import Foundation

// MARK: - Hierarchical heading auto-numbering (implements #4)

/// Prepends hierarchical outline numbers to Markdown ATX headings.
///
/// - Default `maxLevel` is **3** (number `#` … `###` only).
/// - Configurable **1…6**; `0` disables numbering.
/// - **Disjoint from traceability IDs (#6):** does not parse, rewrite, or remove
///   tokens like `BR1`, `TS2`, `ADR3` in heading text — only prefixes
///   an outline number (`1.2.3. `) before the existing title.
/// - Fence skipping and ATX parse come from `MarkdownDocument` (#18).
enum HeadingNumberer {
    /// Minimum allowed max level (0 = off).
    static let minMaxLevel = 0
    /// Maximum ATX heading depth.
    static let absoluteMaxLevel = 6
    /// Product default: number through H3.
    static let defaultMaxLevel = 3

    /// Clamp a configured max level into the valid range.
    static func clampMaxLevel(_ value: Int) -> Int {
        min(max(value, minMaxLevel), absoluteMaxLevel)
    }

    /// Number ATX headings in `markdown` up through `maxLevel`.
    ///
    /// Skips fenced code blocks (``` / ~~~) so comments and examples are untouched.
    /// Does not modify setext-style headings.
    static func numberHeadings(in markdown: String, maxLevel: Int = defaultMaxLevel) -> String {
        let maxLevel = clampMaxLevel(maxLevel)
        guard maxLevel > 0 else { return markdown }

        let document = MarkdownDocument.parse(markdown)
        var counters = [Int](repeating: 0, count: absoluteMaxLevel + 1)
        var output: [String] = []
        output.reserveCapacity(document.lines.count)

        for line in document.lines {
            if line.isFenceDelimiter || line.inFence {
                output.append(line.text)
                continue
            }

            if let numbered = numberHeading(line.heading, maxLevel: maxLevel, counters: &counters) {
                output.append(numbered)
            } else {
                output.append(line.text)
            }
        }

        var result = output.joined(separator: "\n")
        if document.endsWithNewline && !result.hasSuffix("\n") {
            result.append("\n")
        }
        return result
    }

    // MARK: - Internals

    /// Returns a numbered heading line, or nil if there is no ATX heading at a numbered level.
    private static func numberHeading(
        _ heading: MarkdownDocument.ATXHeading?,
        maxLevel: Int,
        counters: inout [Int]
    ) -> String? {
        guard let heading else { return nil }
        let level = heading.level
        guard level >= 1, level <= absoluteMaxLevel else { return nil }
        // Deeper than max: leave unnumbered (still a valid heading for TOC later).
        guard level <= maxLevel else { return nil }

        // Strip a previous outline prefix we may have added (idempotent re-runs).
        // Only strip pure hierarchical prefixes like "1. ", "1.2.3. " — never touch BR1 style IDs.
        let title = stripOutlinePrefix(from: heading.text)

        counters[level] += 1
        if level < absoluteMaxLevel {
            for deeper in (level + 1)...absoluteMaxLevel {
                counters[deeper] = 0
            }
        }

        let outline = (1...level).map { String(counters[$0]) }.joined(separator: ".")
        let prefix = "\(outline). "
        return "\(heading.indent)\(heading.hashes)\(heading.spacing)\(prefix)\(title)"
    }

    /// Removes a leading hierarchical outline number if present (`1. ` / `1.2.3. `).
    /// Leaves traceability IDs (`BR1: …`) and normal titles untouched.
    static func stripOutlinePrefix(from title: String) -> String {
        // One or more digit groups separated by dots, each group followed by a dot and space
        // e.g. "1. ", "1.2. ", "12.3.4. "
        guard let range = title.range(of: #"^\d+(?:\.\d+)*\.\s+"#, options: .regularExpression) else {
            return title
        }
        return String(title[range.upperBound...])
    }
}
