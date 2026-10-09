import ArgumentParser

// MARK: - Export Command Group (#5)

struct Export: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Write derived artifacts (GFM and future formats). Sources stay canonical.",
        discussion: """
            Export produces reviewable copies of the assembled spec. Edit Markdown sources \
            under the project; re-run export after changes. See docs/export.md and issue #5.
            """,
        subcommands: [
            ExportMarkdown.self
        ]
    )

    func run() throws {
        print("""
            Use:
              scs export markdown
              scs export markdown --output path/to/spec.md
            Docs: docs/export.md (#5).
            """)
    }
}
