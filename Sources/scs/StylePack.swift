import Foundation
import ArgumentParser

// MARK: - Style packs / multi-template registry (#141) — step 1 scaffolding

/// A built-in (or later external) documentation style pack.
///
/// Pack on disk under `Resources/`: today the Path A pack lives at `Skeleton/`
/// and is registered as id `default`. Later packs can use `Styles/<id>/`.
struct StylePack: Equatable, Sendable {
    /// Stable id used by `scs init --style` and `doc.style` in config.
    var id: String
    /// Short help text for `scs init --help`.
    var summary: String
    /// Bundle subdirectory under `Resources/` that contains the skeleton tree.
    var resourceDirectory: String
}

enum StylePackRegistry {
    /// Path A / SRS-ish vertical template (current init skeleton).
    static let defaultPackID = "default"

    /// Built-in packs. Adding a style later ≈ new directory + entry here (#141).
    static let builtIn: [StylePack] = [
        StylePack(
            id: defaultPackID,
            summary: "Path A vertical specs (business/tech requirements, glossaries, ADRs/BDRs, …)",
            resourceDirectory: "Skeleton"
        ),
    ]

    static var builtInIDs: [String] { builtIn.map(\.id) }

    static func pack(id: String) -> StylePack? {
        let key = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return builtIn.first { $0.id == key }
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
            subdirectory: "Resources"
        ) else {
            throw ValidationError(
                "Internal error: style pack '\(pack.id)' resources not found (\(pack.resourceDirectory))."
            )
        }
        return url
    }

    static var helpListing: String {
        builtIn.map { "  \($0.id) — \($0.summary)" }.joined(separator: "\n")
    }
}
