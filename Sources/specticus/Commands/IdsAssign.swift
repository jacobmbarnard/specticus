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
            New numbers are (per-prefix max)+1, never reused (#33). See GitHub issue #6.
            """
    )

    @Flag(name: .shortAndLong, help: "Preview changes without writing files")
    var dryRun: Bool = false

    func run() throws {
        let project = try SpecticusProject.load()
        for warning in project.warnings {
            print("⚠️  \(warning)")
        }
        try IdsManager.assignIDs(project: project, dryRun: dryRun)
    }
}
