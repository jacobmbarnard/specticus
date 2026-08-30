import Foundation

// MARK: - HTML demotion of owning traceability IDs to chips (#149 / #42)

/// Render presentation only: source Markdown keeps `## BR1: Title` (#31).
/// Built HTML shows the human title (plus outline numbers) with a subtle chip for the owning ID.
enum TraceabilityChips {
    struct HeadingParts: Equatable, Sendable {
        /// Leading outline prefix including trailing space, e.g. `"1.1. "`, or empty.
        var outlinePrefix: String
        /// Owning ID when present (`BR1`), else `nil`.
        var owningID: String?
        /// Human title without outline or owning ID.
        var titleText: String

        /// Visible heading text for HTML / TOC (outline + human title).
        var visibleHeadingText: String {
            outlinePrefix + titleText
        }
    }

    /// Split heading title text into outline, optional owning ID, and human title.
    static func parts(from headingText: String) -> HeadingParts {
        let text = headingText.trimmingCharacters(in: .whitespacesAndNewlines)
        var outlinePrefix = ""
        var rest = text
        if let range = text.range(of: #"^\d+(?:\.\d+)*\.\s+"#, options: .regularExpression) {
            outlinePrefix = String(text[range])
            rest = String(text[range.upperBound...])
        }

        if let (id, content) = IdsManager.parseOwningID(from: rest) {
            return HeadingParts(
                outlinePrefix: outlinePrefix,
                owningID: id,
                titleText: content
            )
        }

        return HeadingParts(outlinePrefix: outlinePrefix, owningID: nil, titleText: rest)
    }

    /// Preferred HTML anchor for a heading: lowercase owning ID when present.
    static func preferredAnchorBase(from headingText: String) -> String {
        let p = parts(from: headingText)
        if let id = p.owningID {
            return id.lowercased()
        }
        return TableOfContents.slugify(p.visibleHeadingText)
    }

    /// Rewrite heading HTML: strip owning IDs from visible titles; emit chips below.
    static func demoteOwningIDs(in html: String) -> String {
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

        for match in matches {
            let matchRange = match.range
            if matchRange.location > lastNSEnd {
                output += nsHTML.substring(
                    with: NSRange(location: lastNSEnd, length: matchRange.location - lastNSEnd)
                )
            }

            let level = nsHTML.substring(with: match.range(at: 1))
            let attrs: String = match.range(at: 2).location != NSNotFound
                ? nsHTML.substring(with: match.range(at: 2))
                : ""
            let inner = nsHTML.substring(with: match.range(at: 3))
            let plain = plainText(fromHTMLFragment: inner)
            let p = parts(from: plain)

            if let id = p.owningID {
                let visible = escapeHTML(p.visibleHeadingText)
                output += "<h\(level)\(attrs)>\(visible)</h\(level)>"
                output += renderChip(id: id)
            } else {
                output += nsHTML.substring(with: matchRange)
            }

            lastNSEnd = matchRange.location + matchRange.length
        }

        if lastNSEnd < nsHTML.length {
            output += nsHTML.substring(from: lastNSEnd)
        }
        return output
    }

    /// Chip markup placed immediately after the heading (#42: below / subtitle-adjacent).
    static func renderChip(id: String) -> String {
        let escaped = escapeHTML(id)
        let attr = escapeHTMLAttribute(id)
        return """

        <p class="scs-id-chip" data-scs-id="\(attr)"><span class="scs-id">\(escaped)</span></p>
        """
    }

    // MARK: - Helpers

    private static func plainText(fromHTMLFragment html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<[^>]+>"#) else {
            return decodeBasicEntities(html)
        }
        let range = NSRange(html.startIndex..., in: html)
        let stripped = regex.stringByReplacingMatches(in: html, range: range, withTemplate: "")
        return decodeBasicEntities(stripped)
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeBasicEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
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
