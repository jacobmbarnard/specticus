import Foundation

// MARK: - Traceability ID reporter (internals #20)
//
// Turns store / scan / assign results into the lines commands print today
// (including the heading scan summary). Commands and the build-time assign
// path call into this type.

enum IdsReporter {
    enum CollaborationReportStyle: Equatable, Sendable {
        case blocking
        case warning
        case status
    }

    static func printStoreLoadWarning(_ warning: String) {
        print(warning)
    }

    /// Print duplicate-ID fallout with concurrent-assign guidance (#39).
    static func printDuplicateIDReport(
        hazards: IdsAssigner.CollaborationHazards,
        style: CollaborationReportStyle = .blocking
    ) {
        guard !hazards.duplicateIDs.isEmpty else { return }
        let header: String
        switch style {
        case .blocking:
            header = "❌ Duplicate IDs found (must be unique) — often concurrent `ids assign` (#39):"
        case .warning:
            header = "⚠️  Duplicate IDs found (must be unique) — often concurrent `ids assign` (#39):"
        case .status:
            header = "  ❌ Duplicate claims (concurrent `ids assign` — #39): \(hazards.duplicateIDs.joined(separator: ", "))"
        }
        print(header)
        for id in hazards.duplicateIDs {
            if style != .status {
                print("   \(id)")
            }
            for loc in hazards.duplicateLocations[id] ?? [] {
                let prefix = style == .status ? "      " : "     - "
                print("\(prefix)\(loc)")
            }
        }
        if style == .status {
            print("      → Edit Markdown so each ID appears once; prefer one assigner per integrate cycle")
        } else {
            print("   → Keep one heading per ID; renumber or drop the other claim (never silent reuse — #33).")
            print("   → Team tip: integrate latest docs before `ids assign`; commit Markdown + ids.json together.")
        }
    }

    /// Print a human-readable lifecycle status report (#37 / #39). Does not mutate files.
    static func printStatus(project: SpecticusProject) throws {
        let report = try IdsAssigner.lifecycleReport(project: project)
        let sensitivity = project.config.ids.driftSensitivity
        let collab = try IdsAssigner.collectCollaborationHazards(project: project)

        print("📋 Traceability ID lifecycle status (#37 / #39)\n")

        if report.storeExists {
            print("  Store: .specticus/ids.json present (\(report.bindingCount) binding(s))")
        } else {
            print("  Store: .specticus/ids.json missing (treated as empty)")
            print("      → Recovery: run `scs ids assign` to bootstrap from Markdown IDs")
        }

        print("  Live IDs in Markdown: \(report.liveIDs.count)")
        if !report.liveIDs.isEmpty {
            let preview = report.liveIDs.prefix(12).joined(separator: ", ")
            let more = report.liveIDs.count > 12 ? ", …" : ""
            print("      \(preview)\(more)")
        }

        if collab.hasDuplicateIDs {
            printDuplicateIDReport(hazards: collab, style: .status)
        } else {
            print("  ✅ No duplicate live IDs")
        }

        if !report.unboundLiveIDs.isEmpty {
            print("  ℹ️  Live IDs not yet in store: \(report.unboundLiveIDs.joined(separator: ", "))")
            print("      → Run `scs ids assign` to bind them")
        }

        if !report.drifts.isEmpty {
            print("  ⚠️  Content drift (\(report.drifts.count); mode=\(sensitivity.rawValue)):")
            for d in report.drifts.prefix(8) {
                print("      \(d.id): was \"\(d.oldContent)\" → now \"\(d.newContent)\" (\(d.file))")
            }
            if report.drifts.count > 8 {
                print("      … and \(report.drifts.count - 8) more")
            }
            print("      → `scs ids accept-drift <ID>` after review (#66)")
        } else if report.bindingCount > 0 {
            print("  ✅ No content drift (mode=\(sensitivity.rawValue))")
        }

        if report.orphans.isEmpty {
            print("  ✅ No orphan bindings")
        } else {
            print("  ℹ️  Orphan bindings: \(report.orphans.count) (reserve numbers; not an error — #33/#37)")
            for o in report.orphans.prefix(12) {
                print("      \(o.id): \(o.content)")
            }
            if report.orphans.count > 12 {
                print("      … and \(report.orphans.count - 12) more")
            }
            print("      → Leave for audit history, or `scs ids prune-orphans` after review")
            print("      → Pruning removes the binding only; counters never decrease (numbers stay reserved)")
        }

        if !report.counters.isEmpty {
            let parts = report.counters.keys.sorted().compactMap { key -> String? in
                guard let v = report.counters[key] else { return nil }
                return "\(key)=\(v)"
            }
            print("  Counters (high-water): \(parts.joined(separator: ", "))")
        }

        print("""

          Divergence recovery cheat-sheet:
            • Missing ids.json          → ids assign (bootstrap)
            • Live ID not in store      → ids assign
            • Content drift             → ids accept-drift <ID>
            • Orphan (deleted heading)  → leave, or ids prune-orphans
            • Duplicate IDs             → edit Markdown so each ID is unique (#39)
            • Manual ids.json edit      → ok for advanced users; prefer CLI for audit trail

          Team workflow (ID hygiene — #39):
            • Integrate latest docs before `ids assign`; commit Markdown + ids.json together
            • Prefer one assign pass per integrate cycle to avoid duplicate ID minting
            • specticus cares about ID uniqueness and store coherence — not which SCM you use
        """)
    }

