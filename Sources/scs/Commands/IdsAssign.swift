import ArgumentParser

struct IdsAssign: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "assign",
        abstract: "Assign missing stable IDs to document headers.",
        discussion: """
            IDs are simple (BR1, BR2, TS1, ...). Must be unique. Detects content drift \
            (heading text vs ids.json; sensitivity via ids.drift_sensitivity, default strict — #36). \
            Never auto-accepts drift and never overwrites existing ID tokens. After review, rebind \
            one ID at a time with `specticus ids accept-drift <ID>` (#66). Rejects Markdown \
            formatting in headings. By default only H1–H2 may own IDs (ids.heading_max_level, #32). \
            New numbers are (per-prefix max)+1, never reused (#33). Orphan bindings (deleted \
            headings) are reported but left in place; use `ids status` / `ids prune-orphans` (#37).

            Source mutation safety (#35 / #38):
            - Assign rewrites Markdown **in place** when new IDs are needed.
            - Prefer `specticus ids assign --dry-run` (add `--diff` for line-level patches) first.
            - Interactive sessions prompt before rewriting unless `--yes` is passed.
            - Non-interactive sessions require `--yes` to rewrite source files.
            - Missing ids.json is recovered by bootstrapping from live Markdown IDs.
            - Build does not mutate sources when ids.auto_assign is true alone (#38);
              use `specticus build --assign-ids` only when you intentionally want that.

            Collaboration hazards (#39) — ID hygiene (SCM-agnostic by design):
            - Duplicate live IDs (classic concurrent `ids assign` fallout) block writes.
            - specticus does not model SCM merge markers or call git/fossil/svn for safety.
            - Optional git dirty-path hints remain convenience-only (--skip-git-check to silence).
            - Team tip: integrate latest docs before assign; commit Markdown + ids.json together.

            Skip feedback (#43):
            - Always prints a heading scan summary: considered counts, skips with reasons, syntax tips.
            - Pass --verbose to list every eligible heading considered for ownership.
            """
    )

    @Flag(name: .shortAndLong, help: "Preview changes without writing files")
    var dryRun: Bool = false

    @Flag(name: .shortAndLong, help: "Skip confirmation and allow source rewrites (required when non-interactive)")
    var yes: Bool = false

    @Flag(name: .long, help: "Show line-level before/after for planned Markdown rewrites")
    var diff: Bool = false

    @Flag(name: .long, help: "Skip optional git dirty-tree hint for files about to change (ID uniqueness checks are independent, #39)")
    var skipGitCheck: Bool = false

    @Flag(name: .long, help: "List every eligible heading considered for ID ownership (#43)")
    var verbose: Bool = false

    func run() throws {
        let project = try SpecticusProject.load()
        for warning in project.warnings {
            print("⚠️  \(warning)")
        }
        var options = IdsManager.AssignOptions(
            dryRun: dryRun,
            assumeYes: yes || dryRun,
            showDiff: diff,
            checkGit: !skipGitCheck && !dryRun,
            verbose: verbose
        )
        // Dry-run never writes; always safe without --yes.
        if dryRun {
            options.assumeYes = true
        }
        do {
            try IdsManager.assignIDs(project: project, options: options)
        } catch let error as IdsManager.AssignAbort {
            throw ValidationError(error.description)
        }
    }
}
