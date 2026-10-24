import Foundation

// MARK: - Lint rules (internals #22)

/// Shared inputs for every lint rule. Built once per `scs lint` run.
struct LintContext {
    let project: SpecticusProject
    let fm: FileManager
    let cwd: String
    let rootURL: URL
    let hasSpecticusDir: Bool
    let hasTitle: Bool
    let hasWelcome: Bool
    let usesVertical: Bool
    let mdFiles: [String]
    let hasNumberedSections: Bool
    let discovered: [URL]
    let discoverError: String?

    static func make(project: SpecticusProject, cwd: String, fm: FileManager = .default) -> LintContext {
        let rootURL = URL(fileURLWithPath: cwd, isDirectory: true)
        let hasSpecticusDir = project.hasSpecticusDirectory
        let hasTitle = fm.fileExists(atPath: project.titleURL.path)
        let hasWelcome = fm.fileExists(atPath: project.resolve("welcome-template.md").path)
        let usesVertical = TemplateSections.usesVerticalLayout(at: rootURL, fm: fm)
        let mdFiles = (try? fm.contentsOfDirectory(atPath: cwd).filter {
            let lower = $0.lowercased()
            return (lower.hasSuffix(".md") || lower.hasSuffix(".markdown")) &&
                !lower.hasPrefix("readme") &&
                !lower.hasPrefix(".")
        }) ?? []
        let hasNumberedSections = mdFiles.contains {
            $0.range(of: #"^\d{3}-"#, options: .regularExpression) != nil
        }

        let discovered: [URL]
        let discoverError: String?
        do {
            discovered = try MarkdownSources.discoverContentFiles(
                in: rootURL,
                layout: project.assemblyLayout
            )
            discoverError = nil
        } catch {
            discovered = []
            discoverError = error.localizedDescription
        }

        return LintContext(
            project: project,
            fm: fm,
            cwd: cwd,
            rootURL: rootURL,
            hasSpecticusDir: hasSpecticusDir,
            hasTitle: hasTitle,
            hasWelcome: hasWelcome,
            usesVertical: usesVertical,
            mdFiles: mdFiles,
            hasNumberedSections: hasNumberedSections,
            discovered: discovered,
            discoverError: discoverError
        )
    }
}

/// One function per check that exists today. `Lint.run` only loads, runs, prints.
enum LintRules {
    /// Ordered evaluation matching the previous procedural `Lint.run` sections.
    static func evaluate(_ context: LintContext) -> [LintFinding] {
        checkProjectMarkers(context)
            + checkSpecticusConfig(context)
            + checkProjectLoadWarnings(context)
            + checkTitleMetadata(context)
            + checkStylesheet(context)
            + checkContentDiscoveryError(context)
            + checkAssemblyLayout(context)
            + checkMarkdownContent(context)
            + checkDiagrams(context)
            + checkDecisionRecords(context)
            + checkAssembleSources(context)
            + checkAutoAssign(context)
            + checkTraceabilityIDs(context)
    }

    // MARK: - Project markers

    static func checkProjectMarkers(_ ctx: LintContext) -> [LintFinding] {
        if ctx.hasSpecticusDir || ctx.hasTitle || ctx.hasNumberedSections || ctx.hasWelcome || ctx.usesVertical {
            return [.pass("Detected specticus project (or partial/legacy project)")]
        }
        return [
            .warn(
                "No clear specticus project markers found in this directory.",
                suggestion: "Run `scs init` to scaffold a new project, or `cd` into an existing one."
            )
        ]
    }

    // MARK: - Config & style

    static func checkSpecticusConfig(_ ctx: LintContext) -> [LintFinding] {
        var findings: [LintFinding] = []
        if ctx.hasSpecticusDir {
            findings.append(.pass(".specticus/ directory present"))
            if ctx.project.hasConfigFile {
                if ctx.project.configSource == .file {
                    findings.append(.pass(".specticus/config.yml present and valid"))
                    findings.append(.pass(
                        "Config: output=\(ctx.project.config.build.output), css=\(ctx.project.config.build.css), copy_assets=\(ctx.project.config.build.copyAssets), track_builds=\(ctx.project.config.build.trackBuilds), diagrams=\(ctx.project.config.build.diagramsEnabled)"
                    ))
                    if let unknown = StylePackRegistry.unknownStyleDiagnostic(ctx.project.config.doc.style) {
                        findings.append(.warn(
                            unknown,
                            suggestion: "Set `doc.style` to a built-in pack (`scs init --help`) or omit it for `default` (#141)."
                        ))
                    } else {
                        findings.append(.pass("doc.style=\(ctx.project.config.doc.style)"))
                    }
                }
            } else {
                findings.append(.warn(
                    ".specticus/config.yml missing",
                    suggestion: "Re-run init or manually create a config file."
                ))
            }
        } else {
            findings.append(.warn(
                ".specticus/ directory not found (config lives here in modern projects)",
                suggestion: "Run `scs init` (or `scs init --force`) to create it."
            ))
        }
        return findings
    }

