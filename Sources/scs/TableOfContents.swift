import Foundation

// MARK: - Hyperlinked table of contents (implements #12)

/// Builds a hyperlinked TOC and injects stable `id` anchors into generated heading HTML.
/// Works with hierarchical numbering from #4 (TOC shows the numbered title text).
/// Owning traceability IDs are stripped from TOC labels; anchors prefer the ID slug (#149 / #42).
enum TableOfContents {
    struct Heading: Equatable, Sendable {
        let level: Int
        let text: String
        /// Present when this heading is included in the TOC (`level <= maxLevel`).
        let id: String?
    }

    static let defaultMaxLevel = 3
    static let absoluteMaxLevel = 6

    static func clampMaxLevel(_ value: Int) -> Int {
        min(max(value, 0), absoluteMaxLevel)
    }

    // MARK: - Public pipeline

    /// Extract headings from Markdown, build TOC HTML, and inject anchors into body HTML.
    /// - Returns: `(bodyWithAnchors, tocHTML)` — `tocHTML` is empty when disabled or no entries.
    static func apply(
        markdown: String,
        bodyHTML: String,
        maxLevel: Int = defaultMaxLevel
    ) -> (bodyHTML: String, tocHTML: String) {
        let maxLevel = clampMaxLevel(maxLevel)
        guard maxLevel > 0 else {
            return (bodyHTML, "")
        }

        let headings = extractHeadings(from: markdown, maxLevel: maxLevel)
        let withAnchors = injectAnchors(into: bodyHTML, headings: headings)
        let tocEntries = headings.filter { $0.id != nil }
        let toc = tocEntries.isEmpty ? "" : renderNav(entries: tocEntries)
        return (withAnchors, toc)
    }

    // MARK: - Extraction

    /// Parse ATX headings from markdown (skips fenced code). Assigns unique ids for levels ≤ maxLevel.
    static func extractHeadings(from markdown: String, maxLevel: Int) -> [Heading] {
        let maxLevel = clampMaxLevel(maxLevel)
        var results: [Heading] = []
        var usedIDs = Set<String>()
        var inFence = false

        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        for raw in lines {
            var line = String(raw)
            if line.hasSuffix("\r") { line = String(line.dropLast()) }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence { continue }

            guard let (level, text) = parseATXHeading(line) else { continue }
            let parts = TraceabilityChips.parts(from: text)
            let display = parts.visibleHeadingText
            let id: String? = (maxLevel > 0 && level <= maxLevel)
                ? uniqueSlug(base: TraceabilityChips.preferredAnchorBase(from: text), used: &usedIDs)
                : nil
            results.append(Heading(level: level, text: display, id: id))
        }
        return results
    }

    // MARK: - Anchor injection

    /// Walk HTML headings in document order and attach `id` when the matching extracted heading has one.
    static func injectAnchors(into html: String, headings: [Heading]) -> String {
        guard !headings.isEmpty else { return html }
        guard let regex = try? NSRegularExpression(
            pattern: #"<h([1-6])(\s[^>]*)?>([\s\S]*?)</h\1>"#,
            options: [.caseInsensitive]
        ) else {
            return html
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        guard !matches.isEmpty else { return html }

        var output = ""
        var lastNSEnd = 0
        var hi = 0

        for match in matches {
            let matchRange = match.range
            if matchRange.location > lastNSEnd {
                output += nsHTML.substring(
                    with: NSRange(location: lastNSEnd, length: matchRange.location - lastNSEnd)
                )
            }

            let level = Int(nsHTML.substring(with: match.range(at: 1))) ?? 1
            let attrs: String = match.range(at: 2).location != NSNotFound
                ? nsHTML.substring(with: match.range(at: 2))
                : ""
            let inner = nsHTML.substring(with: match.range(at: 3))
            let cleanedAttrs = stripExistingID(from: attrs)

            var idAttr = ""
            if hi < headings.count {
                if let id = headings[hi].id {
                    idAttr = #" id="\#(escapeHTMLAttribute(id))""#
                }
                hi += 1
            }
            _ = level // level used for tag name only

            output += "<h\(level)\(idAttr)\(cleanedAttrs)>\(inner)</h\(level)>"
            lastNSEnd = matchRange.location + matchRange.length
        }

        if lastNSEnd < nsHTML.length {
            output += nsHTML.substring(from: lastNSEnd)
        }
        return output
    }

    // MARK: - TOC HTML

    static func renderNav(entries: [Heading], title: String = "Contents") -> String {
        var items = ""
        for entry in entries {
            guard let id = entry.id else { continue }
            let label = escapeHTML(entry.text)
            let href = escapeHTMLAttribute(id)
            items += """
            <li class="toc-level-\(entry.level)"><a href="#\(href)">\(label)</a></li>

            """
        }
        guard !items.isEmpty else { return "" }

        return """
        <nav class="toc" id="toc" aria-label="Table of contents">
          <h2 class="toc-title">\(escapeHTML(title))</h2>
          <ol class="toc-list">
        \(items)  </ol>
        </nav>
        """
    }

    // MARK: - Helpers

    private static func parseATXHeading(_ line: String) -> (level: Int, text: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(#{1,6})\s+(.*)$"#) else {
            return nil
        }
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let hashes = ns.substring(with: m.range(at: 1))
        var text = ns.substring(with: m.range(at: 2))
        if let trail = text.range(of: #"\s+#+\s*$"#, options: .regularExpression) {
            text = String(text[..<trail.lowerBound])
        }
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (hashes.count, text)
    }

    static func slugify(_ text: String) -> String {
        let lowered = text.lowercased()
        var slug = ""
        var lastWasHyphen = false
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                slug.append(ch)
                lastWasHyphen = false
            } else if ch == "-" || ch == "_" || ch.isWhitespace {
                if !lastWasHyphen && !slug.isEmpty {
                    slug.append("-")
                    lastWasHyphen = true
                }
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        while slug.hasPrefix("-") { slug.removeFirst() }
        if slug.isEmpty { slug = "section" }
        return slug
    }

    private static func uniqueSlug(from text: String, used: inout Set<String>) -> String {
        uniqueSlug(base: slugify(text), used: &used)
    }

    private static func uniqueSlug(base: String, used: inout Set<String>) -> String {
        let normalized = base.isEmpty ? "section" : base
        var candidate = normalized
        var n = 2
        while used.contains(candidate) {
            candidate = "\(normalized)-\(n)"
            n += 1
        }
        used.insert(candidate)
        return candidate
    }

    private static func stripExistingID(from attrs: String) -> String {
        guard !attrs.isEmpty else { return attrs }
        guard let regex = try? NSRegularExpression(
            pattern: #"\s*id\s*=\s*("[^"]*"|'[^']*')"#,
            options: .caseInsensitive
        ) else {
            return attrs
        }
        let range = NSRange(attrs.startIndex..., in: attrs)
        return regex.stringByReplacingMatches(in: attrs, range: range, withTemplate: "")
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func escapeHTMLAttribute(_ string: String) -> String {
        escapeHTML(string)
    }
}
