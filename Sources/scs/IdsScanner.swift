import Foundation

// MARK: - Traceability ID scanner (internals #20)
//
// Eligible headings from the MarkdownDocument model (#18): structural-title skip,
// owning-ID parse, exclusion zones. No printing.

enum IdsScanner {
    struct HeadingInfo {
        let file: URL
        let lineIndex: Int
        let originalLine: String
        let level: Int
        let title: String          // raw title text
        let id: String?            // "BR1" or nil
        let content: String        // descriptive text after ID or full title
    }

    // MARK: - Heading scan feedback (#43)

    /// Why an ATX heading was not treated as an eligible ID owner, or why assign skipped it.
    enum HeadingSkipReason: Equatable, Sendable {
        /// Heading level is outside 1…`ids.heading_max_level`.
        case deeperThanMaxLevel(level: Int, maxLevel: Int)
        case insideCodeFence
        case insideBlockquote
        case insideHTMLComment
        case insideTable
        /// Eligible level, no owning ID, and no BR/TS/… prefix could be inferred.
        case noPrefixInferred
        /// Title looks like an ID attempt but does not match owning-ID syntax (#31).
        case unrecognizedIDForm(detail: String)
        /// Section / vertical chrome (e.g. `# Business Requirements`) — not a requirement owner.
        case structuralSectionTitle

        var shortLabel: String {
            switch self {
            case .deeperThanMaxLevel(let level, let max):
                return "heading level H\(level) is deeper than ids.heading_max_level (\(max))"
            case .insideCodeFence:
                return "inside a fenced code block"
            case .insideBlockquote:
                return "inside a blockquote"
            case .insideHTMLComment:
                return "inside an HTML comment"
            case .insideTable:
                return "inside a table row"
            case .noPrefixInferred:
                return "no ID prefix could be inferred (title, filename, or sibling IDs)"
            case .unrecognizedIDForm(let detail):
                return detail
            case .structuralSectionTitle:
                return "structural section / vertical title (not an ID owner)"
            }
        }

        var syntaxTip: String {
            switch self {
            case .deeperThanMaxLevel(let level, let maxAllowed):
                let suggested = Swift.min(6, Swift.max(level, maxAllowed))
                return "Promote to H1–H\(maxAllowed) (e.g. `## BR1: Title`), or set ids.heading_max_level: \(suggested) in .specticus/config.yml."
            case .insideCodeFence:
                return "Move real requirements out of ``` / ~~~ fences into normal headings."
            case .insideBlockquote:
                return "Blockquoted headings are examples only (#30). Use a normal ATX heading for ownership."
            case .insideHTMLComment:
                return "Headings inside <!-- comments --> are ignored. Uncomment or copy into body content."
            case .insideTable:
                return "Table cells are not ID owners. Use a normal `## BR1: …` heading above/beside the table."
            case .noPrefixInferred:
                return "Write a manual ID (`## BR1: Title`), use a keyword (requirement, specification, use case, …), or put the heading in a section file (e.g. 007-business-requirements.md)."
            case .unrecognizedIDForm:
                return "Owning form is `## BR1: Title` — PREFIX + digits (no dash, no zero-padding), then `:` / `.` / space. Known prefixes: \(PrefixCatalog.prefixes.joined(separator: ", "))."
            case .structuralSectionTitle:
                return "Leave the section title without an ID. Put owning IDs on child requirement headings (e.g. `## BR1: User Login` under Business Requirements)."
            }
        }
    }

    /// One ATX heading observed while scanning sources (#43).
    struct HeadingObservation: Sendable {
        let file: URL
        let lineIndex: Int
        let level: Int
        let originalLine: String
        let title: String
        /// Non-nil when the heading is in an exclusion zone or wrong level for ownership.
        let exclusion: HeadingSkipReason?
        /// Eligible heading when exclusion is nil (same as collectHeadings results).
        let info: HeadingInfo?

        var isEligible: Bool { exclusion == nil && info != nil }

        var location: String {
            "\(file.lastPathComponent):\(lineIndex + 1)"
        }
    }

    /// Full scan used for assign feedback; eligible subset matches `collectHeadings` (#43).
    struct HeadingScan: Sendable {
        let maxLevel: Int
        let observations: [HeadingObservation]

        var eligible: [HeadingInfo] {
            observations.compactMap(\.info)
        }

        var excluded: [HeadingObservation] {
            observations.filter { $0.exclusion != nil }
        }
    }