    static func checkProjectLoadWarnings(_ ctx: LintContext) -> [LintFinding] {
        ctx.project.warnings.map {
            .warn($0, suggestion: "Fix title.yml or remove it if unused.")
        }
    }

    static func checkTitleMetadata(_ ctx: LintContext) -> [LintFinding] {
        if ctx.hasTitle {
            if ctx.project.titleMetadata != nil {
                return [.pass("title.yml present and readable")]
            }
            return [
                .warn(
                    "title.yml present but could not be parsed",
                    suggestion: "Check YAML syntax (title, author, version, …)."
                )
            ]
        }
        return [
            .fail(
                "title.yml is missing",
                suggestion: "This provides project title, author, version, etc. Add it or run init."
            )
        ]
    }

    static func checkStylesheet(_ ctx: LintContext) -> [LintFinding] {
        let cssPath = ctx.project.resolve(ctx.project.styleSheetPath).path
        if ctx.fm.fileExists(atPath: cssPath) {
            return [.pass("\(ctx.project.styleSheetPath) present (for HTML styling)")]
        }
        return [
            .warn(
                "\(ctx.project.styleSheetPath) not found",
                suggestion: "The default theme is embedded in init; copy or restore it, or update build.css in config."
            )
        ]
    }

    // MARK: - Content & layout

    static func checkContentDiscoveryError(_ ctx: LintContext) -> [LintFinding] {
        guard let discoverError = ctx.discoverError else { return [] }
        return [.warn("Could not discover Markdown content: \(discoverError)")]
    }

    static func checkAssemblyLayout(_ ctx: LintContext) -> [LintFinding] {
        var findings: [LintFinding] = []
        let layout = ctx.project.assemblyLayout
        let dupOrders = layout.duplicateOrders
        if !dupOrders.isEmpty {
            findings.append(.warn(
                "Assembly layout has duplicate order values: \(dupOrders.map(String.init).joined(separator: ", "))",
                suggestion: "Give each assembly.sections[].order a unique integer in config.yml or layout.yml (#140)."
            ))
        }
        for id in layout.unknownSectionIDs {
            findings.append(.warn(
                "Assembly layout references unknown section id '\(id)'",
                suggestion: "Use a default pack folder id (see docs/template-sections.md) or create that folder."
            ))
        }
        if ctx.usesVertical {
            for spec in layout.sections {
                let sectionPath = ctx.rootURL.appendingPathComponent(spec.id, isDirectory: true).path
                var isDir: ObjCBool = false
                if !ctx.fm.fileExists(atPath: sectionPath, isDirectory: &isDir) || !isDir.boolValue {
                    if ctx.project.config.assembly.sections.contains(where: { $0.id == spec.id })
                        || FileManager.default.fileExists(atPath: ctx.project.layoutURL.path)
                    {
                        findings.append(.warn(
                            "Assembly section '\(spec.id)' (order \(spec.order)) has no folder on disk",
                            suggestion: "Create \(spec.id)/ or remove it from assembly layout (#140)."
                        ))
                    }
                }
            }
        }
        return findings
    }

