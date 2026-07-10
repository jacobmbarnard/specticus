import Foundation

// MARK: - Hierarchical heading auto-numbering (implements #4)

/// Prepends hierarchical outline numbers to Markdown ATX headings.
///
/// - Default `maxLevel` is **3** (number `#` … `###` only).
/// - Configurable **1…6**; `0` disables numbering.
/// - **Disjoint from traceability IDs (#6):** does not parse, rewrite, or remove
///   tokens like `BR-001`, `TS-002`, `ADR-0001` in heading text — only prefixes
///   an outline number (`1.2.3. `) before the existing title.
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

        // counters[1]…counters[6]
        var counters = [Int](repeating: 0, count: absoluteMaxLevel + 1)
        var inFence = false

        // Preserve whether the source used \n or \r\n by splitting on \n and keeping content.
        let endsWithNewline = markdown.hasSuffix("\n")
        let rawLines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var output: [String] = []
        output.reserveCapacity(rawLines.count)

        for raw in rawLines {
            // Drop a single trailing \r for CRLF files
            var line = String(raw)
            if line.hasSuffix("\r") {
                line = String(line.dropLast())
            }

            if isFenceDelimiter(line) {
                inFence.toggle()
                output.append(line)
                continue
            }

            if inFence {
                output.append(line)
                continue
            }

            if let numbered = numberHeadingLine(line, maxLevel: maxLevel, counters: &counters) {
                output.append(numbered)
            } else {
                output.append(line)
            }
        }

        var result = output.joined(separator: "\n")
        if endsWithNewline && !result.hasSuffix("\n") {
            result.append("\n")
        }
        return result
    }

    // MARK: - Internals

    private static func isFenceDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    /// Returns a numbered heading line, or nil if `line` is not an ATX heading at a numbered level.
    private static func numberHeadingLine(
        _ line: String,
        maxLevel: Int,
        counters: inout [Int]
    ) -> String? {
        // Optional leading whitespace, 1–6 hashes, required space, rest of title.
        // Do not treat "#######" (7+) as a heading.
        guard let match = line.range(
            of: #"^(\s*)(#{1,6})(\s+)(.*)$"#,
            options: .regularExpression
        ) else {
            return nil
        }

        let full = String(line[match])
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*)(#{1,6})(\s+)(.*)$"#) else {
            return nil
        }
        let ns = full as NSString
        guard let m = regex.firstMatch(in: full, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }

        let indent = ns.substring(with: m.range(at: 1))
        let hashes = ns.substring(with: m.range(at: 2))
        let space = ns.substring(with: m.range(at: 3))
        var title = ns.substring(with: m.range(at: 4))

        let level = hashes.count
        guard level >= 1, level <= absoluteMaxLevel else { return nil }

        // Deeper than max: leave unnumbered (still a valid heading for TOC later).
        guard level <= maxLevel else { return nil }

        // Strip a previous outline prefix we may have added (idempotent re-runs on already-numbered source).
        // Only strip pure hierarchical prefixes like "1. ", "1.2.3. " — never touch BR-001 style IDs.
        title = stripOutlinePrefix(from: title)

        counters[level] += 1
        if level < absoluteMaxLevel {
            for deeper in (level + 1)...absoluteMaxLevel {
                counters[deeper] = 0
            }
        }

        let outline = (1...level).map { String(counters[$0]) }.joined(separator: ".")
        // "1.2.3. Title" — trailing dot after last component for readability
        let prefix = "\(outline). "
        return "\(indent)\(hashes)\(space)\(prefix)\(title)"
    }

    /// Removes a leading hierarchical outline number if present (`1. ` / `1.2.3. `).
    /// Leaves traceability IDs (`BR-001: …`) and normal titles untouched.
    static func stripOutlinePrefix(from title: String) -> String {
        // One or more digit groups separated by dots, each group followed by a dot and space
        // e.g. "1. ", "1.2. ", "12.3.4. "
        guard let range = title.range(of: #"^\d+(?:\.\d+)*\.\s+"#, options: .regularExpression) else {
            return title
        }
        return String(title[range.upperBound...])
    }
}