    struct MarkdownHeadingFinding: Equatable, Sendable {
        let file: String
        let lineIndex: Int
        let title: String
    }

    /// Scans the project's content Markdown (top-level like assembleSources) and returns heading info.
    ///
    /// Content file discovery is shared via `MarkdownSources` (#35) with `DocumentGenerator.assembleSources`.
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
    ///
    /// For full skip/eligibility diagnostics (including excluded headings), use `scanHeadings` (#43).
    static func collectHeadings(project: SpecticusProject) throws -> [HeadingInfo] {
        try scanHeadings(project: project).eligible
    }

    /// Full ATX heading scan for assign feedback (#43).
    ///
    /// Records ATX headings in content files, including those in exclusion zones and
    /// deeper than `ids.heading_max_level`, with a reason when they cannot own an ID.
    /// Eligible observations (`.info != nil`) match historical `collectHeadings` behavior.
    /// Region flags and ATX recovery come from `MarkdownDocument` (#18).
    static func scanHeadings(project: SpecticusProject) throws -> HeadingScan {
        let maxLevel = SpecticusConfig.IdsSection.clampHeadingMaxLevel(
            project.config.ids.headingMaxLevel
        )
        let minLevel = SpecticusConfig.IdsSection.minHeadingLevel
        let mdFiles = try MarkdownSources.discoverContentFiles(
            in: project.root,
            layout: project.assemblyLayout
        )

        var observations: [HeadingObservation] = []

        for file in mdFiles {
            let raw = try String(contentsOf: file, encoding: .utf8)
            let document = MarkdownDocument.parse(raw)

            for (idx, line) in document.lines.enumerated() {
                // Fence delimiters and HTML-comment lines are not observed (#30).
                if line.isFenceDelimiter || line.inHTMLComment { continue }
                guard let atx = line.recoveredHeading else { continue }

                var exclusion: HeadingSkipReason? = nil
                if line.inFence {
                    exclusion = .insideCodeFence
                } else if line.inBlockquote {
                    exclusion = .insideBlockquote
                } else if line.inTable {
                    exclusion = .insideTable
                }

                let level = atx.level
                let title = atx.text

                if exclusion == nil, level < minLevel || level > maxLevel {
                    exclusion = .deeperThanMaxLevel(level: level, maxLevel: maxLevel)
                }

                let cleaned = HeadingNumberer.stripOutlinePrefix(from: title)
                let info: HeadingInfo?
                if exclusion == nil {
                    if let (id, content) = parseID(from: cleaned) {
                        info = HeadingInfo(
                            file: file,
                            lineIndex: idx,
                            originalLine: line.text,
                            level: level,
                            title: title,
                            id: id,
                            content: content
                        )
                    } else {
                        info = HeadingInfo(
                            file: file,
                            lineIndex: idx,
                            originalLine: line.text,
                            level: level,
                            title: title,
                            id: nil,
                            content: cleaned
                        )
                    }
                } else {
                    info = nil
                }

                observations.append(HeadingObservation(
                    file: file,
                    lineIndex: idx,
                    level: level,
                    originalLine: line.text,
                    title: title,
                    exclusion: exclusion,
                    info: info
                ))
            }
        }

        return HeadingScan(maxLevel: maxLevel, observations: observations)
    }

    /// Convenience: collect live IDs from headings (any claim counts, including duplicates).
    static func liveIDSet(from headings: [HeadingInfo]) -> Set<String> {
        Set(headings.compactMap(\.id))
    }

    /// Detect near-miss owning-ID forms after outline strip (#31 / #43).
    /// Returns a human-readable detail when the title looks like an attempted ID but is invalid.
    static func diagnoseUnrecognizedIDForm(in title: String) -> String? {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }

        // Already valid — not a near miss.
        if parseID(from: t) != nil { return nil }

        let knownPrefixes = PrefixCatalog.prefixes

        // Dashed / underscored legacy: BR-001, TS_42
        if let m = matchFirst(t, pattern: #"^([A-Za-z]{1,4})[-_]0*([0-9]+)\b(.*)$"#) {
            let prefix = m[1].uppercased()
            let num = m[2]
            let rest = m[3].trimmingCharacters(in: .whitespacesAndNewlines)
            if knownPrefixes.contains(prefix) {
                let suggestedNum = num.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
                let normalizedNum = suggestedNum.isEmpty ? "0" : suggestedNum
                let body = rest.isEmpty ? "Title" : rest.trimmingCharacters(in: CharacterSet(charactersIn: ":./ ").union(.whitespaces))
                return "legacy/dashed form '\(prefix)-\(num)' is not an owning ID; use \(prefix)\(normalizedNum == "0" ? num : normalizedNum) (no dash, no padding), e.g. `## \(prefix)\(normalizedNum == "0" ? "1" : normalizedNum): \(body.isEmpty ? "Title" : body)`"
            }
        }

