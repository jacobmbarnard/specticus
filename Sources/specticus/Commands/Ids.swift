import ArgumentParser

// MARK: - Ids Command Group (stub, see #6)

struct Ids: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage stable traceability IDs (BR1, TS2, ADR3, etc.).",
        discussion: """
            See GitHub issues #6, #32–#36, #66. IDs use simple form (BR1, BR2, TS1, … no dash \
            or padding). Must be unique. Default: H1–H2 may own IDs (#32). Counters: per-prefix \
            max+1, no reuse (#33). Drift sensitivity: ids.drift_sensitivity (strict / contentStrict \
            / contentStrictPlus; #36). Plain-text headings only (no Markdown in titles). \
            Content drift is never auto-accepted — use `ids accept-drift <ID>` for same-identity \
            rewording after review (#66).
            """,
        subcommands: [IdsAssign.self, IdsAcceptDrift.self]
    )

    func run() throws {
        print("Use `specticus ids assign` or `specticus ids accept-drift <ID>` (see issues #6, #66).")
    }
}
