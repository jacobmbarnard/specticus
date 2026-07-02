import Ink
import Foundation
import ArgumentParser

// MARK: - Core Generation (will be expanded in future issues)

struct DocumentGenerator {
    static func generateHTML(from markdown: String, title: String = "specticus • Documentation") throws -> String {
        let bodyHTML = MarkdownParser().html(from: markdown)

        return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>\(title)</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <header class="site-header">
        <div class="site-header-inner">
            <a href="#" class="site-title">specticus</a>
            <span class="site-nav text-muted">Documentation</span>
        </div>
    </header>

    <main class="main-content">
        <div class="page-content">
            \(bodyHTML)
        </div>
    </main>
</body>
</html>
"""
    }

    static func writeOutput(_ html: String, to path: String = "output.html") throws {
        let outputURL = URL(fileURLWithPath: path)
        try html.write(to: outputURL, atomically: true, encoding: .utf8)
        print("Wrote \(outputURL.lastPathComponent)")
    }
}

// MARK: - CLI

@main
struct Specticus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "specticus",
        abstract: "A fast, beautiful documentation generator for specifications as code.",
        version: "0.1.0",
        subcommands: [
            Build.self,
            Init.self,
            Lint.self,
            Clean.self,
            Ids.self
        ],
        defaultSubcommand: Build.self
    )
}

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

    @Flag(name: .long, help: "Skip diagram/PlantUML processing (placeholder for #5)")
    var skipPuml: Bool = false

    func run() throws {
        let templateURL = URL(fileURLWithPath: input)
        guard FileManager.default.fileExists(atPath: templateURL.path) else {
            throw ValidationError("Input file not found: \(input). Run `specticus init` (#2) to create a project, or specify --input.")
        }

        let markdown = try String(contentsOf: templateURL, encoding: .utf8)
        let html = try DocumentGenerator.generateHTML(from: markdown)
        try DocumentGenerator.writeOutput(html, to: output)

        if skipPuml {
            print("(PlantUML skipped as requested)")
        }
    }
}

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

// MARK: - Lint Command (stub, see #10)

struct Lint: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Validate the project structure, required files, and external tools.",
        discussion: "See GitHub issue #10."
    )

    func run() throws {
        print("specticus lint is not yet implemented (issue #10).")
        print("Planned checks: presence of key Markdown, config, CSS, PlantUML (when supported), etc.")
    }
}

// MARK: - Clean Command (stub)

struct Clean: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove generated output files and directories."
    )

    func run() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: "output.html") {
            try fm.removeItem(atPath: "output.html")
            print("Removed output.html")
        }
        // Future: also clean output/ dir, copied resources, etc. (#9)
        print("Clean complete (basic implementation; full version in follow-up work).")
    }
}

// MARK: - Ids Command Group + Subcommands (stub, see #6)

struct Ids: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage stable traceability IDs (BR-*, TS-*, ADR-*, etc.).",
        discussion: "See GitHub issue #6 for the full traceability system.",
        subcommands: [IdsAssign.self]
    )

    func run() throws {
        print("Use `specticus ids assign` (see issue #6).")
    }
}

struct IdsAssign: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "assign",
        abstract: "Assign missing stable IDs to document headers."
    )

    @Flag(name: .shortAndLong, help: "Preview changes without writing files")
    var dryRun: Bool = false

    func run() throws {
        print("specticus ids assign is not yet implemented (issue #6).")
        if dryRun {
            print("(would have been a dry-run)")
        }
    }
}
