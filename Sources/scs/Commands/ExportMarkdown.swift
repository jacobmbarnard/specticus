import Foundation
import ArgumentParser

// MARK: - Export Markdown (GFM monolith, #5)

struct ExportMarkdown: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "markdown",
        abstract: "Export a GitHub-flavored Markdown monolith for PRs and human review.",
        discussion: """
            Assembles the same Markdown sources as `scs build`, optionally numbers headings \
            and injects a Contents list, keeps owning traceability IDs in headings, copies \
            media into the output tree when build.copy_assets is on, and writes a derived \
            `.md` file (default `output/export.md`). Sources remain the source of truth (#5).
            """
    )

    @Option(name: .shortAndLong, help: "Path to a single input Markdown file (same as build --input).")
    var input: String? = nil

    @Option(name: .shortAndLong, help: "Output Markdown path (defaults to build.markdown_export, or output/export.md).")
    var output: String? = nil

    @Flag(name: .long, help: "Do not copy CSS/images/SVGs into the output tree (overrides build.copy_assets).")
    var skipAssets: Bool = false

    @Flag(name: .long, help: "Do not auto-number headings (overrides build.heading_number_max_level).")
    var skipHeadingNumbers: Bool = false

    @Flag(name: .long, help: "Do not generate a Contents list (overrides build.toc).")
    var skipToc: Bool = false

    func run() throws {
        let project = try SpecticusProject.load()

        for warning in project.warnings {
            print("⚠️  \(warning)")
        }

        if project.configSource == .defaults {
            print("ℹ️  No .specticus/config.yml found — using built-in defaults. Run `scs init` for a full project.")
        }

        if let unknownStyle = StylePackRegistry.unknownStyleDiagnostic(project.config.doc.style) {
            print("⚠️  \(unknownStyle)")
        }

        let result = try MarkdownExporter.export(
            project: project,
            options: MarkdownExporter.Options(
                input: input,
                output: output,
                skipAssets: skipAssets,
                skipHeadingNumbers: skipHeadingNumbers,
                skipToc: skipToc
            )
        )

        if result.copiedAssetCount > 0 {
            print(
                "📦 Copied \(result.copiedAssetCount) asset(s) into \(displayPath(result.outputRootPath, projectRoot: project.root.path))/"
            )
        } else if project.config.build.copyAssets && !skipAssets {
            print("ℹ️  No CSS/images/SVGs found to copy (or copy_assets produced an empty set).")
        }

        print("✅ GFM export ready (derived; sources stay canonical).")
    }

    private func displayPath(_ path: String, projectRoot: String) -> String {
        if path.hasPrefix(projectRoot + "/") {
            return String(path.dropFirst(projectRoot.count + 1))
        }
        if path == projectRoot { return "." }
        return path
    }
}
