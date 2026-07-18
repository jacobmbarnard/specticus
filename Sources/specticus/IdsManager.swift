import Foundation

// MARK: - Traceability IDs manager (implements #6 happy path)
//
// IDs are simple form: BR1, TS2, ADR3, etc. (prefix + integer, no dash, no padding).
// Stored with counters and verbatim content bindings in .specticus/ids.json
// Disjoint from heading numbering (#4).
//
// Counter policy (#33): **monotonic per-prefix high-water mark; never reuse numbers.**
// New IDs always use (max seen for that prefix) + 1. Gaps left by deleted or retired
// requirements are intentional — orphaned entries in ids.json still reserve their numbers
// for audit/traceability integrity. No renumbering and no gap-filling.

enum IdsManager {
    static let knownPrefixes: [String] = ["BR", "TS", "UC", "ADR", "BDR", "TC", "BC", "REF", "DIAG", "REV"]

    struct IdStore: Codable, Equatable, Sendable {
        var version: Int = 1
        /// Per-prefix high-water mark (largest number ever issued or observed). Never decreases (#33).
        var counters: [String: Int] = [:]   // e.g. "BR": 3
        /// ID → descriptive content. Orphan bindings (ID not in Markdown) still reserve numbers (#33).
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
    ///
    /// Per issue #32, only ATX levels **1…`ids.heading_max_level`** may own IDs
    /// (default H1+H2; configurable through H6). Deeper headings are skipped entirely.
    static func collectHeadings(project: SpecticusProject) throws -> [HeadingInfo] {
        let fm = FileManager.default
        let base = project.root
        let maxLevel = SpecticusConfig.IdsSection.clampHeadingMaxLevel(
            project.config.ids.headingMaxLevel
        )

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
                // Issue #32: eligible levels are 1…heading_max_level (default 2 = H1+H2).
                guard level >= SpecticusConfig.IdsSection.minHeadingLevel,
                      level <= maxLevel else { continue }

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

    struct DriftFinding: Equatable, Sendable {
        let id: String
        let oldContent: String
        let newContent: String
        let file: String
    }

    struct MarkdownHeadingFinding: Equatable, Sendable {
        let file: String
        let lineIndex: Int
        let title: String
    }

    /// Main entry for `ids assign`.
    static func assignIDs(project: SpecticusProject, dryRun: Bool) throws {
        let storeURL = project.idsURL
        var store = loadStore(from: storeURL)
        let sensitivity = project.config.ids.driftSensitivity

        let headings = try collectHeadings(project: project)

        var idToInfos: [String: [HeadingInfo]] = [:]
        var headingsNeedingID: [HeadingInfo] = []
        var drifts: [DriftFinding] = []
        var markdownHeadings: [MarkdownHeadingFinding] = []

        // Raise high-water marks from any IDs already recorded in the store (including orphans).
        // Deleted headings must not free their numbers for reuse (#33).
        raiseHighWaterMarks(in: &store)

        // First pass: analyze existing IDs, update store counters/bindings, detect duplicates/drifts
        for h in headings {
            // #36: Markdown emphasis/links/code/HTML in heading titles is disallowed
            let titleForMd = HeadingNumberer.stripOutlinePrefix(from: h.title)
            if headingContainsDisallowedMarkdown(titleForMd) {
                markdownHeadings.append(MarkdownHeadingFinding(
                    file: h.file.lastPathComponent,
                    lineIndex: h.lineIndex,
                    title: titleForMd
                ))
            }

            if let id = h.id {
                idToInfos[id, default: []].append(h)

                // Live IDs also raise the per-prefix high-water mark
                noteObservedID(id, in: &store)

                // Drift check (#36) using configured sensitivity
                if let bound = store.bindings[id],
                   isContentDrift(bound: bound, current: h.content, sensitivity: sensitivity) {
                    drifts.append(DriftFinding(
                        id: id,
                        oldContent: bound,
                        newContent: h.content,
                        file: h.file.lastPathComponent
                    ))
                }

                // (re)bind to current exact text when not drifting (or when first seen).
                // On drift we still stage the rebind in memory but abort write below.
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

        if !markdownHeadings.isEmpty {
            hasProblems = true
            print("❌ Markdown formatting is not allowed in headings (#36):")
            for m in markdownHeadings.prefix(20) {
                print("   \(m.file):\(m.lineIndex + 1): \(m.title)")
            }
            if markdownHeadings.count > 20 {
                print("   ... and \(markdownHeadings.count - 20) more")
            }
            print("   → Use plain text in headings (no **bold**, *italic*, `code`, [links](), or HTML).")
        }

        if !drifts.isEmpty {
            hasProblems = true
            print("⚠️  Content drift detected (ID kept but heading text changed; mode=\(sensitivity.rawValue)):")
            for d in drifts {
                print("   \(d.id):")
                print("     was: \(d.oldContent)")
                print("     now: \(d.newContent)  (\(d.file))")
            }
            print("   → Revert the heading text, or after review rebind one ID at a time:")
            print("      specticus ids accept-drift <ID>   (same identity / reword only — #66)")
        }

        // Per-file context: if a file already owns IDs of one prefix family (e.g. TS1, TS2),
        // new plain-language headings in that file inherit that prefix. This is how a new H2
        // under technical specifications gets TS without needing the word "specification" in the title.
        let fileContextPrefix = dominantPrefixByFile(in: headings)

        // Assign new IDs
        var newlyAssigned: [(info: HeadingInfo, newID: String)] = []
        var skippedCount = 0
        var skippedExamples: [String] = []
        for h in headingsNeedingID {
            guard let prefix = resolvePrefix(for: h, fileContextPrefix: fileContextPrefix[h.file]) else {
                skippedCount += 1
                if skippedExamples.count < 3 {
                    skippedExamples.append("\(h.content) [\(h.file.lastPathComponent)]")
                }
                continue
            }
            // #33: always max+1 per prefix; never reuse gaps or orphaned numbers
            let newID = allocateNextID(prefix: prefix, store: &store)
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
            print("    Tip: put the item in a section file (e.g. 008-technical-specifications.md), use a keyword in the title, or add a manual ID like `## TS3: …`.")
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
            if !newlyAssigned.isEmpty {
                print("ℹ️  \(newlyAssigned.count) heading(s) are ready for new IDs but were not written because of the problems above:")
                for (h, id) in newlyAssigned.prefix(10) {
                    print("     would assign \(id): \(h.content)  [\(h.file.lastPathComponent)]")
                }
                if newlyAssigned.count > 10 {
                    print("     ... and \(newlyAssigned.count - 10) more")
                }
            }
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

    // MARK: - Accept drift (#66)

    /// Structured audit event for deliberate ID rebinds. Appended as one JSON line to
    /// `.specticus/ids-audit.jsonl` (never rewritten in place).
    struct AuditEvent: Codable, Equatable, Sendable {
        var timestamp: String
        var event: String
        var id: String
        var oldContent: String
        var newContent: String
        var source: String
        var actor: String
        var note: String?

        enum CodingKeys: String, CodingKey {
            case timestamp
            case event
            case id
            case oldContent = "old_content"
            case newContent = "new_content"
            case source
            case actor
            case note
        }
    }

    /// Result of a successful `ids accept-drift`.
    struct AcceptDriftResult: Equatable, Sendable {
        let id: String
        let oldContent: String
        let newContent: String
        let source: String
        let actor: String
        let note: String?
        let auditURL: URL
        let storeURL: URL
    }

    /// Failure modes for `acceptDrift`. Callers map these to user-facing errors / non-zero exit.
    enum AcceptDriftError: Error, Equatable, CustomStringConvertible, LocalizedError {
        case notInStore(id: String)
        case notInMarkdown(id: String)
        case duplicateClaims(id: String, locations: [String])
        case noDrift(id: String, content: String)
        case auditWriteFailed(message: String)
        case storeWriteFailed(message: String)

        var description: String {
            switch self {
            case .notInStore(let id):
                return "ID \(id) is not present in .specticus/ids.json bindings. Nothing to rebind."
            case .notInMarkdown(let id):
                return "ID \(id) is not claimed by any eligible heading in Markdown. Cannot accept drift for an orphan binding."
            case .duplicateClaims(let id, let locations):
                let locs = locations.joined(separator: ", ")
                return "ID \(id) is claimed by multiple headings (\(locs)). Resolve the duplicate before accept-drift; do not use accept-drift to merge duplicates."
            case .noDrift(let id, let content):
                return "ID \(id) has no content drift under the current sensitivity (bound text already matches: \"\(content)\"). No changes made."
            case .auditWriteFailed(let message):
                return "Failed to write audit log (binding not updated — fail closed): \(message)"
            case .storeWriteFailed(let message):
                return "Failed to update ids.json after audit log write: \(message)"
            }
        }

        var errorDescription: String? { description }
    }

    /// Explicitly rebind a single ID’s stored content to the current heading text after review.
    ///
    /// This is **accept-drift**, not reassignment:
    /// - Updates only `ids.json` bindings for `<id>`
    /// - Never rewrites the Markdown ID token
    /// - Never mints, renumbers, reuses, or bulk-accepts other IDs
    /// - Requires true drift under `ids.drift_sensitivity` (#36)
    /// - Requires a durable audit log entry; if the log cannot be written, the binding is not updated
    ///
    /// - Parameters:
    ///   - project: Loaded project (paths + config).
    ///   - id: Traceability ID (e.g. `BR1`).
    ///   - note: Optional human reason stored in the audit entry (`--note`).
    ///   - actor: Optional override for the audit actor (defaults to `$USER` / `$LOGNAME` / `"unknown"`).
    ///   - auditURL: Optional override for the audit log path (tests / fail-closed simulation).
    ///   - storeURL: Optional override for `ids.json` path.
    ///   - now: Optional clock for deterministic timestamps in tests.
    @discardableResult
    static func acceptDrift(
        project: SpecticusProject,
        id rawID: String,
        note: String? = nil,
        actor: String? = nil,
        auditURL: URL? = nil,
        storeURL: URL? = nil,
        now: Date = Date()
    ) throws -> AcceptDriftResult {
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedStoreURL = storeURL ?? project.idsURL
        let resolvedAuditURL = auditURL ?? project.idsAuditURL
        let sensitivity = project.config.ids.driftSensitivity
        let resolvedActor = actor ?? currentActor()
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = (trimmedNote?.isEmpty == false) ? trimmedNote : nil

        var store = loadStore(from: resolvedStoreURL)

        guard let oldContent = store.bindings[id] else {
            throw AcceptDriftError.notInStore(id: id)
        }

        let headings = try collectHeadings(project: project)
        let claims = headings.filter { $0.id == id }

        if claims.isEmpty {
            throw AcceptDriftError.notInMarkdown(id: id)
        }
        if claims.count > 1 {
            let locations = claims.map { "\($0.file.lastPathComponent):\($0.lineIndex + 1)" }
            throw AcceptDriftError.duplicateClaims(id: id, locations: locations)
        }

        let heading = claims[0]
        let newContent = heading.content
        let source = "\(heading.file.lastPathComponent):\(heading.lineIndex + 1)"

        // True drift only — same comparison rules as assign/lint (#36).
        guard isContentDrift(bound: oldContent, current: newContent, sensitivity: sensitivity) else {
            throw AcceptDriftError.noDrift(id: id, content: oldContent)
        }

        let event = AuditEvent(
            timestamp: iso8601UTCString(from: now),
            event: "accept-drift",
            id: id,
            oldContent: oldContent,
            newContent: newContent,
            source: source,
            actor: resolvedActor,
            note: noteValue
        )

        // Fail closed: binding update must not commit if the audit log cannot be written.
        do {
            try appendAuditEvent(event, to: resolvedAuditURL)
        } catch let err as AcceptDriftError {
            throw err
        } catch {
            throw AcceptDriftError.auditWriteFailed(message: error.localizedDescription)
        }

        store.bindings[id] = newContent
        do {
            try saveStore(store, to: resolvedStoreURL)
        } catch let err as AcceptDriftError {
            throw err
        } catch {
            throw AcceptDriftError.storeWriteFailed(message: error.localizedDescription)
        }

        print("✅ Accepted drift for \(id) (mode=\(sensitivity.rawValue))")
        print("   was: \(oldContent)")
        print("   now: \(newContent)  (\(source))")
        print("📝 Appended audit entry to \(resolvedAuditURL.lastPathComponent)")
        print("💾 Updated \(resolvedStoreURL.lastPathComponent)")
        print("   Note: accept-drift is for same-identity rewording only — not new requirements or ID reuse.")

        return AcceptDriftResult(
            id: id,
            oldContent: oldContent,
            newContent: newContent,
            source: source,
            actor: resolvedActor,
            note: noteValue,
            auditURL: resolvedAuditURL,
            storeURL: resolvedStoreURL
        )
    }

    /// Appends one JSON object as a single line to the audit log (creates parent dir / file as needed).
    static func appendAuditEvent(_ event: AuditEvent, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Refuse to clobber a directory or other non-file at the audit path.
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            throw AcceptDriftError.auditWriteFailed(
                message: "\(url.lastPathComponent) exists and is a directory"
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event)
        guard var line = String(data: data, encoding: .utf8) else {
            throw AcceptDriftError.auditWriteFailed(message: "could not encode audit event as UTF-8")
        }
        line.append("\n")
        guard let lineData = line.data(using: .utf8) else {
            throw AcceptDriftError.auditWriteFailed(message: "could not encode audit line as UTF-8")
        }

        // Read-modify-write keeps us off newer FileHandle APIs that require a higher
        // macOS deployment target than the package declares (CI builds on macOS).
        // Audit logs stay small; atomic rewrite is appropriate and portable.
        if fm.fileExists(atPath: url.path) {
            var combined = try Data(contentsOf: url)
            combined.append(lineData)
            try combined.write(to: url, options: .atomic)
        } else {
            try lineData.write(to: url, options: .atomic)
        }
    }

    /// Loads all audit events from a JSONL file (skips blank lines). Used by tests and tooling.
    static func loadAuditEvents(from url: URL) throws -> [AuditEvent] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        var events: [AuditEvent] = []
        for (idx, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            do {
                let data = Data(trimmed.utf8)
                events.append(try decoder.decode(AuditEvent.self, from: data))
            } catch {
                throw AcceptDriftError.auditWriteFailed(
                    message: "malformed audit log line \(idx + 1): \(error.localizedDescription)"
                )
            }
        }
        return events
    }

    private static func currentActor() -> String {
        if let user = ProcessInfo.processInfo.environment["USER"], !user.isEmpty {
            return user
        }
        if let logname = ProcessInfo.processInfo.environment["LOGNAME"], !logname.isEmpty {
            return logname
        }
        return "unknown"
    }

    private static func iso8601UTCString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
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

    /// Resolves which ID prefix to use when assigning a new ID to a heading.
    ///
    /// Priority:
    /// 1. Keywords in the heading text itself
    /// 2. Section filename (skeleton `00N-technical-specifications.md`, etc.)
    /// 3. Dominant prefix already used by other owned IDs in the same file (sibling context)
    private static func resolvePrefix(for heading: HeadingInfo, fileContextPrefix: String?) -> String? {
        if let fromContent = inferPrefixFromContent(heading.content) {
            return fromContent
        }
        if let fromFile = inferPrefixFromFilename(heading.file.lastPathComponent) {
            return fromFile
        }
        return fileContextPrefix
    }

    /// Most common ID prefix among headings that already own an ID in each file.
    private static func dominantPrefixByFile(in headings: [HeadingInfo]) -> [URL: String] {
        var counts: [URL: [String: Int]] = [:]
        for h in headings {
            guard let id = h.id, let prefix = prefixOf(id: id) else { continue }
            counts[h.file, default: [:]][prefix, default: 0] += 1
        }
        var result: [URL: String] = [:]
        for (file, prefixCounts) in counts {
            if let best = prefixCounts.max(by: { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                // Stable tie-break: prefer earlier knownPrefixes entry
                let li = knownPrefixes.firstIndex(of: lhs.key) ?? Int.max
                let ri = knownPrefixes.firstIndex(of: rhs.key) ?? Int.max
                return li > ri
            }) {
                result[file] = best.key
            }
        }
        return result
    }

    /// Infer prefix from heading descriptive text only (not filenames).
    private static func inferPrefixFromContent(_ text: String) -> String? {
        let lower = text.lowercased()

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
        if lower.contains("technical constraint") {
            return "TC"
        }
        if lower.contains("business constraint") || lower.contains("constraint") {
            return "BC"
        }
        if lower.contains("business decision") || lower.contains("bdr") {
            return "BDR"
        }
        if lower.contains("architecture decision") || lower.contains("adr") || lower.contains("decision") {
            return "ADR"
        }
        if lower.contains("diagram") {
            return "DIAG"
        }
        if lower.contains("revision") {
            return "REV"
        }
        return nil
    }

    /// Infer prefix from a Markdown filename (skeleton section names and common aliases).
    private static func inferPrefixFromFilename(_ filename: String) -> String? {
        var base = filename.lowercased()
        if let dot = base.lastIndex(of: ".") {
            base = String(base[..<dot])
        }
        // Normalize separators so both "technical-specifications" and "technical_specifications" match.
        let normalized = base.replacingOccurrences(of: "_", with: "-")

        // Most specific patterns first (skeleton 00N-* names).
        if normalized.contains("business-requirement") || normalized.contains("business-requirements") {
            return "BR"
        }
        if normalized.contains("technical-specification")
            || normalized.contains("technical-specifications")
            || normalized.contains("technical-spec")
            || normalized.contains("tech-spec") {
            return "TS"
        }
        if normalized.contains("business-constraint") || normalized.contains("business-constraints") {
            return "BC"
        }
        if normalized.contains("technical-constraint") || normalized.contains("technical-constraints") {
            return "TC"
        }
        if normalized.contains("use-case") || normalized.contains("use-cases") {
            return "UC"
        }
        if normalized.contains("test-plan") || normalized.contains("test-case") || normalized.contains("test-cases") {
            return "TC"
        }
        if normalized.contains("business-decision") || normalized.contains("bdr") {
            return "BDR"
        }
        if normalized.contains("architecture") || normalized.contains("-adr") || normalized.hasPrefix("adr") {
            return "ADR"
        }
        if normalized.contains("diagram") {
            return "DIAG"
        }
        if normalized.contains("revision") {
            return "REV"
        }
        // Weaker filename fallbacks (still useful for non-skeleton layouts).
        if normalized.contains("requirement") {
            return "BR"
        }
        if normalized.contains("specification") || normalized.hasSuffix("-specs")
            || normalized.hasSuffix("-spec") || normalized == "specs" || normalized == "spec" {
            return "TS"
        }
        if normalized.contains("constraint") {
            return "BC"
        }
        return nil
    }

    /// Legacy entry used by tests / call sites that pass free-form text (content or filename).
    private static func inferPrefix(from text: String) -> String? {
        // Prefer content-style matching; if it looks like a filename, try filename rules too.
        if let fromContent = inferPrefixFromContent(text) {
            return fromContent
        }
        if text.contains(".") || text.contains("-") || text.contains("_") || text.contains("/") {
            return inferPrefixFromFilename(text)
        }
        return nil
    }

    // MARK: - Drift comparison (#36)

    /// Whether bound vs current heading text counts as content drift under `sensitivity`.
    static func isContentDrift(
        bound: String,
        current: String,
        sensitivity: SpecticusConfig.DriftSensitivity
    ) -> Bool {
        !contentsMatch(bound, current, sensitivity: sensitivity)
    }

    /// Compare two heading content strings according to #36 sensitivity rules.
    static func contentsMatch(
        _ a: String,
        _ b: String,
        sensitivity: SpecticusConfig.DriftSensitivity
    ) -> Bool {
        switch sensitivity {
        case .strict:
            // Utter strictness: any character difference is a change.
            return a == b
        case .contentStrict, .contentStrictPlus:
            return normalizeForDriftComparison(a, sensitivity: sensitivity)
                == normalizeForDriftComparison(b, sensitivity: sensitivity)
        }
    }

    /// Normalizes text for non-strict drift comparison.
    ///
    /// - `contentStrict`: lowercases letters; collapses whitespace runs to a single space
    ///   (whitespace may grow/shrink between tokens but not disappear so tokens merge).
    /// - `contentStrictPlus`: same, then treats punctuation/symbols as whitespace (so they
    ///   may change or vanish without counting as drift).
    static func normalizeForDriftComparison(
        _ text: String,
        sensitivity: SpecticusConfig.DriftSensitivity
    ) -> String {
        switch sensitivity {
        case .strict:
            return text
        case .contentStrict:
            return collapseWhitespace(text.lowercased())
        case .contentStrictPlus:
            let lowered = text.lowercased()
            var scalars: [UnicodeScalar] = []
            scalars.reserveCapacity(lowered.unicodeScalars.count)
            for s in lowered.unicodeScalars {
                if CharacterSet.punctuationCharacters.contains(s)
                    || CharacterSet.symbols.contains(s) {
                    scalars.append(" ")
                } else {
                    scalars.append(s)
                }
            }
            return collapseWhitespace(String(String.UnicodeScalarView(scalars)))
        }
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split { $0.isWhitespace }.joined(separator: " ")
    }

    /// Detects Markdown/HTML formatting that must not appear in heading titles (#36).
    ///
    /// Flags: bold/italic markers, inline code, links/images, strikethrough, raw HTML tags.
    static func headingContainsDisallowedMarkdown(_ title: String) -> Bool {
        if title.contains("`") { return true }
        // Bold **...** or __...__
        if title.range(of: #"\*\*[^*]+\*\*"#, options: .regularExpression) != nil { return true }
        if title.range(of: #"__[^_]+__"#, options: .regularExpression) != nil { return true }
        // Italic *...* (not part of **)
        if title.range(of: #"(?<!\*)\*(?!\*)([^*]+)\*(?!\*)"#, options: .regularExpression) != nil {
            return true
        }
        // Italic _..._ (not part of __) — require word-ish boundaries via non-underscore interior
        if title.range(of: #"(?<![A-Za-z0-9_])_([^_]+)_(?![A-Za-z0-9_])"#, options: .regularExpression) != nil {
            return true
        }
        // Links / images [text](url) or ![alt](url)
        if title.range(of: #"!?\[[^\]]*\]\([^)]+\)"#, options: .regularExpression) != nil { return true }
        // Strikethrough
        if title.range(of: #"~~[^~]+~~"#, options: .regularExpression) != nil { return true }
        // Raw HTML tags
        if title.range(of: #"</?[A-Za-z][^>]*>"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// Collect drift findings for lint/build using the project's configured sensitivity.
    static func findContentDrifts(
        headings: [HeadingInfo],
        store: IdStore,
        sensitivity: SpecticusConfig.DriftSensitivity
    ) -> [DriftFinding] {
        var findings: [DriftFinding] = []
        for h in headings {
            guard let id = h.id, let bound = store.bindings[id] else { continue }
            if isContentDrift(bound: bound, current: h.content, sensitivity: sensitivity) {
                findings.append(DriftFinding(
                    id: id,
                    oldContent: bound,
                    newContent: h.content,
                    file: h.file.lastPathComponent
                ))
            }
        }
        return findings
    }

    /// Headings (eligible for IDs) whose titles contain disallowed Markdown (#36).
    static func findMarkdownFormattedHeadings(in headings: [HeadingInfo]) -> [MarkdownHeadingFinding] {
        headings.compactMap { h in
            let title = HeadingNumberer.stripOutlinePrefix(from: h.title)
            guard headingContainsDisallowedMarkdown(title) else { return nil }
            return MarkdownHeadingFinding(
                file: h.file.lastPathComponent,
                lineIndex: h.lineIndex,
                title: title
            )
        }
    }

    // MARK: - Counter policy (#33)

    /// Policy: **monotonic per-prefix high-water mark; never reuse.**
    ///
    /// When allocating a new ID for prefix `P`:
    /// 1. Compute `high = max(store.counters[P], max number among bindings with prefix P)`.
    /// 2. Issue `P(high + 1)` and set `counters[P] = high + 1`.
    ///
    /// Consequences (intentional):
    /// - Deleting a heading leaves a **gap** (e.g. BR1, BR3 present → next is BR4, not BR2).
    /// - Orphan bindings in `ids.json` (ID removed from Markdown but still recorded) **reserve**
    ///   their numbers so historical references stay unambiguous.
    /// - Counters never decrease; a stale high counter is trusted over gap-filling.
    /// - Prefixes are independent (BR and TS counters do not interact).
    ///
    /// Non-goals: lowest-unused reuse, renumbering/compaction, configurable reuse modes.
    static func highWaterMark(for prefix: String, store: IdStore) -> Int {
        var high = store.counters[prefix] ?? 0
        for id in store.bindings.keys {
            guard let p = prefixOf(id: id), p == prefix else { continue }
            high = max(high, numberOf(id: id))
        }
        return high
    }

    /// Raises `store.counters` so each known prefix is at least the max number in bindings.
    private static func raiseHighWaterMarks(in store: inout IdStore) {
        var raised: [String: Int] = store.counters
        for id in store.bindings.keys {
            guard let prefix = prefixOf(id: id) else { continue }
            let num = numberOf(id: id)
            raised[prefix] = max(raised[prefix] ?? 0, num)
        }
        store.counters = raised
    }

    /// Records an observed ID into the high-water mark (does not create bindings).
    private static func noteObservedID(_ id: String, in store: inout IdStore) {
        guard let prefix = prefixOf(id: id) else { return }
        let num = numberOf(id: id)
        store.counters[prefix] = max(store.counters[prefix] ?? 0, num)
    }

    /// Allocates the next ID for `prefix` using the #33 max+1 policy and advances the counter.
    static func allocateNextID(prefix: String, store: inout IdStore) -> String {
        let next = highWaterMark(for: prefix, store: store) + 1
        store.counters[prefix] = next
        return "\(prefix)\(next)"
    }

    private static func prefixOf(id: String) -> String? {
        // Longest prefix first so e.g. BDR wins over BR if both ever matched.
        let ordered = knownPrefixes.sorted { $0.count > $1.count }
        for p in ordered where id.hasPrefix(p) {
            // Require that the remainder starts with a digit (BR1, not BROKEN)
            let rest = id.dropFirst(p.count)
            if let first = rest.first, first.isNumber {
                return p
            }
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
