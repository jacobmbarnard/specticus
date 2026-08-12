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
                    ok("Config: output=\(project.config.build.output), css=\(project.config.build.css), copy_assets=\(project.config.build.copyAssets), track_builds=\(project.config.build.trackBuilds), diagrams=\(project.config.build.diagramsEnabled)")
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

        // --- Traceability IDs (#6 / #36 / #38)
        if project.config.ids.autoAssign {
            warn(
                "ids.auto_assign is true — build will REPORT pending ID assignments (dry-run only)",
                suggestion: "Sources are not rewritten unless you pass `specticus build --assign-ids` (#38). Prefer `specticus ids assign --dry-run` then `--yes`. Never enable --assign-ids in shared CI unless intentional."
            )
        } else {
            ok("ids.auto_assign is false (build will not run ID assign; safe default — #38)")
        }

        do {
            let headings = try IdsManager.collectHeadings(project: project)
            var idToHeadings: [String: [IdsManager.HeadingInfo]] = [:]
            let store = IdsManager.loadStore(from: project.idsURL)
            let sensitivity = project.config.ids.driftSensitivity

            // Collaboration hazards (#39): duplicate live IDs (ID hygiene only — no SCM artifacts).
            for h in headings {
                if let id = h.id {
                    idToHeadings[id, default: []].append(h)
                }
            }

            let dups = idToHeadings.filter { $0.value.count > 1 }
            if !dups.isEmpty {
                fail(
                    "Duplicate traceability IDs found: \(dups.keys.sorted().joined(separator: ", "))",
                    suggestion: "Often concurrent `ids assign` (#39). Edit Markdown so each ID appears once; integrate latest docs before the next assign; commit Markdown + ids.json together."
                )
                for id in dups.keys.sorted() {
                    for h in dups[id] ?? [] {
                        print("      \(id) @ \(h.file.lastPathComponent):\(h.lineIndex + 1) — \(h.content)")
                    }
                }
            } else {
                ok("No duplicate traceability IDs")
            }

            let mdFindings = IdsManager.findMarkdownFormattedHeadings(in: headings)
            if !mdFindings.isEmpty {
                fail("\(mdFindings.count) heading(s) contain disallowed Markdown formatting (#36)",
                     suggestion: "Use plain text in headings (no **bold**, *italic*, `code`, [links](), or HTML).")
                for m in mdFindings.prefix(5) {
                    print("      e.g. \(m.file):\(m.lineIndex + 1): \(m.title)")
                }
            } else {
                ok("No Markdown formatting in ID-eligible headings")
            }

            let drifts = IdsManager.findContentDrifts(
                headings: headings,
                store: store,
                sensitivity: sensitivity
            )
            if !drifts.isEmpty {
                warn("\(drifts.count) ID(s) with content drift (mode=\(sensitivity.rawValue))",
                     suggestion: "Review old vs new text below; revert the heading, or run `specticus ids accept-drift <ID>` for same-identity rewording (#66).")
                for d in drifts.prefix(8) {
                    print("      \(d.id):")
                    print("        was: \(d.oldContent)")
                    print("        now: \(d.newContent)  (\(d.file))")
                }
                if drifts.count > 8 {
                    print("      … and \(drifts.count - 8) more")
                }
            } else if !store.bindings.isEmpty {
                ok("No ID content drift detected (mode=\(sensitivity.rawValue); checked \(store.bindings.count) bound ID(s))")
            }

            // Orphans (#37): informational — reserved numbers are intentional (#33).
            let liveIDs = IdsManager.liveIDSet(from: headings)
            let orphans = IdsManager.findOrphans(store: store, liveIDs: liveIDs)
            let storeExists = FileManager.default.fileExists(atPath: project.idsURL.path)
            if !storeExists && !liveIDs.isEmpty {
                warn("ids.json is missing while Markdown claims \(liveIDs.count) ID(s)",
                     suggestion: "Run `specticus ids assign` to bootstrap the store from Markdown (#37 recovery).")
            } else if orphans.isEmpty {
                if storeExists || !store.bindings.isEmpty {
                    ok("No orphan ID bindings in ids.json")
                }
            } else {
                warn("\(orphans.count) orphan ID binding(s) in ids.json (not claimed in Markdown)",
                     suggestion: "Orphans reserve numbers by design (#33). Leave for history, inspect with `specticus ids status`, or after review `specticus ids prune-orphans` (#37).")
                for o in orphans.prefix(8) {
                    print("      \(o.id): \(o.content)")
                }
                if orphans.count > 8 {
                    print("      … and \(orphans.count - 8) more")
                }
            }
        } catch {
            warn("Could not fully validate traceability IDs: \(error.localizedDescription)")
        }

        // --- External tooling notes (Mermaid is client-rendered)
        print("\n  ℹ️  External tools:")
        print("      • Mermaid diagrams: rendered client-side in the output HTML (no CLI tool required).")
        print("      • For advanced Mermaid CLI rendering you can optionally install @mermaid-js/mermaid-cli.")
        print("  ℹ️  Config: .specticus/config.yml drives output path, CSS, asset copy, diagrams, build tracking (#8), and ID traceability settings (#6; #32 heading levels; #33 counters; #36 drift_sensitivity; #37 ids.json lifecycle; #38 auto_assign is report-only on build — mutation needs --assign-ids; #39 collaboration: duplicate live IDs / ID hygiene, SCM-agnostic). Lint enforces ID uniqueness, drift, plain-text headings, and reports orphans.")
        if project.hasSpecticusDirectory {
            if FileManager.default.fileExists(atPath: project.buildNumberURL.path) {
                if let record = try? BuildTracker.load(from: project.buildNumberURL) {
                    print("  ℹ️  Last recorded build: #\(record.number) at \(record.lastBuilt)")
                }
            }
        }

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
