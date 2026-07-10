import Foundation
import ArgumentParser

// MARK: - Build Command

struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build the documentation from Markdown sources into styled HTML.",
        discussion: """
        Assembles Markdown sources (single file via --input, or multi-file lex order by default per #3) \
        then renders to HTML. Project settings load from `.specticus/config.yml` when present (#7). \
        By default assets (CSS, images, SVGs) are copied into a structured tree next to the HTML (#9). \
        Use `specticus lint` first to validate. CLI flags override config values.
        """
    )

    @Option(name: .shortAndLong, help: "Path to a single input Markdown file. If omitted, discovers *.md/*.markdown files in the current directory, sorts lexicographically, skips READMEs and welcome-template.md, and concatenates them.")
    var input: String?

    @Option(name: .shortAndLong, help: "Output HTML path (defaults to build.output in .specticus/config.yml, or output/index.html)")
    var output: String?

    @Flag(name: .long, help: "Skip diagram processing (placeholder for #5; geared for Mermaid)")
    var skipDiagrams: Bool = false

    @Flag(name: .long, help: "Do not copy CSS/images/SVGs into the output tree (overrides build.copy_assets)")
    var skipAssets: Bool = false

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

        let outputPath = output ?? project.defaultOutputPath
        let copyAssets = project.config.build.copyAssets && !skipAssets

        let publish = try ResourcePublisher.publish(
            projectRoot: project.root,
            outputHTMLPath: outputPath,
            sourceCSS: project.styleSheetPath,
            diagramsDir: project.config.build.diagramsDir,
            copyAssets: copyAssets
        )

        var html = try DocumentGenerator.generateHTML(
            from: markdown,
            title: project.documentTitle,
            stylesheet: publish.stylesheetHref
        )
        html = ResourcePublisher.rewriteReferences(in: html, rewrites: publish.pathRewrites)

        // Resolve to absolute path under project for reliable writes
        let absoluteHTML = project.resolve(outputPath).path
        try DocumentGenerator.writeOutput(html, to: absoluteHTML)

        if !publish.copiedDescriptions.isEmpty {
            print("📦 Copied \(publish.copiedDescriptions.count) asset(s) into \(displayPath(publish.outputRoot.path, projectRoot: project.root.path))/")
            for item in publish.copiedDescriptions.prefix(12) {
                print("   • \(item)")
            }
            if publish.copiedDescriptions.count > 12 {
                print("   • … and \(publish.copiedDescriptions.count - 12) more")
            }
        } else if copyAssets {
            print("ℹ️  No CSS/images/SVGs found to copy (or copy_assets produced an empty set).")
        }

        let diagramsOff = skipDiagrams || !project.config.build.diagramsEnabled
        if diagramsOff {
            print("(Diagrams skipped as requested)")
        }

        if project.config.ids.autoAssign {
            print("ℹ️  ids.auto_assign is enabled in config (auto-assign on build lands with issue #6).")
        }
    }

    private func displayPath(_ path: String, projectRoot: String) -> String {
        if path.hasPrefix(projectRoot + "/") {
            return String(path.dropFirst(projectRoot.count + 1))
        }
        if path == projectRoot { return "." }
        return path
    }
}
