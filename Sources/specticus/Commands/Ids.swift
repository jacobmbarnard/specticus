import ArgumentParser

// MARK: - Ids Command Group (stub, see #6)

struct Ids: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage stable traceability IDs (BR-*, TS-*, ADR-*, etc.).",
        discussion: "See GitHub issue #6 for the full traceability system.",
        subcommands: [IdsAssign.self]
    )

    func run() throws {
        print("Use `specticus ids assign` (see issue #6).")
    }
}
