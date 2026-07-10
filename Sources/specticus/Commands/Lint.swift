import Foundation
import ArgumentParser

// MARK: - Lint Command (implements #10; config validation via #7)

struct Lint: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Validate the project structure, required files, and external tools.",
        discussion: "Checks for a valid specticus project layout (from `specticus init`), key files, `.specticus/config.yml`, and build readiness. See issues #10 and #7."
    )

    func run() throws {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        let project = try SpecticusProject.load(from: cwd)

        print("🔍 Running specticus lint...\n")

        var passed = 0
        var warnings = 0
        var failures = 0

        func ok(_ msg: String) {
            print("  ✅ \(msg)")
            passed += 1
        }
        func warn(_ msg: String, suggestion: String? = nil) {
            print("  ⚠️  \(msg)")
            if let s = suggestion { print("      → \(s)") }
            warnings += 1
        }
        func fail(_ msg: String, suggestion: String? = nil) {
            print("  ❌ \(msg)")
            if let s = suggestion { print("      → \(s)") }
            failures += 1
        }

        // --- Project detection
        let hasSpecticusDir = project.hasSpecticusDirectory
        let hasTitle = fm.fileExists(atPath: project.titleURL.path)
        let hasWelcome = fm.fileExists(atPath: project.resolve("welcome-template.md").path)
        let mdFiles = (try? fm.contentsOfDirectory(atPath: cwd).filter {
            let lower = $0.lowercased()
            return (lower.hasSuffix(".md") || lower.hasSuffix(".markdown")) &&
                   !lower.hasPrefix("readme") &&
                   !lower.hasPrefix(".")
        }) ?? []
        let hasNumberedSections = mdFiles.contains { $0.range(of: #"^\d{3}-"#, options: .regularExpression) != nil }

        if hasSpecticusDir || hasTitle || hasNumberedSections || hasWelcome {
            ok("Detected specticus project (or partial/legacy project)")
        } else {
            warn("No clear specticus project markers found in this directory.",
                 suggestion: "Run `specticus init` to scaffold a new project, or `cd` into an existing one.")
        }

        // --- Core config & metadata (#7)
        if hasSpecticusDir {
            ok(".specticus/ directory present")
            if project.hasConfigFile {
                if project.configSource == .file {
                    ok(".specticus/config.yml present and valid")
                    ok("Config: output=\(project.config.build.output), css=\(project.config.build.css), copy_assets=\(project.config.build.copyAssets), diagrams=\(project.config.build.diagramsEnabled)")
                }
            } else {
                warn(".specticus/config.yml missing", suggestion: "Re-run init or manually create a config file.")
            }
        } else {
            warn(".specticus/ directory not found (config lives here in modern projects)",
                 suggestion: "Run `specticus init` (or `specticus init --force`) to create it.")
        }

        for w in project.warnings {
            warn(w, suggestion: "Fix title.yml or remove it if unused.")
        }

        if hasTitle {
            if project.titleMetadata != nil {
                ok("title.yml present and readable")
            } else {
                warn("title.yml present but could not be parsed",
                     suggestion: "Check YAML syntax (title, author, version, …).")
            }
        } else {
            fail("title.yml is missing", suggestion: "This provides project title, author, version, etc. Add it or run init.")
        }

        // --- Style & assets (respect config css path)
        let cssPath = project.resolve(project.styleSheetPath).path
        if fm.fileExists(atPath: cssPath) {
            ok("\(project.styleSheetPath) present (for HTML styling)")
        } else {
            warn("\(project.styleSheetPath) not found",
                 suggestion: "The default theme is embedded in init; copy or restore it, or update build.css in config.")
        }

        // --- Markdown content
        if hasNumberedSections {
            let numberedCount = mdFiles.filter { $0.range(of: #"^\d{3}-"#, options: .regularExpression) != nil }.count
            ok("Found \(numberedCount) numbered section file(s) (00N-*.md)")
        } else if hasWelcome {
            warn("Only legacy welcome-template.md found (no 00N-*.md sections)",
                 suggestion: "Consider migrating to the modern numbered section layout from `specticus init`.")
        } else if !mdFiles.isEmpty {
            warn("Markdown files present but none follow the recommended 00N-*.md naming",
                 suggestion: "Rename or add numbered sections for reliable lex-order assembly.")
        } else {
            fail("No Markdown content files found", suggestion: "Add at least one .md file or run `specticus init`.")
        }

        // --- Diagrams (config diagrams_dir)
        let diagramsDir = project.config.build.diagramsDir
        let diagramsPath = project.diagramsDirectory.path
        if fm.fileExists(atPath: diagramsPath) {
            let diagrams = (try? fm.contentsOfDirectory(atPath: diagramsPath).filter { $0.hasSuffix(".mmd") }) ?? []
            if !diagrams.isEmpty {
                ok("\(diagramsDir)/ present with \(diagrams.count) Mermaid file(s)")
            } else {
                warn("\(diagramsDir)/ exists but contains no .mmd files",
                     suggestion: "Add Mermaid diagrams or remove the folder if unused.")
            }
        } else if project.config.build.diagramsEnabled {
            warn("\(diagramsDir)/ directory not found",
                 suggestion: "Useful for architecture diagrams. Run init to create starter diagrams.")
        } else {
            ok("Diagrams disabled in config (build.diagrams_enabled: false)")
        }

        // --- Decision records
        for (drType, enabled) in [
            ("ADRs", project.config.decisionRecords.adrsEnabled),
            ("BDRs", project.config.decisionRecords.bdrsEnabled)
        ] {
            if !enabled {
                ok("\(drType) disabled in config")
                continue
            }
            let base = drType
            if fm.fileExists(atPath: base) {
                let subdirs = ["accepted", "proposed", "deprecated", "superseded"]
                let missing = subdirs.filter { !fm.fileExists(atPath: "\(base)/\($0)") }
                if missing.isEmpty {
                    ok("\(base)/ structure complete (all status folders)")
                } else {
                    warn("\(base)/ is incomplete (missing: \(missing.joined(separator: ", ")))",
                         suggestion: "Create the status subdirectories for proper record management.")
                }
            } else {
                warn("\(base)/ directory missing",
                     suggestion: "Run `specticus init` to scaffold ADRs/ + BDRs/ with examples.")
            }
        }

        // --- Build readiness (lightweight check)
        do {
            _ = try DocumentGenerator.assembleSources(
                input: nil,
                baseDirectory: cwd,
                fallbackInput: project.config.build.defaultInput
            )
            ok("Markdown sources assemble successfully (lex order or single file)")
        } catch {
            fail("Markdown sources failed to assemble",
                 suggestion: "Run with a specific --input or ensure numbered .md files (or welcome-template.md) are present and readable. Error: \(error.localizedDescription)")
        }

        // --- External tooling notes (Mermaid is client-rendered)
        print("\n  ℹ️  External tools:")
        print("      • Mermaid diagrams: rendered client-side in the output HTML (no CLI tool required).")
        print("      • For advanced Mermaid CLI rendering you can optionally install @mermaid-js/mermaid-cli.")
        print("  ℹ️  Config: .specticus/config.yml drives output path, CSS, asset copy, diagrams, and future ID settings.")

        // --- Summary
        print("\n📊 Lint summary:")
        print("   Passed: \(passed)   Warnings: \(warnings)   Failures: \(failures)")

        if failures > 0 {
            print("\nSome critical items need attention before a clean build.")
        } else if warnings > 0 {
            print("\nProject is mostly ready — address warnings for best results.")
        } else {
            print("\n✅ Everything looks good! Try: specticus build")
        }
    }
}