        // Leading zero padding: BR01, TS007
        if let m = matchFirst(t, pattern: #"^([A-Z]{1,4})0+([0-9]+)\b(.*)$"#) {
            let prefix = m[1]
            let num = m[2]
            if knownPrefixes.contains(prefix) {
                return "zero-padded ID '\(prefix)0\(num)' is not valid; use \(prefix)\(num) with no leading zeros"
            }
        }

        // Lowercase prefix: br1, ts2
        if let m = matchFirst(t, pattern: #"^([a-z]{1,4})([1-9][0-9]*)\b(.*)$"#) {
            let prefix = m[1].uppercased()
            let num = m[2]
            if knownPrefixes.contains(prefix) {
                return "ID prefixes are case-sensitive; use \(prefix)\(num) not \(m[1])\(num)"
            }
        }

        // Bracketed: [BR1], (TS2)
        if let m = matchFirst(t, pattern: #"^[\[\(]([A-Z]{1,4})([1-9][0-9]*)[\]\)](.*)$"#) {
            let prefix = m[1]
            let num = m[2]
            if knownPrefixes.contains(prefix) {
                return "bracketed '\(prefix)\(num)' is not an owning ID; use leading \(prefix)\(num): without brackets"
            }
        }

        // Known prefix + digits but missing delimiter before rest, or unknown junk
        if let m = matchFirst(t, pattern: #"^([A-Z]{1,4})([1-9][0-9]*)([^:.\s].*)$"#) {
            let prefix = m[1]
            let num = m[2]
            if knownPrefixes.contains(prefix) {
                return "\(prefix)\(num) must be followed by ':' / '.' / whitespace before the title (got '\(m[3].prefix(12))…')"
            }
        }

        // Bare ID with no delimiter/title: `BR1`
        if let m = matchFirst(t, pattern: #"^([A-Z]{1,4})([1-9][0-9]*)$"#) {
            let prefix = m[1]
            let num = m[2]
            if knownPrefixes.contains(prefix) {
                return "\(prefix)\(num) must be followed by ':' / '.' / whitespace and a title, e.g. `## \(prefix)\(num): Title`"
            }
            return "prefix '\(prefix)' is not a known ID prefix (\(knownPrefixes.joined(separator: ", ")))"
        }

        // Unknown PREFIX + digits + delimiter (e.g. FOO1: Title)
        if let m = matchFirst(t, pattern: #"^([A-Z]{1,4})([1-9][0-9]*)([:.\s].*)$"#) {
            let prefix = m[1]
            if !knownPrefixes.contains(prefix) {
                return "prefix '\(prefix)' is not a known ID prefix (\(knownPrefixes.joined(separator: ", ")))"
            }
        }

