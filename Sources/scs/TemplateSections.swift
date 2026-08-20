import Foundation

// MARK: - Default Path A section verticals (#139)

/// Stable top-level section folder ids for the default template pack.
/// Assembly order until #140 lands: this array order, then lex paths within each section.
enum TemplateSections {
    /// Default verticals in Path A narrative order (folder names under project root).
    static let defaultOrder: [String] = [
        "document-metadata",
        "system-overview",
        "stakeholders-and-scope",
        "business-notes",
        "technical-notes",
        "assumptions-and-open-questions",
        "business-constraints",
        "technical-constraints",
        "business-requirements",
        "technical-specifications",
        "quality-attributes",
        "external-interfaces",
        "data-and-privacy",
        "security-and-access",
        "use-cases",
        "test-plan",
        "operational-concerns",
        "risks-and-tradeoffs",
        "compliance-and-controls",
        "business-glossary",
        "technical-glossary",
        "references",
        "diagrams",
        "ADRs",
        "BDRs",
        "appendices",
    ]

    static let defaultOrderSet: Set<String> = Set(defaultOrder)

    /// ADR/BDR lifecycle status folders (includes `rejected` per #139).
    static let decisionStatusFolders: [String] = [
        "proposed",
        "accepted",
        "deprecated",
        "superseded",
        "rejected",
    ]

    /// True when `directory` looks like a vertically sliced project (any known section folder present).
    static func usesVerticalLayout(at directory: URL, fm: FileManager = .default) -> Bool {
        for id in defaultOrder {
            var isDir: ObjCBool = false
            let path = directory.appendingPathComponent(id, isDirectory: true).path
            if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return true
            }
        }
        return false
    }
}
