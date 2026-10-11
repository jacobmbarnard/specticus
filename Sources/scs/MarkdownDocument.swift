import Foundation

// MARK: - One Markdown document pass (internals #18)
//
// Single line walk produces region flags and ATX headings. HeadingNumberer,
// TableOfContents, and IdsManager consume this model instead of each keeping
// a private fence/heading walker. Parse with Swift Regex (no NSRegularExpression
// in this pass). Later internals steps throw SpecticusError from new failures;
// this type only models text.

/// Assembled Markdown broken into annotated lines.
struct MarkdownDocument: Equatable, Sendable {
    /// One ATX heading (`#`…`######`) recovered from a line.
    struct ATXHeading: Equatable, Sendable {
        let level: Int
        let text: String
        let indent: String
        let hashes: String
        let spacing: String
    }

    /// One physical line after CRLF normalization (`\r` stripped).
    struct Line: Equatable, Sendable {
        let text: String
        /// True for ``` / ~~~ delimiter lines (content between them has `inFence`).
        let isFenceDelimiter: Bool
        /// Inside a fenced code block (delimiter lines themselves are false).
        let inFence: Bool
        /// Line begins with `>` (blockquote marker).
        let inBlockquote: Bool
        /// Inside `<!-- … -->` (including the opener/closer lines).
        let inHTMLComment: Bool
        /// Line begins with `|` (GFM table row).
        let inTable: Bool
        /// Standard ATX heading at the start of the line (after indent), if any.
        let heading: ATXHeading?
        /// Heading recovered for ID-scan observation (strips `>` / table pipes).
        /// Nil on fence delimiters and HTML-comment lines (IdsManager does not observe those).
        let recoveredHeading: ATXHeading?
    }

    let lines: [Line]
    let endsWithNewline: Bool

    // MARK: - Parse

    /// Walk `markdown` once: fences, blockquotes, HTML comments, tables, ATX headings.
    static func parse(_ markdown: String) -> MarkdownDocument {
        let endsWithNewline = markdown.hasSuffix("\n")
        let rawLines = markdown.split(separator: "\n", omittingEmptySubsequences: false)

        var lines: [Line] = []
        lines.reserveCapacity(rawLines.count)

        var inFence = false
        var inComment = false

        for raw in rawLines {
            var text = String(raw)
            if text.hasSuffix("\r") {
                text = String(text.dropLast())
            }
            let trimmed = text.trimmingCharacters(in: .whitespaces)

            if isFenceDelimiter(trimmed) {
                lines.append(
                    Line(
                        text: text,
                        isFenceDelimiter: true,
                        inFence: false,
                        inBlockquote: false,
                        inHTMLComment: false,
                        inTable: false,
                        heading: nil,
                        recoveredHeading: nil
                    )
                )
                inFence.toggle()
                continue
            }

            var lineInComment = inComment
            if trimmed.hasPrefix("<!--") {
                lineInComment = true
                if trimmed.contains("-->") {
                    inComment = false
                } else {
                    inComment = true
                }
            } else if inComment {
                lineInComment = true
                if trimmed.contains("-->") {
                    inComment = false
                }
            }

            let inBlockquote = trimmed.hasPrefix(">")
            let inTable = trimmed.hasPrefix("|")
            let heading = parseATXHeading(text)
            let recovered = recoveredHeading(
                text: text,
                trimmed: trimmed,
                inFence: inFence,
                inBlockquote: inBlockquote,
                inHTMLComment: lineInComment,
                inTable: inTable,
                standard: heading
            )

            lines.append(
                Line(
                    text: text,
                    isFenceDelimiter: false,
                    inFence: inFence,
                    inBlockquote: inBlockquote,
                    inHTMLComment: lineInComment,
                    inTable: inTable,
                    heading: heading,
                    recoveredHeading: recovered
                )
            )
        }

        return MarkdownDocument(lines: lines, endsWithNewline: endsWithNewline)
    }

    /// Reassemble lines with `\n`, preserving a trailing newline when the source had one.
    func rendered() -> String {
        var result = lines.map(\.text).joined(separator: "\n")
        if endsWithNewline && !result.hasSuffix("\n") {
            result.append("\n")
        }
        return result
    }

    // MARK: - Shared primitives (also used via MarkdownSources)

    /// True when a trimmed line opens or closes a fenced code block (``` or ~~~).
    static func isFenceDelimiter(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~")
    }

    /// Parse an ATX heading (`#`…`######` + title). Trailing `#` decorations are stripped.
    /// Uses Swift `Regex` literals (not `NSRegularExpression`).
    static func parseATXHeading(_ line: String) -> ATXHeading? {
        guard let match = line.wholeMatch(of: #/^(\s*)(#{1,6})(\s+)(.*)$/#) else { return nil }
        let indent = String(match.1)
        let hashes = String(match.2)
        let spacing = String(match.3)
        var text = String(match.4)
        if let trail = text.firstMatch(of: #/\s+#+\s*$/#) {
            text = String(text[..<trail.range.lowerBound])
        }
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return ATXHeading(
            level: hashes.count,
            text: text,
            indent: indent,
            hashes: hashes,
            spacing: spacing
        )
    }

    // MARK: - Internals

    private static func recoveredHeading(
        text: String,
        trimmed: String,
        inFence: Bool,
        inBlockquote: Bool,
        inHTMLComment: Bool,
        inTable: Bool,
        standard: ATXHeading?
    ) -> ATXHeading? {
        if inHTMLComment { return nil }
        if inFence { return parseATXHeading(text) }
        if inBlockquote {
            let stripped = String(trimmed.drop(while: { $0 == ">" || $0 == " " || $0 == "\t" }))
            return parseATXHeading(stripped)
        }
        if inTable {
            let unpiped = trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .trimmingCharacters(in: .whitespaces)
            guard unpiped.hasPrefix("#") else { return nil }
            return parseATXHeading(unpiped)
        }
        return standard
    }
}
