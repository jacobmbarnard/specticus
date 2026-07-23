import ArgumentParser

// MARK: - Ids Command Group (stub, see #6)

struct Ids: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage stable traceability IDs (BR1, TS2, ADR3, etc.).",
        discussion: """
            Recommended workflow and common pitfalls: docs/traceability-ids.md (#41). \
            See also GitHub issues #6, #32–#39, #66. IDs use simple form (BR1, BR2, TS1, … no dash \
            or padding). Must be unique. Default: H1–H2 may own IDs (#32). Counters: per-prefix \
            max+1, no reuse (#33). Drift sensitivity: ids.drift_sensitivity (strict / contentStrict \
            / contentStrictPlus; #36). Plain-text headings only (no Markdown in titles). \
            Content drift is never auto-accepted — use `ids accept-drift <ID>` for same-identity \
            rewording after review (#66). Orphan bindings (deleted headings) reserve numbers; \
            inspect with `ids status`, prune after review with `ids prune-orphans` (#37). \
            `ids assign` rewrites Markdown in place — preview with `--dry-run` / `--diff`, \
            confirm with `--yes` when non-interactive (#35). Build-time ids.auto_assign is \
            report-only; mutation requires `specticus build --assign-ids` (#38). Collaboration \
            (#39): duplicate live IDs block assign/lint (ID hygiene only — specticus never \
            latches onto git/fossil/svn or SCM merge markers).
            """,
        subcommands: [
            IdsAssign.self,
            IdsAcceptDrift.self,
            IdsStatus.self,
            IdsPruneOrphans.self
        ]
    )

    func run() throws {
        print("""
            Use:
              specticus ids assign --dry-run
              specticus ids assign --yes
              specticus ids accept-drift <ID>
              specticus ids status
              specticus ids prune-orphans
            Workflow guide: docs/traceability-ids.md (#41).
            (also issues #6, #35, #37, #66).
            """)
    }
}
