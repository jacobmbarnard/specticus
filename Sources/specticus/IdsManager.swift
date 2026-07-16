import Foundation

// MARK: - Traceability IDs manager (implements #6 happy path)
//
// IDs are simple form: BR1, TS2, ADR3, etc. (prefix + integer, no dash, no padding).
// Stored with counters and verbatim content bindings in .specticus/ids.json
// Disjoint from heading numbering (#4).

enum IdsManager {
    static let knownPrefixes: [String] = ["BR", "TS", "UC", "ADR", "BDR", "TC", "BC", "REF", "DIAG", "REV"]

    struct IdStore: Codable, Equatable, Sendable {
        var version: Int = 1
        var counters: [String: Int] = [:]   // e.g. "BR": 3
        var bindings: [String: String] = [:] // e.g. "BR1": "User Login"
    }

    struct HeadingInfo {
        let file: URL
        let lineIndex: Int
        let originalLine: String
        let level: Int
        let title: String          // raw title text
        let id: String?            // "BR1" or nil
        let content: String        // descriptive text after ID or full title
    }

    // MARK: - Public API

    static func loadStore(from url: URL) -> IdStore {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return IdStore() }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(IdStore.self, from: data)
        } catch {
            print("⚠️  Could not read \(url.lastPathComponent), starting fresh: \(error)")
            return IdStore()
        }
    }

    static func saveStore(_ store: IdStore, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        try data.write(to: url, options: .atomic)
    }

    /// Scans the project's content Markdown (top-level like assembleSources) and returns heading info.
    ///
    /// Per issue #30, the ID scanner **ignores** headings that appear inside:
    /// - Fenced code blocks (``` or ~~~)
    /// - Blockquotes (lines starting with `>`)
    /// - HTML comments (<!-- ... -->)
    /// - Tables (lines starting with `|`)
    /// This prevents accidental ID assignment or drift detection for example code and non-body content.
    static func collectHeadings(project: SpecticusProject) throws -> [HeadingInfo] {
        let fm = FileManager.default
        let base = project.root

        let contents = try fm.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let mdFiles = contents
            .filter { url in
                let name = url.lastPathComponent.lowercased()
                return (name.hasSuffix(".md") || name.hasSuffix(".markdown")) &&
                       name != "readme.md" &&
                       name != "readme.markdown" &&
                       name != "welcome-template.md"
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var results: [HeadingInfo] = []

        for file in mdFiles {
            let raw = try String(contentsOf: file, encoding: .utf8)
            let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

            var inFence = false
            var inComment = false

            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Track fenced code blocks (``` or ~~~)
                if isFenceDelimiter(trimmed) {
                    inFence.toggle()
                    continue
                }
                if inFence { continue }

                // Track HTML comments (multi-line aware)
                if trimmed.hasPrefix("<!--") {
                    inComment = true
                    // Check for immediate close on same line
                    if trimmed.contains("-->") {
                        inComment = false
                    }
                    continue
                }
                if inComment {
                    if trimmed.contains("-->") {
                        inComment = false
                    }
                    continue
                }

                // Skip blockquotes (lines starting with > after optional ws)
                if trimmed.hasPrefix(">") { continue }

                // Skip table rows (conservative: anything starting with | after ws)
                if trimmed.hasPrefix("|") { continue }

                guard let (level, title) = parseATXHeading(line) else { continue }
                guard level >= 2 else { continue }  // IDs for H2+ (H1 is doc title)

                // Issue #34: strip hierarchical outline numbering (#4) before ID detection.
                // Sources may mix numbered (`## 1.2. BR1: …`) and unnumbered (`## BR1: …`)
                // headings; outline prefixes are presentation-only and must not affect IDs.
                // Completely disjoint from heading numbering — we only strip, never invent numbers.
                let cleaned = HeadingNumberer.stripOutlinePrefix(from: title)

                if let (id, content) = parseID(from: cleaned) {
                    results.append(HeadingInfo(
                        file: file,
                        lineIndex: idx,
                        originalLine: line,
                        level: level,
                        title: title,
                        id: id,
                        content: content
                    ))
                } else {
                    results.append(HeadingInfo(
                        file: file,
                        lineIndex: idx,
                        originalLine: line,
                        level: level,
                        title: title,
                        id: nil,
                        content: cleaned
                    ))
                }
            }
        }

        return results
    }

    private static func isFenceDelimiter(_ trimmed: String) -> Bool {
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    /// Main entry for `ids assign`.
    static func assignIDs(project: SpecticusProject, dryRun: Bool) throws {
        let storeURL = project.idsURL
        var store = loadStore(from: storeURL)

        let headings = try collectHeadings(project: project)

        var idToInfos: [String: [HeadingInfo]] = [:]
        var headingsNeedingID: [HeadingInfo] = []
        var drifts: [(id: String, oldContent: String, newContent: String, file: String)] = []

        // First pass: analyze existing IDs, update store counters/bindings, detect duplicates/drifts
        for h in headings {
            if let id = h.id {
                idToInfos[id, default: []].append(h)

                // update counters
                if let prefix = prefixOf(id: id) {
                    let num = numberOf(id: id)
                    store.counters[prefix] = max(store.counters[prefix] ?? 0, num)
                }

                // drift check
                if let bound = store.bindings[id], bound != h.content {
                    drifts.append((id: id, oldContent: bound, newContent: h.content, file: h.file.lastPathComponent))
                }

                // (re)bind
                store.bindings[id] = h.content
            } else {
                headingsNeedingID.append(h)
            }
        }

        // duplicates?
        let duplicateIDs = idToInfos.filter { $0.value.count > 1 }.keys.sorted()

        // Report problems
        var hasProblems = false
        if !duplicateIDs.isEmpty {
            hasProblems = true
            print("❌ Duplicate IDs found (must be unique):")
            for id in duplicateIDs {
                print("   \(id)")
                for h in idToInfos[id]! {
                    print("     - \(h.file.lastPathComponent): \(h.content)")
                }
            }
        }

        if !drifts.isEmpty {
            hasProblems = true
            print("⚠️  Content drift detected (ID kept but heading text changed):")
            for d in drifts {
                print("   \(d.id):")
                print("     was: \(d.oldContent)")
                print("     now: \(d.newContent)  (\(d.file))")
            }
        }

        // Assign new IDs
        var newlyAssigned: [(info: HeadingInfo, newID: String)] = []
        var skippedCount = 0
        var skippedExamples: [String] = []
        for h in headingsNeedingID {
            guard let prefix = inferPrefix(from: h.content) ?? inferPrefix(from: h.file.lastPathComponent) else {
                skippedCount += 1
                if skippedExamples.count < 3 {
                    skippedExamples.append("\(h.content) [\(h.file.lastPathComponent)]")
                }
                continue
            }
            let next = (store.counters[prefix] ?? 0) + 1
            let newID = "\(prefix)\(next)"
            store.counters[prefix] = next
            store.bindings[newID] = h.content
            newlyAssigned.append((h, newID))
        }

        if skippedCount > 0 {
            print("ℹ️  Skipped \(skippedCount) heading(s) (no prefix inferred — these are likely structural/document sections rather than traceable items like requirements, constraints or diagrams).")
            for ex in skippedExamples {
                print("    e.g. \(ex)")
            }
            if skippedCount > skippedExamples.count {
                print("    ... and \(skippedCount - skippedExamples.count) more")
            }
        }

        if dryRun {
            if !newlyAssigned.isEmpty {
                print("Would assign the following IDs (dry-run):")
                for (h, id) in newlyAssigned {
                    print("  \(id): \(h.content)  [\(h.file.lastPathComponent)]")
                }
            }
            if hasProblems {
                print("Note: problems above would block actual assignment.")
            }
            // For dry-run we still want to show current state, but no write
            if newlyAssigned.isEmpty && !hasProblems {
                print("✅ No IDs to assign. Everything looks good.")
            }
            return
        }

        if hasProblems {
            print("Aborting write due to duplicates or drift. Fix issues and re-run `ids assign`.")
            // Do not mutate bindings on problems (user should resolve drift/dupe first)
            return
        }

        if newlyAssigned.isEmpty {
            // Bootstrap / persist current bindings even if no new assignments
            try saveStore(store, to: storeURL)
            print("💾 Updated \(storeURL.lastPathComponent) (no new IDs assigned)")
            return
        }

        // Apply rewrites
        let byFile = Dictionary(grouping: newlyAssigned, by: { $0.info.file })

        for (file, items) in byFile {
            var lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)

            for (h, id) in items {
                lines[h.lineIndex] = addIDPrefix(to: h.originalLine, id: id)
            }

            let joined = lines.joined(separator: "\n")
            let final = lines.last == "" ? joined : joined + "\n"  // try to preserve trailing newline-ish
            try final.write(to: file, atomically: true, encoding: .utf8)
            print("✍️  Assigned \(items.count) ID(s) in \(file.lastPathComponent)")
        }

        try saveStore(store, to: storeURL)
        print("💾 Updated \(storeURL.lastPathComponent)")
    }

    // MARK: - Helpers

    private static func parseATXHeading(_ line: String) -> (level: Int, title: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(#{1,6})\s+(.*)$"#) else { return nil }
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let hashes = ns.substring(with: m.range(at: 1))
        var title = ns.substring(with: m.range(at: 2))
        // trim trailing #s like in TOC parser
        if let trail = title.range(of: #"\s+#+\s*$"#, options: .regularExpression) {
            title = String(title[..<trail.lowerBound])
        }
        title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return (hashes.count, title)
    }

    /// Parses a traceability ID from an outline-stripped heading title according to the
    /// exact syntax rules defined in issue #31.
    ///
    /// Rules (must match exactly after `HeadingNumberer.stripOutlinePrefix`):
    /// - ID must be the very first token: `ID ::= PREFIX DIGITS`
    /// - PREFIX ::= [A-Z]{1,4}   (e.g. BR, TS, ADR, UC, BC, TC, DIAG, REV, BDR)
    /// - DIGITS ::= [1-9][0-9]*  (no leading zero, no padding)
    /// - Must be immediately followed by a required delimiter: `:`, `.`, or whitespace
    /// - Only knownPrefixes are accepted
    /// - ID at any other position, with brackets, dashes, lowercase, or inside non-heading
    ///   content is rejected (see also #30 for content-type filtering).
    private static func parseID(from title: String) -> (id: String, content: String)? {
        // title must already be outline-stripped; we require the ID at absolute start
        let pattern = #"^([A-Z]{1,4})([1-9]\d*)([:.\s]+)(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = title as NSString
        guard let m = regex.firstMatch(in: title, range: NSRange(0..<ns.length)) else { return nil }

        let prefix = ns.substring(with: m.range(at: 1))
        let numPart = ns.substring(with: m.range(at: 2))
        let rest = ns.substring(with: m.range(at: 4)).trimmingCharacters(in: .whitespaces)

        guard knownPrefixes.contains(prefix) else { return nil }
        let id = "\(prefix)\(numPart)"
        let content = rest.isEmpty ? title : rest
        return (id, content)
    }

    private static func inferPrefix(from text: String) -> String? {
        let lower = text.lowercased()

        // Filename hints
        if lower.contains("business-constraint") || lower.contains("business constraint") {
            return "BC"
        }
        if lower.contains("technical-constraint") || lower.contains("technical constraint") {
            return "TC"
        }
        if lower.contains("diagram") {
            return "DIAG"
        }
        if lower.contains("revision") {
            return "REV"
        }

        // Content based
        if lower.contains("business requirement") || lower.contains("requirement") || lower.contains("shall ") {
            return "BR"
        }
        if lower.contains("technical specification") || lower.contains("specification") {
            return "TS"
        }
        if lower.contains("use case") {
            return "UC"
        }
        if lower.contains("test case") || lower.contains("test plan") {
            return "TC"
        }
        if lower.contains("business constraint") || lower.contains("constraint") {
            return "BC"
        }
        if lower.contains("technical constraint") {
            return "TC"
        }
        if lower.contains("architecture decision") || lower.contains("adr") || lower.contains("decision") {
            return "ADR"
        }
        if lower.contains("business decision") || lower.contains("bdr") {
            return "BDR"
        }
        if lower.contains("diagram") {
            return "DIAG"
        }
        if lower.contains("revision") {
            return "REV"
        }
        return nil
    }

    private static func prefixOf(id: String) -> String? {
        for p in knownPrefixes where id.hasPrefix(p) {
            return p
        }
        return nil
    }

    private static func numberOf(id: String) -> Int {
        let digits = id.drop { !$0.isNumber }
        return Int(digits) ?? 0
    }

    /// Inserts a newly assigned ID into an ATX heading line.
    ///
    /// Per issue #34, if the heading already has a hierarchical outline prefix
    /// (e.g. `## 1.2. User Login`), the ID is placed **after** that prefix so the
    /// line becomes `## 1.2. BR1: User Login`. Putting the ID before the outline
    /// would break subsequent scans and pollute content bindings with outline text.
    /// We never invent or modify outline numbers here (disjoint from #4).
    private static func addIDPrefix(to line: String, id: String) -> String {
        // Match ATX heading and insert ID after the hashes+space (and after any outline prefix)
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*)(#{1,6})(\s+)(.*)$"#) else { return line }
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return line }

        let indent = ns.substring(with: m.range(at: 1))
        let hashes = ns.substring(with: m.range(at: 2))
        let space = ns.substring(with: m.range(at: 3))
        let rest = ns.substring(with: m.range(at: 4))

        // Preserve an existing outline prefix from #4 if present in source (mixed files).
        if let outlineRange = rest.range(of: #"^\d+(?:\.\d+)*\.\s+"#, options: .regularExpression) {
            let outline = String(rest[outlineRange])
            let afterOutline = String(rest[outlineRange.upperBound...])
            let newTitle = "\(outline)\(id): \(afterOutline)"
            return "\(indent)\(hashes)\(space)\(newTitle)"
        }

        let newTitle = "\(id): \(rest)"
        return "\(indent)\(hashes)\(space)\(newTitle)"
    }
}
