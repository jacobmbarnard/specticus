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
        Each build can increment a counter in `.specticus/build-number.yml` and stamp the HTML footer (#8). \
        Headings are auto-numbered hierarchically through level 3 by default (#4; config up to 6). \
        A hyperlinked table of contents is injected by default (#12). \
        Use `specticus lint` first to validate. CLI flags override config values.

        Traceability IDs / auto_assign safety (#38):
        - ids.auto_assign: true only reports pending ID assignments during build (dry-run; no source writes).
        - Actual Markdown mutation on build requires explicit --assign-ids (dangerous in CI/shared repos).
        - Safer default workflow: specticus ids assign --dry-run  then  specticus ids assign --yes.
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

    @Flag(name: .long, help: "Do not increment build number or stamp the document footer (overrides build.track_builds)")
    var skipBuildTracking: Bool = false

    @Flag(name: .long, help: "Do not auto-number headings (overrides build.heading_number_max_level)")
    var skipHeadingNumbers: Bool = false

    @Flag(name: .long, help: "Do not generate a table of contents (overrides build.toc)")
    var skipToc: Bool = false

    @Flag(
        name: .long,
        help: """
            Explicitly run ids assign and allow rewriting Markdown sources in place during build (#38). \
            Without this flag, ids.auto_assign only prints a dry-run report. Prefer \
            `specticus ids assign --dry-run` / `--yes` over baking mutation into CI builds.
            """
    )
    var assignIds: Bool = false

    func run() throws {
        let project = try SpecticusProject.load()

        for warning in project.warnings {
            print("⚠️  \(warning)")
        }

        if project.configSource == .defaults {
            print("ℹ️  No .specticus/config.yml found — using built-in defaults. Run `specticus init` for a full project.")
        }

        var markdown = try DocumentGenerator.assembleSources(
            input: input,
            baseDirectory: project.root.path,
            fallbackInput: project.config.build.defaultInput
        )

        // Hierarchical section numbers (#4) — independent of traceability IDs (#6).
        let headingMax = skipHeadingNumbers ? 0 : project.config.build.headingNumberMaxLevel
        if headingMax > 0 {
            markdown = HeadingNumberer.numberHeadings(in: markdown, maxLevel: headingMax)
        }

        var buildInfo: BuildRecord?
        let trackingOn = project.config.build.trackBuilds && !skipBuildTracking
        if trackingOn {
            buildInfo = try BuildTracker.incrementAndSave(at: project.buildNumberURL)
            if let buildInfo {
                print("🔢 \(buildInfo.displayLine)")
            }
        }

        let outputPath = output ?? project.defaultOutputPath
        let copyAssets = project.config.build.copyAssets && !skipAssets

        let publish = try ResourcePublisher.publish(
            projectRoot: project.root,
            outputHTMLPath: outputPath,
            sourceCSS: project.styleSheetPath,
            diagramsDir: project.config.build.diagramsDir,
            copyAssets: copyAssets
        )

        let tocMax: Int = {
            if skipToc || !project.config.build.tocEnabled { return 0 }
            return project.config.build.tocMaxLevel
        }()

        var html = try DocumentGenerator.generateHTML(
            from: markdown,
            title: project.documentTitle,
            stylesheet: publish.stylesheetHref,
            buildInfo: buildInfo,
            tocMaxLevel: tocMax
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

        // Traceability checks (#6 / #36): warn on drift and disallowed Markdown in headings.
        // Build still succeeds; assign/lint treat these as stronger problems.
        do {
            let headings = try IdsManager.collectHeadings(project: project)
            let store = IdsManager.loadStore(from: project.idsURL)
            let sensitivity = project.config.ids.driftSensitivity
            let drifts = IdsManager.findContentDrifts(
                headings: headings,
                store: store,
                sensitivity: sensitivity
            )
            let mdFindings = IdsManager.findMarkdownFormattedHeadings(in: headings)

            if !mdFindings.isEmpty {
                print("⚠️  \(mdFindings.count) heading(s) contain disallowed Markdown formatting (#36). Use plain text in headings.")
                for m in mdFindings.prefix(5) {
                    print("   \(m.file):\(m.lineIndex + 1): \(m.title)")
                }
            }
            if !drifts.isEmpty {
                print("⚠️  \(drifts.count) ID content drift(s) detected (mode=\(sensitivity.rawValue)):")
                for d in drifts.prefix(8) {
                    print("   \(d.id):")
                    print("     was: \(d.oldContent)")
                    print("     now: \(d.newContent)  (\(d.file))")
                }
                if drifts.count > 8 {
                    print("   … and \(drifts.count - 8) more")
                }
            }
        } catch {
            print("⚠️  Could not validate traceability IDs during build: \(error.localizedDescription)")
        }

        // Traceability assign during build (#38): report-only unless --assign-ids.
        // ids.auto_assign alone never mutates sources (CI / shared-repo foot-gun).
        let assignMode = IdsManager.resolveBuildAssignMode(
            autoAssign: project.config.ids.autoAssign,
            assignIdsFlag: assignIds
        )
        if assignMode != .off {
            if assignMode == .mutate && !project.config.ids.autoAssign {
                print("""
                    ℹ️  --assign-ids without ids.auto_assign: one-shot source mutation for this build (#38).
                       Consider enabling ids.auto_assign only if you want dry-run reports on every build.
                    """)
            }
            do {
                try IdsManager.assignIDs(
                    project: project,
                    options: .forBuild(mode: assignMode)
                )
            } catch {
                print("⚠️  Build-time ID assign encountered an issue: \(error.localizedDescription)")
            }
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
