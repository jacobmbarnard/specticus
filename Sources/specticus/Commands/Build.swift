import Foundation
import ArgumentParser

// MARK: - Build Command

struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build the documentation from Markdown sources into styled HTML.",
        discussion: """
        Assembles Markdown sources (single file via --input, or multi-file lex order by default per #3) \
        then renders to HTML. Project settings load from `.specticus/config.yml` when present (#7). \
        Each build can increment a counter in `.specticus/build-number.yml` and stamp the HTML footer (#8). \
        Use `specticus lint` first to validate. CLI flags override config values.
        """
    )

    @Option(name: .shortAndLong, help: "Path to a single input Markdown file. If omitted, discovers *.md/*.markdown files in the current directory, sorts lexicographically, skips READMEs and welcome-template.md, and concatenates them.")
    var input: String?

    @Option(name: .shortAndLong, help: "Output HTML path (defaults to build.output in .specticus/config.yml, or output.html)")
    var output: String?

    @Flag(name: .long, help: "Skip diagram processing (placeholder for #5; geared for Mermaid)")
    var skipDiagrams: Bool = false

    @Flag(name: .long, help: "Do not increment build number or stamp the document footer (overrides build.track_builds)")
    var skipBuildTracking: Bool = false

    func run() throws {
        let project = try SpecticusProject.load()

        for warning in project.warnings {
            print("⚠️  \(warning)")
        }

        if project.configSource == .defaults {
            print("ℹ️  No .specticus/config.yml found — using built-in defaults. Run `specticus init` for a full project.")
        }

        let markdown = try DocumentGenerator.assembleSources(
            input: input,
            baseDirectory: project.root.path,
            fallbackInput: project.config.build.defaultInput
        )

        var buildInfo: BuildRecord?
        let trackingOn = project.config.build.trackBuilds && !skipBuildTracking
        if trackingOn {
            buildInfo = try BuildTracker.incrementAndSave(at: project.buildNumberURL)
            if let buildInfo {
                print("🔢 \(buildInfo.displayLine)")
            }
        }

        let html = try DocumentGenerator.generateHTML(
            from: markdown,
            title: project.documentTitle,
            stylesheet: project.styleSheetPath,
            buildInfo: buildInfo
        )

        let outputPath = output ?? project.defaultOutputPath
        try DocumentGenerator.writeOutput(html, to: outputPath)

        let diagramsOff = skipDiagrams || !project.config.build.diagramsEnabled
        if diagramsOff {
            print("(Diagrams skipped as requested)")
        }

        if project.config.ids.autoAssign {
            print("ℹ️  ids.auto_assign is enabled in config (auto-assign on build lands with issue #6).")
        }
    }
}