        return nil
    }

    private static func matchFirst(_ text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(0..<ns.length)) else { return nil }
        var parts: [String] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            parts.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return parts
    }

    /// Parses an owning traceability ID from heading title text (#31 / #149).
    ///
    /// Outline numbering is stripped first (`1.2. BR1: Title` → same as `BR1: Title`).
    /// Returns `nil` when the title does not own an ID.
    /// When the heading is ID-only (`BR1:`), `content` is an empty string (unlike the
    /// internal assign parser, which falls back to the full title).
    static func parseOwningID(from title: String) -> (id: String, content: String)? {
        let stripped = HeadingNumberer.stripOutlinePrefix(from: title)
        guard let (id, _) = parseID(from: stripped) else { return nil }
        let pattern = #"^[A-Z]{1,4}[1-9]\d*[:.\s]+(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (id, "")
        }
        let ns = stripped as NSString
        guard let m = regex.firstMatch(in: stripped, range: NSRange(0..<ns.length)) else {
            return (id, "")
        }
        let body = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        return (id, body)
    }

    /// Parses a traceability ID from an outline-stripped heading title according to the
    /// exact syntax rules defined in issue #31.
    ///
    /// Rules (must match exactly after `HeadingNumberer.stripOutlinePrefix`):
    /// - ID must be the very first token: `ID ::= PREFIX DIGITS`
    /// - PREFIX ::= [A-Z]{1,4}   (e.g. BR, TS, ADR, UC, BC, TC, DIAG, REV, BDR)
    /// - DIGITS ::= [1-9][0-9]*  (no leading zero, no padding)
    /// - Must be immediately followed by a required delimiter: `:`, `.`, or whitespace
    /// - Only known prefixes are accepted
    /// - ID at any other position, with brackets, dashes, lowercase, or inside non-heading
    ///   content is rejected (see also #30 for content-type filtering).
    static func parseID(from title: String) -> (id: String, content: String)? {
        // title must already be outline-stripped; we require the ID at absolute start
        let pattern = #"^([A-Z]{1,4})([1-9]\d*)([:.\s]+)(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = title as NSString
        guard let m = regex.firstMatch(in: title, range: NSRange(0..<ns.length)) else { return nil }

        let prefix = ns.substring(with: m.range(at: 1))
        let numPart = ns.substring(with: m.range(at: 2))
        let rest = ns.substring(with: m.range(at: 4)).trimmingCharacters(in: .whitespaces)

        guard PrefixCatalog.prefixes.contains(prefix) else { return nil }
        let id = "\(prefix)\(numPart)"
        let content = rest.isEmpty ? title : rest
        return (id, content)
    }

    // MARK: - Structural section titles (skip auto-assign)

    /// Known Path A / skeleton vertical titles and common aliases (normalized).
    /// These are document chrome, not requirement owners.
    static let structuralSectionTitles: Set<String> = {
        var titles: Set<String> = [
            "document metadata",
            "document revisions",
            "system overview",
            "stakeholders and scope",
            "business need elicitation notes",
            "business notes",
            "technical notes",
            "assumptions and open questions",
            "business constraints",
            "technical constraints",
            "business requirements",
            "technical specifications",
            "quality attributes",
            "external interfaces",
            "data and privacy",
            "security and access",
            "use cases",
            "test plan",
            "test cases",
            "operational concerns",
            "risks and tradeoffs",
            "compliance and controls",
            "business glossary",
            "technical glossary",
            "glossary",
            "references",
            "diagrams",
            "overarching system diagrams",
            "overarching diagrams",
            "architecture decision records",
            "business decision records",
            "appendices",
            "technical specifications business requirements",
            "requirements",
            "specifications",
            "constraints",
            "overview",
        ]
        for folder in TemplateSections.defaultOrder {
            titles.insert(normalizeHeadingTitle(humanizePathComponent(folder)))
        }
        return titles
    }()

    /// Whether this heading is section/vertical chrome and must not receive an auto-assigned ID.
    ///
    /// Matches known skeleton titles and titles that merely restate the section folder / file stem
    /// (e.g. `# Business Requirements` in `business-requirements/001-….md`).
    static func isStructuralSectionTitle(_ title: String, file: URL) -> Bool {
        let normalized = normalizeHeadingTitle(HeadingNumberer.stripOutlinePrefix(from: title))
        guard !normalized.isEmpty else { return false }
        if structuralSectionTitles.contains(normalized) {
            return true
        }
        let parent = humanizePathComponent(file.deletingLastPathComponent().lastPathComponent)
        if !parent.isEmpty, normalized == normalizeHeadingTitle(parent) {
            return true
        }
        let stem = humanizePathComponent(file.deletingPathExtension().lastPathComponent)
        if !stem.isEmpty, normalized == normalizeHeadingTitle(stem) {
            return true
        }
        return false
    }

    /// `business-requirements` / `001-business-requirements` → `business requirements`.
    static func humanizePathComponent(_ name: String) -> String {
        var base = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let dot = base.lastIndex(of: "."), base[dot...] == ".md" || base.hasSuffix(".markdown") {
            base = String(base[..<dot])
        }
        // Strip leading outline-style file numbers: `001-`, `0001-`.
        if let range = base.range(of: #"^\d+-"#, options: .regularExpression) {
            base = String(base[range.upperBound...])
        }
        return base
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lowercase, strip light punctuation, collapse whitespace for title comparisons.
    static func normalizeHeadingTitle(_ text: String) -> String {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: "→", with: " ")
        s = s.replacingOccurrences(of: "—", with: " ")
        s = s.replacingOccurrences(of: "–", with: " ")
        var scaled = ""
        scaled.reserveCapacity(s.count)
        for ch in s {
            if ch.isLetter || ch.isNumber {
                scaled.append(ch)
            } else if ch.isWhitespace || ch == "-" || ch == "_" {
                scaled.append(" ")
            }
            // drop other punctuation
        }
        return scaled
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
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
}