    static func printAcceptDrift(_ result: IdsAssigner.AcceptDriftResult) {
        print("✅ Accepted drift for \(result.id) (mode=\(result.sensitivity.rawValue))")
        print("   was: \(result.oldContent)")
        print("   now: \(result.newContent)  (\(result.source))")
        print("📝 Appended audit entry to \(result.auditURL.lastPathComponent)")
        print("💾 Updated \(result.storeURL.lastPathComponent)")
        print("   Note: accept-drift is for same-identity rewording only — not new requirements or ID reuse.")
    }

    static func printPruneOrphans(_ result: IdsAssigner.PruneOrphansResult) {
        if result.dryRun {
            print("Would prune \(result.pruned.count) orphan binding(s) (dry-run; counters unchanged):")
            for o in result.pruned {
                print("  \(o.id): \(o.content)")
            }
            print("   Note: numbers remain reserved (high-water counters are not lowered — #33).")
            return
        }

        print("✅ Pruned \(result.pruned.count) orphan binding(s) from \(result.storeURL.lastPathComponent)")
        for o in result.pruned {
            print("   − \(o.id): \(o.content)")
        }
        print("📝 Appended \(result.pruned.count) audit entr\(result.pruned.count == 1 ? "y" : "ies") to \(result.auditURL.lastPathComponent)")
        print("💾 Updated \(result.storeURL.lastPathComponent)")
        print("   Note: counters were not lowered — pruned numbers stay reserved and will not be reused (#33).")
    }

    /// Plan, report, confirm, and apply. Used by `ids assign`, build `--assign-ids`, and the facade.
    static func performAssign(project: SpecticusProject, options: IdsAssigner.AssignOptions) throws {
        let plan = try IdsAssigner.plan(project: project, options: options)
        printAssignPlan(plan)
        switch plan.disposition {
        case .dryRun, .blocked:
            return
        case .saveBindings, .mutate:
            if plan.disposition == .mutate {
                try confirmMutation(plan, options: options)
            }
            let applied = try IdsAssigner.apply(plan)
            printAssignApplied(applied)
        }
    }

