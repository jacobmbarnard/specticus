import Foundation
import ArgumentParser

// MARK: - Build Command (current functionality + foundation)

struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build the documentation from Markdown sources into styled HTML.",
        discussion: "Currently builds from welcome-template.md (or equivalent). Full multi-file assembly, numbering, etc. tracked in issues #3, #4, #8, #9."
    )

    @Option(name: .shortAndLong, help: "Path to input markdown file (default: welcome-template.md)")
    var input: String = "welcome-template.md"

    @Option(name: .shortAndLong, help: "Output HTML path")
    var output: String = "output.html"

    @Flag(name: .long, help: "Skip diagram processing (placeholder for #5; geared for Mermaid)")
    var skipDiagrams: Bool = false

    func run() throws {
        let templateURL = URL(fileURLWithPath: input)
        guard FileManager.default.fileExists(atPath: templateURL.path) else {
            throw ValidationError("Input file not found: \(input). Run `specticus init` (#2) to create a project, or specify --input.")
        }

        let markdown = try String(contentsOf: templateURL, encoding: .utf8)
        let html = try DocumentGenerator.generateHTML(from: markdown)
        try DocumentGenerator.writeOutput(html, to: output)

        if skipDiagrams {
            print("(Diagrams skipped as requested)")
        }
    }
}
