import Foundation
import ArgumentParser

// MARK: - Build Command

struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build the documentation from Markdown sources into styled HTML.",
        discussion: "Assembles Markdown sources (single file via --input, or multi-file lex order by default per #3) then renders to HTML. See issues #4, #8, #9 for future enhancements."
    )

    @Option(name: .shortAndLong, help: "Path to a single input Markdown file. If omitted, discovers *.md/*.markdown files in the current directory, sorts lexicographically, skips READMEs and welcome-template.md, and concatenates them.")
    var input: String?

    @Option(name: .shortAndLong, help: "Output HTML path")
    var output: String = "output.html"

    @Flag(name: .long, help: "Skip diagram processing (placeholder for #5; geared for Mermaid)")
    var skipDiagrams: Bool = false

    func run() throws {
        let markdown = try DocumentGenerator.assembleSources(input: input)

        let html = try DocumentGenerator.generateHTML(from: markdown)
        try DocumentGenerator.writeOutput(html, to: output)

        if skipDiagrams {
            print("(Diagrams skipped as requested)")
        }
    }
}
