import ArgumentParser

// MARK: - Lint Command (stub, see #10)

struct Lint: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Validate the project structure, required files, and external tools.",
        discussion: "See GitHub issue #10."
    )

    func run() throws {
        print("specticus lint is not yet implemented (issue #10).")
        print("Planned checks: presence of key Markdown, config, CSS, Mermaid diagrams (when supported), etc.")
    }
}
