import Foundation

// MARK: - Shared Markdown content discovery (#35)
//
// Single owner of “which top-level Markdown files count as project content”:
// - `*.md` / `*.markdown`
// - exclude README* and welcome-template.md (assembly skip list)
// - exclude hidden paths via FileManager `.skipsHiddenFiles` (e.g. `.specticus/`)
// - lexicographic order by filename
//
// Used by `DocumentGenerator.assembleSources`, `IdsManager.collectHeadings`, and
// any preflight that must see the same file set as assign/lint/build ID paths.

enum MarkdownSources {
    /// Filenames that are Markdown but never multi-file content sources.
    static let excludedContentFilenames: Set<String> = [
        "readme.md",
        "readme.markdown",
        "welcome-template.md"
    ]

    /// Whether `name` is a project content Markdown filename (case-insensitive).
    static func isContentMarkdownFilename(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard lower.hasSuffix(".md") || lower.hasSuffix(".markdown") else { return false }
        return !excludedContentFilenames.contains(lower)
    }

    /// Discover top-level content Markdown files under `directory` in lex order.
    ///
    /// Mirrors the multi-file discovery historically inlined in assemble + collectHeadings.
    /// Does **not** apply single-file mode or welcome-template fallback — callers handle that.
    static func discoverContentFiles(in directory: URL) throws -> [URL] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { isContentMarkdownFilename($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: Shared line primitives (fence / ATX)

    /// True when a trimmed line opens or closes a fenced code block (``` or ~~~).
    static func isFenceDelimiter(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~")
    }

    /// Parse an ATX heading (`#`…`######` + title). Returns level and title text.
    /// Trailing `#` decorations are stripped from the title (GFM-style).
    static func parseATXHeading(_ line: String) -> (level: Int, title: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(#{1,6})\s+(.*)$"#) else {
            return nil
        }
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let hashes = ns.substring(with: m.range(at: 1))
        var title = ns.substring(with: m.range(at: 2))
        if let trail = title.range(of: #"\s+#+\s*$"#, options: .regularExpression) {
            title = String(title[..<trail.lowerBound])
        }
        title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return (hashes.count, title)
    }

    // MARK: - Unresolved merge conflict markers (#39, SCM-agnostic)

    /// Kind of unresolved VCS merge conflict marker found in a source file.
    ///
    /// Markers are plain-text conventions shared by Git, Mercurial, Fossil, SVN, and
    /// similar tools. specticus does **not** invoke any SCM — it only inspects file text.
    enum ConflictMarkerKind: String, Equatable, Sendable {
        case start   // <<<<<<<
        case middle  // ======= (only when start/end also present in the same file)
        case end     // >>>>>>>
    }

    /// One conflict-marker hit (file + 1-based line + kind).
    struct ConflictMarkerFinding: Equatable, Sendable {
        let file: String
        let lineIndex: Int
        let kind: ConflictMarkerKind
        let linePreview: String
    }

    /// True when a trimmed line is an unambiguous conflict start (`<<<<<<<…`).
    static func isConflictStartMarker(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("<<<<<<<")
    }

    /// True when a trimmed line is an unambiguous conflict end (`>>>>>>>…`).
    static func isConflictEndMarker(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix(">>>>>>>")
    }

    /// True when a trimmed line is a bare conflict separator (`=======` only).
    ///
    /// Requires the whole line (after trim) to be seven or more `=` characters so we
    /// do not flag ordinary Markdown setext underlines that sit under a title on the
    /// previous line without accompanying `<<<<<<<` / `>>>>>>>` (see `findConflictMarkers`).
    static func isConflictMiddleMarker(_ trimmedLine: String) -> Bool {
        guard trimmedLine.count >= 7 else { return false }
        return trimmedLine.allSatisfy { $0 == "=" }
    }

    /// Scan text for unresolved merge conflict markers (#39).
    ///
    /// - `<<<<<<<` / `>>>>>>>` always count.
    /// - Bare `=======` lines count only when the same file also has a start or end
    ///   marker, reducing false positives on setext-style underlines.
    static func findConflictMarkers(in text: String, fileDisplayName: String) -> [ConflictMarkerFinding] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var startsAndEnds: [(idx: Int, kind: ConflictMarkerKind, preview: String)] = []
        var middles: [(idx: Int, preview: String)] = []

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isConflictStartMarker(trimmed) {
                startsAndEnds.append((idx, .start, trimmed))
            } else if isConflictEndMarker(trimmed) {
                startsAndEnds.append((idx, .end, trimmed))
            } else if isConflictMiddleMarker(trimmed) {
                middles.append((idx, trimmed))
            }
        }

        var findings: [ConflictMarkerFinding] = []
        for item in startsAndEnds {
            findings.append(ConflictMarkerFinding(
                file: fileDisplayName,
                lineIndex: item.idx,
                kind: item.kind,
                linePreview: item.preview
            ))
        }
        // Only attach middle markers when the file is clearly in a conflicted state.
        if !startsAndEnds.isEmpty {
            for m in middles {
                findings.append(ConflictMarkerFinding(
                    file: fileDisplayName,
                    lineIndex: m.idx,
                    kind: .middle,
                    linePreview: m.preview
                ))
            }
        }

        return findings.sorted { lhs, rhs in
            if lhs.lineIndex != rhs.lineIndex { return lhs.lineIndex < rhs.lineIndex }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }

    /// Scan a file on disk; returns empty if unreadable or missing.
    static func findConflictMarkers(inFile url: URL, displayName: String? = nil) -> [ConflictMarkerFinding] {
        let name = displayName ?? url.lastPathComponent
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return findConflictMarkers(in: text, fileDisplayName: name)
    }
}

// MARK: - Git workspace helpers for assign safety (#35)

enum GitWorkspace {
    /// Whether `directory` is inside a Git work tree.
    static func isInsideWorkTree(at directory: URL) -> Bool {
        let result = runGit(["rev-parse", "--is-inside-work-tree"], cwd: directory)
        return result.exitCode == 0 && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    /// Paths (relative to `directory` when possible) among `candidates` that have uncommitted changes.
    ///
    /// Uses `git status --porcelain`. Returns empty if not a git repo or git is unavailable.
    static func dirtyPaths(among candidates: [URL], in directory: URL) -> [String] {
        guard !candidates.isEmpty, isInsideWorkTree(at: directory) else { return [] }

        let root = directory.standardizedFileURL
        var relativeArgs: [String] = []
        var displayByRelative: [String: String] = [:]

        for url in candidates {
            let standardized = url.standardizedFileURL
            let rel: String
            if standardized.path.hasPrefix(root.path + "/") {
                rel = String(standardized.path.dropFirst(root.path.count + 1))
            } else {
                rel = standardized.lastPathComponent
            }
            relativeArgs.append(rel)
            displayByRelative[rel] = url.lastPathComponent
        }

        // `git status --porcelain -- path…` lists dirty entries for those paths only.
        let result = runGit(["status", "--porcelain", "--"] + relativeArgs, cwd: directory)
        guard result.exitCode == 0 else { return [] }

        var dirty: [String] = []
        for line in result.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            // porcelain: XY PATH or XY ORIG -> PATH
            let raw = String(line)
            guard raw.count >= 4 else { continue }
            let pathPart = String(raw.dropFirst(3))
            let path: String
            if let arrow = pathPart.range(of: " -> ") {
                path = String(pathPart[arrow.upperBound...])
            } else {
                path = pathPart
            }
            let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            dirty.append(displayByRelative[trimmed] ?? (trimmed as NSString).lastPathComponent)
        }
        // Stable unique
        var seen = Set<String>()
        return dirty.filter { seen.insert($0).inserted }
    }

    private struct GitResult {
        let exitCode: Int32
        let stdout: String
    }

    private static func runGit(_ arguments: [String], cwd: URL) -> GitResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = cwd
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return GitResult(exitCode: process.terminationStatus, stdout: text)
        } catch {
            return GitResult(exitCode: 127, stdout: "")
        }
    }
}
