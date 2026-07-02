import ArgumentParser

// MARK: - Init Command (stub, see #2)

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Initialize a new specticus documentation project with templates and structure.",
        discussion: "See GitHub issue #2 for full implementation details."
    )

    @Argument(help: "Directory name for the new project (defaults to current directory)")
    var directory: String?

    func run() throws {
        let target = directory ?? "."
        print("specticus init is not yet implemented (issue #2).")
        print("Would scaffold templates, .specticus/ config, ADRs/, starter files into '\(target)'.")
        print("For now, you can manually create Markdown content and run `specticus build`.")
    }
}
