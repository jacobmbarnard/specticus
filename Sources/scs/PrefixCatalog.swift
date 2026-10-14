import Foundation

// MARK: - ID prefix rules as data (internals #19)

/// Known ID prefixes and the title / filename tokens that map unbound headings to them.
///
/// Inference picks the **highest-specificity** matching rule. On a specificity
/// tie, the earlier entry in `prefixes` wins (historical ladder order). `TC`
/// covers both "test case" and "technical constraint" via separate rules.
///
/// Structural section titles (`# Business Requirements`) are skipped by
/// `IdsManager` before it calls into this catalog — not here.
enum PrefixCatalog {
    /// Canonical prefix codes in historical order (listing + tie-break).
    static let prefixes: [String] = [
        "BR", "TS", "UC", "ADR", "BDR", "TC", "BC", "REF", "DIAG", "REV"
    ]

    /// How a rule matches a lowercased haystack.
    enum Match: Equatable, Sendable {
        case contains(String)
        case hasPrefix(String)
        case hasSuffix(String)
        case equals(String)

        func matches(_ haystack: String) -> Bool {
            switch self {
            case .contains(let needle):
                return haystack.contains(needle)
            case .hasPrefix(let needle):
                return haystack.hasPrefix(needle)
            case .hasSuffix(let needle):
                return haystack.hasSuffix(needle)
            case .equals(let needle):
                return haystack == needle
            }
        }
    }

    /// One inference rule: prefix + specificity + one or more match needles.
    struct Rule: Equatable, Sendable {
        let prefix: String
        let specificity: Int
        let matches: [Match]

        init(prefix: String, specificity: Int, matches: [Match]) {
            self.prefix = prefix
            self.specificity = specificity
            self.matches = matches
        }

        init(prefix: String, specificity: Int, contains needles: String...) {
            self.prefix = prefix
            self.specificity = specificity
            self.matches = needles.map { .contains($0) }
        }
    }

    // MARK: - Title (heading text) rules

    /// Title / content keywords. Higher specificity wins over weaker fallbacks
    /// (e.g. "technical constraint" → `TC` beats bare "constraint" → `BC`).
    static let titleRules: [Rule] = [
        Rule(prefix: "BR", specificity: 100, contains: "business requirement"),
        Rule(prefix: "TS", specificity: 100, contains: "technical specification"),
        Rule(prefix: "UC", specificity: 100, contains: "use case"),
        Rule(prefix: "TC", specificity: 100, contains: "test case", "test plan"),
        Rule(prefix: "TC", specificity: 100, contains: "technical constraint"),
        Rule(prefix: "BC", specificity: 100, contains: "business constraint"),
        Rule(prefix: "BDR", specificity: 100, contains: "business decision", "bdr"),
        Rule(prefix: "ADR", specificity: 100, contains: "architecture decision"),
        Rule(prefix: "DIAG", specificity: 100, contains: "diagram"),
        Rule(prefix: "REV", specificity: 100, contains: "revision"),
        Rule(prefix: "ADR", specificity: 80, contains: "adr"),
        Rule(prefix: "BR", specificity: 50, contains: "requirement", "shall "),
        Rule(prefix: "TS", specificity: 50, contains: "specification"),
        Rule(prefix: "ADR", specificity: 40, contains: "decision"),
        Rule(prefix: "BC", specificity: 40, contains: "constraint")
        // REF has no title inference today — parse/assign only when already present.
    ]

    // MARK: - Filename rules

    /// Filename tokens (extension stripped; `_` normalized to `-`).
    static let filenameRules: [Rule] = [
        Rule(prefix: "BR", specificity: 100, contains: "business-requirement", "business-requirements"),
        Rule(
            prefix: "TS",
            specificity: 100,
            contains: "technical-specification", "technical-specifications", "technical-spec", "tech-spec"
        ),
        Rule(prefix: "BC", specificity: 100, contains: "business-constraint", "business-constraints"),
        Rule(prefix: "TC", specificity: 100, contains: "technical-constraint", "technical-constraints"),
        Rule(prefix: "UC", specificity: 100, contains: "use-case", "use-cases"),
        Rule(prefix: "TC", specificity: 100, contains: "test-plan", "test-case", "test-cases"),
        Rule(prefix: "BDR", specificity: 100, contains: "business-decision", "bdr"),
        Rule(
            prefix: "ADR",
            specificity: 90,
            matches: [.contains("architecture"), .contains("-adr"), .hasPrefix("adr")]
        ),
        Rule(prefix: "DIAG", specificity: 100, contains: "diagram"),
        Rule(prefix: "REV", specificity: 100, contains: "revision"),
        Rule(prefix: "BR", specificity: 40, contains: "requirement"),
        Rule(
            prefix: "TS",
            specificity: 40,
            matches: [
                .contains("specification"),
                .hasSuffix("-specs"),
                .hasSuffix("-spec"),
                .equals("specs"),
                .equals("spec")
            ]
        ),
        Rule(prefix: "BC", specificity: 30, contains: "constraint")
    ]

    // MARK: - Inference

    /// Infer a prefix from heading descriptive text (not filenames).
    static func inferFromTitle(_ text: String) -> String? {
        bestMatch(rules: titleRules, haystack: text.lowercased())
    }

    /// Infer a prefix from a Markdown filename (skeleton section names and aliases).
    static func inferFromFilename(_ filename: String) -> String? {
        var base = filename.lowercased()
        if let dot = base.lastIndex(of: ".") {
            base = String(base[..<dot])
        }
        let normalized = base.replacingOccurrences(of: "_", with: "-")
        return bestMatch(rules: filenameRules, haystack: normalized)
    }

    /// Free-form helper: title rules first; filename rules when the string looks path-like.
    static func infer(from text: String) -> String? {
        if let fromTitle = inferFromTitle(text) {
            return fromTitle
        }
        if text.contains(".") || text.contains("-") || text.contains("_") || text.contains("/") {
            return inferFromFilename(text)
        }
        return nil
    }

    static func isKnown(_ prefix: String) -> Bool {
        prefixes.contains(prefix)
    }

    /// Index in `prefixes` for stable sorts; `nil` if unknown.
    static func index(of prefix: String) -> Int? {
        prefixes.firstIndex(of: prefix)
    }

    // MARK: - Internals

    private static func bestMatch(rules: [Rule], haystack: String) -> String? {
        var bestPrefix: String?
        var bestSpecificity = Int.min
        var bestOrder = Int.max

        for rule in rules {
            guard rule.matches.contains(where: { $0.matches(haystack) }) else { continue }
            let order = index(of: rule.prefix) ?? Int.max
            if rule.specificity > bestSpecificity
                || (rule.specificity == bestSpecificity && order < bestOrder)
            {
                bestSpecificity = rule.specificity
                bestOrder = order
                bestPrefix = rule.prefix
            }
        }
        return bestPrefix
    }
}