    /// All assign output that happens before confirmation / writes.
    static func printAssignPlan(_ plan: IdsAssigner.AssignPlan) {
        if let warning = plan.storeLoadWarning {
            printStoreLoadWarning(warning)
        }

        let options = plan.options
        if options.autoAssignContext {
            switch options.buildAssignMode {
            case .reportOnly:
                print("""
                    ⚠️  ids.auto_assign is enabled — build is reporting pending ID assignments only (#38).
                       Markdown sources will NOT be rewritten during this build.
                       To apply assignments on build:  scs build --assign-ids
                       Or assign explicitly:           scs ids assign --dry-run
                                                       scs ids assign --yes
                       Disable reporting: set ids.auto_assign: false in .specticus/config.yml
                       ⚠️  --assign-ids REWRITES Markdown in place (dangerous in CI / shared checkouts).
                    """)
            case .mutate:
                print("""
                    🚨 BUILD --assign-ids: will run `ids assign` and may REWRITE Markdown sources in place (#38).
                       This is intentional only when you opted in with the flag (and/or ids.auto_assign).
                       Prefer a dedicated `scs ids assign --dry-run` then `--yes` workflow in CI.
                       Review the git diff before committing any rewritten sources.
                    """)
            case .off, nil:
                print("""
                    ⚠️  Build-time ID assign context (#35/#38).
                       Prefer: scs ids assign --dry-run  then  scs ids assign --yes
                    """)
            }
        }

        if plan.collab.hasDuplicateIDs {
            printDuplicateIDReport(hazards: plan.collab, style: .blocking)
        }

        if !plan.markdownHeadings.isEmpty {
            print("❌ Markdown formatting is not allowed in headings (#36):")
            for m in plan.markdownHeadings.prefix(20) {
                print("   \(m.file):\(m.lineIndex + 1): \(m.title)")
            }
            if plan.markdownHeadings.count > 20 {
                print("   ... and \(plan.markdownHeadings.count - 20) more")
            }
            print("   → Use plain text in headings (no **bold**, *italic*, `code`, [links](), or HTML).")
        }

        if !plan.drifts.isEmpty {
            print("⚠️  Content drift detected (ID kept but heading text changed; mode=\(plan.sensitivity.rawValue)):")
            for d in plan.drifts {
                print("   \(d.id):")
                print("     was: \(d.oldContent)")
                print("     now: \(d.newContent)  (\(d.file))")
            }
            print("   → Revert the heading text, or after review rebind one ID at a time:")
            print("      scs ids accept-drift <ID>   (same identity / reword only — #66)")
        }

        if !plan.orphans.isEmpty {
            print("ℹ️  \(plan.orphans.count) orphan binding(s) in ids.json (ID not claimed by any eligible heading; numbers still reserved — #37):")
            for o in plan.orphans.prefix(8) {
                print("   \(o.id): \(o.content)")
            }
            if plan.orphans.count > 8 {
                print("   ... and \(plan.orphans.count - 8) more")
            }
            print("   → Leave them for history, or after review: scs ids prune-orphans")
            print("   → Inspect: scs ids status")
        }

        printHeadingScanFeedback(
            scan: plan.scan,
            headingsWithIDs: plan.headingsWithIDs,
            headingsNeedingID: plan.headingsNeedingID,
            newlyAssigned: plan.newlyAssigned,
            assignSkips: plan.assignSkips,
            verbose: options.verbose
        )

        switch plan.disposition {
        case .dryRun:
            print("🔍 Dry-run: no files will be written (#35).")
            if !plan.newlyAssigned.isEmpty {
                print("Would assign \(plan.newlyAssigned.count) ID(s) and rewrite \(plan.filesToRewrite.count) Markdown file(s) in place:")
                for item in plan.newlyAssigned {
                    print("  \(item.newID): \(item.info.content)  [\(item.info.file.lastPathComponent):\(item.info.lineIndex + 1)]")
                }
                if options.showDiff {
                    printAssignDiffs(newlyAssigned: plan.newlyAssigned)
                } else {
                    print("   Tip: add --diff to see line-level before/after for each rewrite.")
                }
                print("Would also update .specticus/\(plan.storeURL.lastPathComponent)")
            } else if !plan.hasProblems {
                print("✅ No new IDs to assign. Would refresh \(plan.storeURL.lastPathComponent) bindings only (no Markdown rewrites).")
            }
            if plan.hasProblems {
                print("Note: problems above would block an actual (non-dry-run) write.")
            }
        case .blocked:
            if !plan.newlyAssigned.isEmpty {
                print("ℹ️  \(plan.newlyAssigned.count) heading(s) are ready for new IDs but were not written because of the problems above:")
                for item in plan.newlyAssigned.prefix(10) {
                    print("     would assign \(item.newID): \(item.info.content)  [\(item.info.file.lastPathComponent)]")
                }
                if plan.newlyAssigned.count > 10 {
                    print("     ... and \(plan.newlyAssigned.count - 10) more")
                }
            }
            print("Aborting write due to duplicates, drift, or other problems. Fix issues and re-run `ids assign` (#39).")
        case .saveBindings:
            break
        case .mutate:
            printAssignMutationPlan(
                newlyAssigned: plan.newlyAssigned,
                filesToRewrite: plan.filesToRewrite,
                storeName: plan.storeURL.lastPathComponent
            )
            if options.showDiff {
                printAssignDiffs(newlyAssigned: plan.newlyAssigned)
            }
            if !plan.gitDirtyPaths.isEmpty {
                print("⚠️  Optional VCS hint (git detected): uncommitted changes in path(s) that will be modified:")
                for name in plan.gitDirtyPaths {
                    print("     • \(name)")
                }
                print("   Consider integrating with teammates first. Not required — specticus does not depend on git (#39).")
            }
        }
    }

