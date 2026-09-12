import Foundation
import ArgumentParser

// MARK: - Style packs / multi-template registry (#141)

/// A built-in (or later external) documentation style pack.
///
/// On disk under `Resources/`:
/// - `default` stays at `Resources/Skeleton/` (Path A; not moved to `Styles/default`)
/// - additional packs live at `Resources/Styles/<id>/`
struct StylePack: Equatable, Sendable {
    /// Stable id used by `scs init --style` and `doc.style` in config.
    var id: String
    /// Short help text for `scs init --help`.
    var summary: String
    /// Folder name of the skeleton tree inside `resourceParent`.
    var resourceDirectory: String
    /// Bundle subdirectory that contains `resourceDirectory` (SPM `Resources/…`).
    var resourceParent: String

    init(
        id: String,
        summary: String,
        resourceDirectory: String,
        resourceParent: String = "Resources"
    ) {
        self.id = id
        self.summary = summary
        self.resourceDirectory = resourceDirectory
        self.resourceParent = resourceParent
    }
}

enum StylePackRegistry {
    /// Path A / SRS-ish vertical template (current init skeleton).
    static let defaultPackID = "default"

    /// Sparse stub pack — proves a second built-in style without shipping a full paradigm.
    static let minimalPackID = "minimal"

    /// Built-in packs. Adding a style later ≈ new directory + entry here (#141).
    static let builtIn: [StylePack] = [
        StylePack(
            id: defaultPackID,
            summary: "Path A vertical specs (business/tech requirements, glossaries, ADRs/BDRs, …)",
            resourceDirectory: "Skeleton"
        ),
        StylePack(
            id: minimalPackID,
            summary: "Sparse vertical stub (metadata, overview, requirements, diagrams, ADRs)",
            resourceDirectory: "minimal",
            resourceParent: "Resources/Styles"
        ),
    ]

    static var builtInIDs: [String] { builtIn.map(\.id) }

    static func normalizeID(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func pack(id: String) -> StylePack? {
        let key = normalizeID(id)
        return builtIn.first { $0.id == key }
    }

    /// Non-nil when `id` is not a built-in pack (empty/missing already defaulted in config).
    static func unknownStyleDiagnostic(_ id: String) -> String? {
        let key = normalizeID(id)
        guard !key.isEmpty, pack(id: key) == nil else { return nil }
        let known = builtInIDs.joined(separator: ", ")
        return "Unknown documentation style '\(id)'. Built-in styles: \(known). Missing `doc.style` still means `default`."
    }

    /// Resolve embedded skeleton URL for a pack id.
    static func skeletonURL(forPackID id: String = defaultPackID) throws -> URL {
        guard let pack = pack(id: id) else {
            let known = builtInIDs.joined(separator: ", ")
            throw ValidationError(
                "Unknown documentation style '\(id)'. Built-in styles: \(known)."
            )
        }
        guard let url = Bundle.module.url(
            forResource: pack.resourceDirectory,
            withExtension: nil,
            subdirectory: pack.resourceParent
        ) else {
            throw ValidationError(
                "Internal error: style pack '\(pack.id)' resources not found (\(pack.resourceParent)/\(pack.resourceDirectory))."
            )
        }
        return url
    }

    static var helpListing: String {
        builtIn.map { "  \($0.id) — \($0.summary)" }.joined(separator: "\n")
    }
}
