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

            Source mutation safety (#35):
            - Assign rewrites Markdown **in place** when new IDs are needed.
            - Prefer `specticus ids assign --dry-run` (add `--diff` for line-level patches) first.
            - Interactive sessions prompt before rewriting unless `--yes` is passed.
            - Non-interactive sessions require `--yes` to rewrite source files.
            - Git dirty paths that will be modified are reported as warnings.
            - Missing ids.json is recovered by bootstrapping from live Markdown IDs.
            """
    )

    @Flag(name: .shortAndLong, help: "Preview changes without writing files")
    var dryRun: Bool = false

    @Flag(name: .shortAndLong, help: "Skip confirmation and allow source rewrites (required when non-interactive)")
    var yes: Bool = false

    @Flag(name: .long, help: "Show line-level before/after for planned Markdown rewrites")
    var diff: Bool = false

    @Flag(name: .long, help: "Skip git dirty-tree warning for files about to change")
    var skipGitCheck: Bool = false

    func run() throws {
        let project = try SpecticusProject.load()
        for warning in project.warnings {
            print("⚠️  \(warning)")
        }
        var options = IdsManager.AssignOptions(
            dryRun: dryRun,
            assumeYes: yes || dryRun,
            showDiff: diff,
            checkGit: !skipGitCheck && !dryRun
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
