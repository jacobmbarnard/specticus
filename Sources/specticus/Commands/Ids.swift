import ArgumentParser

// MARK: - Ids Command Group (stub, see #6)

struct Ids: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage stable traceability IDs (BR1, TS2, ADR3, etc.).",
        discussion: "See GitHub issue #6. IDs use simple form (BR1, BR2, TS1, ... no dash or padding). Must be unique. Default: H1–H2 may own IDs (ids.heading_max_level, up to H6; #32). Counters are per-prefix max+1 with no reuse (#33). ids assign + lint detect content drift; build warns.",
        subcommands: [IdsAssign.self]
    )

    func run() throws {
        print("Use `specticus ids assign` (see issue #6).")
    }
}
