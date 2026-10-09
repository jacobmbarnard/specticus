import Foundation

// MARK: - Library errors (#17)

/// Failures raised by library code (project load, assembly, style packs).
///
/// Commands translate this through `CommandBoundary` so the text users see
/// stays the same. Later internals steps (#18–#25) should throw
/// `SpecticusError` from library code. Do not add cases for failures that
/// do not exist yet.
enum SpecticusError: Error, Equatable, CustomStringConvertible, LocalizedError {
    /// `--input` (or another explicit path) does not exist.
    case missingInput(path: String)
    /// Assembly found no Markdown sources and no fallback file.
    case noMarkdownSources
    /// `.specticus/config.yml` exists but could not be parsed.
    case invalidConfig(path: String, reason: String)
    /// `doc.style` / `--style` is not a built-in pack.
    case unknownStylePack(id: String, known: String)
    /// A built-in pack's bundled skeleton is missing from the module resources.
    case missingBundledResources(packID: String, resourceParent: String, resourceDirectory: String)

    var description: String {
        switch self {
        case .missingInput(let path):
            return "Input file not found: \(path)."
        case .noMarkdownSources:
            return "No Markdown files found to assemble (looked for *.md / *.markdown). Specify --input or add content files."
        case .invalidConfig(let path, let reason):
            return "Failed to parse \(path): \(reason)"
        case .unknownStylePack(let id, let known):
            return "Unknown documentation style '\(id)'. Built-in styles: \(known)."
        case .missingBundledResources(let packID, let resourceParent, let resourceDirectory):
            return "Internal error: style pack '\(packID)' resources not found (\(resourceParent)/\(resourceDirectory))."
        }
    }

    var errorDescription: String? { description }
}