    static func printAssignApplied(_ result: IdsAssigner.AssignApplyResult) {
        switch result.disposition {
        case .saveBindings:
            print("💾 Updated \(result.storeURL.lastPathComponent) (no new IDs assigned; Markdown sources unchanged)")
        case .mutate:
            for item in result.rewritten {
                print("✍️  Assigned \(item.count) ID(s) in \(item.file.lastPathComponent)")
            }
            print("💾 Updated \(result.storeURL.lastPathComponent)")
            print("✅ Assign complete — review the Markdown diff in version control before committing.")
        case .dryRun, .blocked:
            break
        }
    }

    /// Human-readable mutation plan printed before writing source files.
    static func printAssignMutationPlan(
        newlyAssigned: [IdsAssigner.PendingAssignment],
        filesToRewrite: [URL],
        storeName: String
    ) {
        print("⚠️  Source mutation plan (#35) — `ids assign` rewrites Markdown in place:")
        print("   Will assign \(newlyAssigned.count) new ID(s) across \(filesToRewrite.count) file(s):")
        for file in filesToRewrite {
            let count = newlyAssigned.filter { $0.info.file == file }.count
            print("     • \(file.lastPathComponent) (\(count) ID(s))")
        }
        print("   Will update .specticus/\(storeName)")
        print("   Existing ID tokens are never overwritten; only missing IDs are injected.")
        print("   Tip: preview with `scs ids assign --dry-run` (add --diff for line patches).")
    }

    /// Print simple unified-style hunks for planned ID injections (not a full git patch).
    static func printAssignDiffs(newlyAssigned: [IdsAssigner.PendingAssignment]) {
        print("📄 Planned line changes:")
        let byFile = Dictionary(grouping: newlyAssigned, by: { $0.info.file })
        let files = byFile.keys.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in files {
            guard let items = byFile[file] else { continue }
            print("   --- \(file.lastPathComponent)")
            for item in items.sorted(by: { $0.info.lineIndex < $1.info.lineIndex }) {
                let newLine = IdsAssigner.addIDPrefix(to: item.info.originalLine, id: item.newID)
                print("   @@ line \(item.info.lineIndex + 1) @@")
                print("   - \(item.info.originalLine)")
                print("   + \(newLine)")
            }
        }
    }

