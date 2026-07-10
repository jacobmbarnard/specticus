import ArgumentParser

struct IdsAssign: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "assign",
        abstract: "Assign missing stable IDs to document headers.",
        discussion: "IDs are simple (BR1, BR2, TS1, ...). Must be unique. Detects content drift (an existing ID's heading text has changed). See GitHub issue #6 for full requirements."
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