    static func checkMarkdownContent(_ ctx: LintContext) -> [LintFinding] {
        var findings: [LintFinding] = []
        if ctx.usesVertical {
            let presentSections = TemplateSections.defaultOrder.filter { id in
                var isDir: ObjCBool = false
                let p = ctx.rootURL.appendingPathComponent(id, isDirectory: true).path
                return ctx.fm.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue
            }
            findings.append(.pass("Vertical section layout (#139): \(presentSections.count) section folder(s)"))
            if ctx.discovered.isEmpty {
                findings.append(.fail(
                    "No Markdown content under section folders",
                    suggestion: "Add `.md` files under folders such as `business-requirements/` or run `scs init`."
                ))
            } else {
                findings.append(.pass(
                    "Found \(ctx.discovered.count) content Markdown file(s) under section folders"
                ))
            }
            for kind in ["ADRs", "BDRs"] {
                let rejected = ctx.rootURL.appendingPathComponent(kind).appendingPathComponent("rejected")
                var isDir: ObjCBool = false
                if ctx.fm.fileExists(atPath: rejected.path, isDirectory: &isDir), isDir.boolValue {
                    findings.append(.pass("\(kind)/rejected/ present"))
                } else if ctx.fm.fileExists(atPath: ctx.rootURL.appendingPathComponent(kind).path) {
                    findings.append(.warn(
                        "\(kind)/rejected/ missing",
                        suggestion: "Add a `rejected/` status folder for declined decision records (#139)."
                    ))
                }
            }
        } else if ctx.hasNumberedSections {
            let numberedCount = ctx.mdFiles.filter {
                $0.range(of: #"^\d{3}-"#, options: .regularExpression) != nil
            }.count
            findings.append(.pass("Legacy flat layout: \(numberedCount) numbered section file(s) (00N-*.md)"))
        } else if ctx.hasWelcome {
            findings.append(.warn(
                "Only legacy welcome-template.md found (no section folders or 00N-*.md)",
                suggestion: "Run `scs init` for the vertical section layout (#139)."
            ))
        } else if !ctx.discovered.isEmpty || !ctx.mdFiles.isEmpty {
            findings.append(.warn(
                "Markdown present but not using vertical section folders",
                suggestion: "Prefer `business-requirements/`, `technical-specifications/`, … from `scs init` (#139)."
            ))
        } else {
            findings.append(.fail(
                "No Markdown content files found",
                suggestion: "Add at least one .md file or run `scs init`."
            ))
        }
        return findings
    }

    // MARK: - Diagrams & decision records

    static func checkDiagrams(_ ctx: LintContext) -> [LintFinding] {
        let diagramsDir = ctx.project.config.build.diagramsDir
        let diagramsPath = ctx.project.diagramsDirectory.path
        if ctx.fm.fileExists(atPath: diagramsPath) {
            let diagrams = (try? ctx.fm.contentsOfDirectory(atPath: diagramsPath).filter {
                $0.hasSuffix(".mmd")
            }) ?? []
            if !diagrams.isEmpty {
                return [.pass("\(diagramsDir)/ present with \(diagrams.count) Mermaid file(s)")]
            }
            return [
                .warn(
                    "\(diagramsDir)/ exists but contains no .mmd files",
                    suggestion: "Add Mermaid diagrams or remove the folder if unused."
                )
            ]
        }
        if ctx.project.config.build.diagramsEnabled {
            return [
                .warn(
                    "\(diagramsDir)/ directory not found",
                    suggestion: "Useful for architecture diagrams. Run init to create starter diagrams."
                )
            ]
        }
        return [.pass("Diagrams disabled in config (build.diagrams_enabled: false)")]
    }

    static func checkDecisionRecords(_ ctx: LintContext) -> [LintFinding] {
        var findings: [LintFinding] = []
        for (drType, enabled) in [
            ("ADRs", ctx.project.config.decisionRecords.adrsEnabled),
            ("BDRs", ctx.project.config.decisionRecords.bdrsEnabled)
        ] {
            if !enabled {
                findings.append(.pass("\(drType) disabled in config"))
                continue
            }
            let baseURL = ctx.rootURL.appendingPathComponent(drType, isDirectory: true)
            if ctx.fm.fileExists(atPath: baseURL.path) {
                let subdirs = ["accepted", "proposed", "deprecated", "superseded"]
                let missing = subdirs.filter {
                    !ctx.fm.fileExists(atPath: baseURL.appendingPathComponent($0).path)
                }
                if missing.isEmpty {
                    findings.append(.pass("\(drType)/ structure complete (all status folders)"))
                } else {
                    findings.append(.warn(
                        "\(drType)/ is incomplete (missing: \(missing.joined(separator: ", ")))",
                        suggestion: "Create the status subdirectories for proper record management."
                    ))
                }
            } else {
                findings.append(.warn(
                    "\(drType)/ directory missing",
                    suggestion: "Run `scs init` to scaffold ADRs/ + BDRs/ with examples."
                ))
            }
        }
        return findings
    }

    // MARK: - Assemble

    static func checkAssembleSources(_ ctx: LintContext) -> [LintFinding] {
        do {
            _ = try CommandBoundary.call {
                try DocumentGenerator.assembleSources(
                    input: nil,
                    baseDirectory: ctx.cwd,
                    fallbackInput: ctx.project.config.build.defaultInput,
                    layout: ctx.project.assemblyLayout
                )
            }
            return [.pass("Markdown sources assemble successfully (layout order / single file)")]
        } catch {
            return [
                .fail(
                    "Markdown sources failed to assemble",
                    suggestion: "Ensure section folders or Markdown files are present, or pass --input. Error: \(error.localizedDescription)"
                )
            ]
        }
    }

    // MARK: - IDs

    static func checkAutoAssign(_ ctx: LintContext) -> [LintFinding] {
        if ctx.project.config.ids.autoAssign {
            return [
                .warn(
                    "ids.auto_assign is true — build will REPORT pending ID assignments (dry-run only)",
                    suggestion: "Sources are not rewritten unless you pass `scs build --assign-ids` (#38). Prefer `scs ids assign --dry-run` then `--yes`. Never enable --assign-ids in shared CI unless intentional."
                )
            ]
        }
        return [
            .pass("ids.auto_assign is false (build will not run ID assign; safe default — #38)")
        ]
    }

    static func checkTraceabilityIDs(_ ctx: LintContext) -> [LintFinding] {
        do {
            let headings = try IdsManager.collectHeadings(project: ctx.project)
            var idToHeadings: [String: [IdsManager.HeadingInfo]] = [:]
            let store = IdsManager.loadStore(from: ctx.project.idsURL)
            let sensitivity = ctx.project.config.ids.driftSensitivity

            for h in headings {
                if let id = h.id {
                    idToHeadings[id, default: []].append(h)
                }
            }

            var findings: [LintFinding] = []

            let dups = idToHeadings.filter { $0.value.count > 1 }
            if !dups.isEmpty {
                var details: [String] = []
                for id in dups.keys.sorted() {
                    for h in dups[id] ?? [] {
                        details.append(
                            "\(id) @ \(h.file.lastPathComponent):\(h.lineIndex + 1) — \(h.content)"
                        )
                    }
                }
                findings.append(.fail(
                    "Duplicate traceability IDs found: \(dups.keys.sorted().joined(separator: ", "))",
                    suggestion: "Often concurrent `ids assign` (#39). Edit Markdown so each ID appears once; integrate latest docs before the next assign; commit Markdown + ids.json together.",
                    details: details
                ))
            } else {
                findings.append(.pass("No duplicate traceability IDs"))
            }

            let mdFindings = IdsManager.findMarkdownFormattedHeadings(in: headings)
            if !mdFindings.isEmpty {
                var details: [String] = []
                for m in mdFindings.prefix(5) {
                    details.append("e.g. \(m.file):\(m.lineIndex + 1): \(m.title)")
                }
                findings.append(.fail(
                    "\(mdFindings.count) heading(s) contain disallowed Markdown formatting (#36)",
                    suggestion: "Use plain text in headings (no **bold**, *italic*, `code`, [links](), or HTML).",
                    details: details
                ))
            } else {
                findings.append(.pass("No Markdown formatting in ID-eligible headings"))
            }

            let drifts = IdsManager.findContentDrifts(
                headings: headings,
                store: store,
                sensitivity: sensitivity
            )
            if !drifts.isEmpty {
                var details: [String] = []
                for d in drifts.prefix(8) {
                    details.append("\(d.id):")
                    details.append("  was: \(d.oldContent)")
                    details.append("  now: \(d.newContent)  (\(d.file))")
                }
                if drifts.count > 8 {
                    details.append("… and \(drifts.count - 8) more")
                }
                findings.append(.warn(
                    "\(drifts.count) ID(s) with content drift (mode=\(sensitivity.rawValue))",
                    suggestion: "Review old vs new text below; revert the heading, or run `scs ids accept-drift <ID>` for same-identity rewording (#66).",
                    details: details
                ))
            } else if !store.bindings.isEmpty {
                findings.append(.pass(
                    "No ID content drift detected (mode=\(sensitivity.rawValue); checked \(store.bindings.count) bound ID(s))"
                ))
            }

            let liveIDs = IdsManager.liveIDSet(from: headings)
            let orphans = IdsManager.findOrphans(store: store, liveIDs: liveIDs)
            let storeExists = FileManager.default.fileExists(atPath: ctx.project.idsURL.path)
            if !storeExists && !liveIDs.isEmpty {
                findings.append(.warn(
                    "ids.json is missing while Markdown claims \(liveIDs.count) ID(s)",
                    suggestion: "Run `scs ids assign` to bootstrap the store from Markdown (#37 recovery)."
                ))
            } else if orphans.isEmpty {
                if storeExists || !store.bindings.isEmpty {
                    findings.append(.pass("No orphan ID bindings in ids.json"))
                }
            } else {
                var details: [String] = []
                for o in orphans.prefix(8) {
                    details.append("\(o.id): \(o.content)")
                }
                if orphans.count > 8 {
                    details.append("… and \(orphans.count - 8) more")
                }
                findings.append(.warn(
                    "\(orphans.count) orphan ID binding(s) in ids.json (not claimed in Markdown)",
                    suggestion: "Orphans reserve numbers by design (#33). Leave for history, inspect with `scs ids status`, or after review `scs ids prune-orphans` (#37).",
                    details: details
                ))
            }

            return findings
        } catch {
            return [
                .warn("Could not fully validate traceability IDs: \(error.localizedDescription)")
            ]
        }
    }
}