    /// Print which headings were considered and why others were skipped (#43).
    static func printHeadingScanFeedback(
        scan: IdsScanner.HeadingScan,
        headingsWithIDs: Int,
        headingsNeedingID: Int,
        newlyAssigned: [IdsAssigner.PendingAssignment],
        assignSkips: [IdsAssigner.AssignSkip],
        verbose: Bool
    ) {
        let eligible = scan.eligible
        let excluded = scan.excluded
        let deeper = excluded.filter {
            if case .deeperThanMaxLevel = $0.exclusion { return true }
            return false
        }
        let inFence = excluded.filter { $0.exclusion == .insideCodeFence }
        let inQuote = excluded.filter { $0.exclusion == .insideBlockquote }
        let inTable = excluded.filter { $0.exclusion == .insideTable }
        let exclusionZoneCount = inFence.count + inQuote.count + inTable.count

        print("📋 Heading scan (#43) — ids.heading_max_level=\(scan.maxLevel) (eligible: H1–H\(scan.maxLevel))")
        print("   Considered for ID ownership: \(eligible.count)")
        print("     • already have IDs: \(headingsWithIDs)")
        print("     • missing IDs this pass: \(headingsNeedingID)")
        print("       – will assign: \(newlyAssigned.count)")
        print("       – skipped: \(assignSkips.count)")
        if !excluded.isEmpty {
            print("   Not eligible for ownership:")
            if !deeper.isEmpty {
                print("     • deeper than H\(scan.maxLevel): \(deeper.count)")
            }
            if exclusionZoneCount > 0 {
                print("     • in code fence / blockquote / table: \(exclusionZoneCount)")
                if !inFence.isEmpty { print("         – code fence: \(inFence.count)") }
                if !inQuote.isEmpty { print("         – blockquote: \(inQuote.count)") }
                if !inTable.isEmpty { print("         – table: \(inTable.count)") }
            }
        }

        if verbose {
            print("   Eligible headings considered:")
            for h in eligible {
                let idPart = h.id.map { " [\($0)]" } ?? " [no ID]"
                print("     • \(h.file.lastPathComponent):\(h.lineIndex + 1)  H\(h.level)\(idPart)  \(h.content)")
            }
            if eligible.isEmpty {
                print("     (none)")
            }
        } else if !eligible.isEmpty {
            print("   Tip: pass --verbose to list every eligible heading considered.")
        }

        var interestingExcluded: [(IdsScanner.HeadingObservation, IdsScanner.HeadingSkipReason, String?)] = []
        for obs in excluded {
            guard let reason = obs.exclusion else { continue }
            let cleaned = HeadingNumberer.stripOutlinePrefix(from: obs.title)
            let malformed = IdsScanner.diagnoseUnrecognizedIDForm(in: cleaned)
            let hasKnownPrefixToken = cleaned.range(
                of: #"\b(?:BR|TS|UC|ADR|BDR|TC|BC|REF|DIAG|REV)\d+"#,
                options: .regularExpression
            ) != nil
            let looksIntentional: Bool
            if IdsScanner.parseID(from: cleaned) != nil {
                looksIntentional = true
            } else if malformed != nil || hasKnownPrefixToken {
                looksIntentional = true
            } else {
                looksIntentional = false
            }
            if looksIntentional {
                interestingExcluded.append((obs, reason, malformed))
            }
        }

        if !interestingExcluded.isEmpty {
            print("⚠️  Headings that look ID-related but are not eligible owners:")
            let limit = 20
            for (obs, reason, malformed) in interestingExcluded.prefix(limit) {
                print("   \(obs.location)  H\(obs.level)  \(obs.title)")
                if let malformed {
                    print("     reason: \(malformed)")
                    print("     tip: \(IdsScanner.HeadingSkipReason.unrecognizedIDForm(detail: malformed).syntaxTip)")
                } else {
                    print("     reason: \(reason.shortLabel)")
                    print("     tip: \(reason.syntaxTip)")
                }
            }
            if interestingExcluded.count > limit {
                print("   ... and \(interestingExcluded.count - limit) more")
            }
        }

        if !assignSkips.isEmpty {
            print("ℹ️  Skipped \(assignSkips.count) eligible heading(s) (no ID assigned):")
            let limit = 25
            for skip in assignSkips.prefix(limit) {
                print("   \(skip.info.file.lastPathComponent):\(skip.info.lineIndex + 1)  H\(skip.info.level)  \(skip.info.content)")
                print("     reason: \(skip.reason.shortLabel)")
                print("     tip: \(skip.reason.syntaxTip)")
            }
            if assignSkips.count > limit {
                print("   ... and \(assignSkips.count - limit) more")
            }
            print("   Preferred owning form: `## BR1: Descriptive title` (see docs/traceability-ids.md).")
        }
    }

    /// Prompt on stdout/stdin for y/N. Empty or anything other than y/yes is false.
    static func promptYesNo(_ message: String) -> Bool {
        print(message, terminator: "")
        guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return line == "y" || line == "yes"
    }

    static func confirmMutation(
        _ plan: IdsAssigner.AssignPlan,
        options: IdsAssigner.AssignOptions
    ) throws {
        let interactive = options.isInteractive ?? IdsAssigner.isInteractiveTerminal()
        if !options.assumeYes {
            if interactive {
                let prompt = "Proceed with rewriting \(plan.filesToRewrite.count) Markdown file(s) in place? [y/N]: "
                let confirmed: Bool
                if let handler = options.confirmHandler {
                    confirmed = handler(prompt)
                } else {
                    confirmed = promptYesNo(prompt)
                }
                if !confirmed {
                    print("Cancelled — no files written.")
                    throw IdsAssigner.AssignAbort.userDeclined
                }
            } else {
                throw IdsAssigner.AssignAbort.nonInteractiveRequiresYes(fileCount: plan.filesToRewrite.count)
            }
        }
    }
}
