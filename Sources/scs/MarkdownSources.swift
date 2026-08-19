import Foundation

// MARK: - Shared Markdown content discovery (#35 / #139)
//
// Single owner of “which Markdown files count as project content”:
// - `*.md` / `*.markdown`
// - exclude README* and welcome-template.md (assembly skip list)
// - exclude hidden paths (e.g. `.specticus/`)
// - **Vertical layout (#139):** recurse known section folders in pack order, then
//   lex by relative path within each section; also include leftover root `.md` files
// - **Legacy flat layout:** top-level files only, lex by filename
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

    /// Discover content Markdown files for assembly / ID scan.
    ///
    /// - Vertical projects (#139): section folders in `TemplateSections.defaultOrder`,
    ///   recursive under each; then any remaining root-level content files (hybrid compat).
    /// - Flat projects: top-level content files only (legacy #3 / #35).
    ///
    /// Does **not** apply single-file mode or welcome-template fallback — callers handle that.
    static func discoverContentFiles(in directory: URL) throws -> [URL] {
        let root = directory.standardizedFileURL
        if TemplateSections.usesVerticalLayout(at: root) {
            return try discoverVerticalContentFiles(in: root)
        }
        return try discoverFlatContentFiles(in: root)
    }

    /// Legacy: top-level `*.md` only, lex by filename.
    static func discoverFlatContentFiles(in directory: URL) throws -> [URL] {
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

    /// Vertical pack: ordered sections + recursive files, then leftover root files.
    static func discoverVerticalContentFiles(in directory: URL) throws -> [URL] {
        let fm = FileManager.default
        let root = directory.standardizedFileURL
        var ordered: [URL] = []
        var seen = Set<String>()

        func appendUnique(_ url: URL) {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                ordered.append(url.standardizedFileURL)
            }
        }

        for sectionID in TemplateSections.defaultOrder {
            let sectionURL = root.appendingPathComponent(sectionID, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: sectionURL.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            let found = try collectMarkdownRecursively(under: sectionURL, projectRoot: root)
            for url in found {
                appendUnique(url)
            }
        }

        // Hybrid: root-level content Markdown not already collected (migration / extras).
        for url in try discoverFlatContentFiles(in: root) {
            appendUnique(url)
        }

        return ordered
    }

    /// Recursively collect content Markdown under `directory`, sorted by relative path (lex).
    static func collectMarkdownRecursively(under directory: URL, projectRoot: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var found: [URL] = []
        for case let fileURL as URL in enumerator {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
                continue
            }
            guard isContentMarkdownFilename(fileURL.lastPathComponent) else { continue }
            found.append(fileURL.standardizedFileURL)
        }

        let rootPath = projectRoot.standardizedFileURL.path
        return found.sorted { a, b in
            relativePath(a, from: rootPath) < relativePath(b, from: rootPath)
        }
    }

    private static func relativePath(_ url: URL, from rootPath: String) -> String {
        let path = url.standardizedFileURL.path
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
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
