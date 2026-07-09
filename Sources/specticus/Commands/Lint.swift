import Foundation
import ArgumentParser

// MARK: - Lint Command (implements #10)

struct Lint: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Validate the project structure, required files, and external tools.",
        discussion: "Checks for a valid specticus project layout (from `specticus init`), key files, and build readiness. See issue #10."
    )

    func run() throws {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath

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
        let hasSpecticusDir = fm.fileExists(atPath: ".specticus")
        let hasTitle = fm.fileExists(atPath: "title.yml")
        let hasWelcome = fm.fileExists(atPath: "welcome-template.md")
        let mdFiles = (try? fm.contentsOfDirectory(atPath: cwd).filter {
            let lower = $0.lowercased()
            return (lower.hasSuffix(".md") || lower.hasSuffix(".markdown")) &&
                   !lower.hasPrefix("readme")
        }) ?? []
        let hasNumberedSections = mdFiles.contains { $0.range(of: #"^\d{3}-"#, options: .regularExpression) != nil }

        if hasSpecticusDir || hasTitle || hasNumberedSections || hasWelcome {
            ok("Detected specticus project (or partial/legacy project)")
        } else {
            warn("No clear specticus project markers found in this directory.",
                 suggestion: "Run `specticus init` to scaffold a new project, or `cd` into an existing one.")
        }

        // --- Core config & metadata
        if hasSpecticusDir {
            ok(".specticus/ directory present")
            if fm.fileExists(atPath: ".specticus/config.yml") {
                ok(".specticus/config.yml present")
            } else {
                warn(".specticus/config.yml missing", suggestion: "Re-run init or manually create a config file.")
            }
        } else {
            warn(".specticus/ directory not found (config lives here in modern projects)",
                 suggestion: "Run `specticus init` (or `specticus init --force`) to create it.")
        }

        if hasTitle {
            ok("title.yml present")
        } else {
            fail("title.yml is missing", suggestion: "This provides project title, author, version, etc. Add it or run init.")
        }

        // --- Style & assets
        if fm.fileExists(atPath: "style.css") {
            ok("style.css present (for HTML styling)")
        } else {
            warn("style.css not found", suggestion: "The default theme is embedded in init; copy or restore it.")
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

        // --- Diagrams
        let diagramsDir = "diagrams"
        if fm.fileExists(atPath: diagramsDir) {
            let diagrams = (try? fm.contentsOfDirectory(atPath: diagramsDir).filter { $0.hasSuffix(".mmd") }) ?? []
            if !diagrams.isEmpty {
                ok("diagrams/ present with \(diagrams.count) Mermaid file(s)")
            } else {
                warn("diagrams/ exists but contains no .mmd files",
                     suggestion: "Add Mermaid diagrams or remove the folder if unused.")
            }
        } else {
            warn("diagrams/ directory not found",
                 suggestion: "Useful for architecture diagrams. Run init to create starter diagrams.")
        }

        // --- Decision records
        for drType in ["ADRs", "BDRs"] {
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
            _ = try DocumentGenerator.assembleSources(input: nil, baseDirectory: cwd)
            ok("Markdown sources assemble successfully (lex order or single file)")
        } catch {
            fail("Markdown sources failed to assemble",
                 suggestion: "Run with a specific --input or ensure numbered .md files (or welcome-template.md) are present and readable. Error: \(error.localizedDescription)")
        }

        // --- External tooling notes (Mermaid is client-rendered)
        print("\n  ℹ️  External tools:")
        print("      • Mermaid diagrams: rendered client-side in the output HTML (no CLI tool required).")
        print("      • For advanced Mermaid CLI rendering you can optionally install @mermaid-js/mermaid-cli.")

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
