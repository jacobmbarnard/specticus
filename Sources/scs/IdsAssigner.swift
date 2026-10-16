import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Traceability ID assigner (internals #20)
//
// Mint, drift compare, accept-drift, prune-orphans. Returns result values. No printing.

enum IdsAssigner {
    struct DriftFinding: Equatable, Sendable {
        let id: String
        let oldContent: String
        let newContent: String
        let file: String
    }

    struct PendingAssignment {
        let info: IdsScanner.HeadingInfo
        let newID: String
    }

    struct AssignSkip {
        let info: IdsScanner.HeadingInfo
        let reason: IdsScanner.HeadingSkipReason
    }

    // MARK: - Collaboration hazards (#39, SCM-agnostic)

    /// Snapshot of collaboration / ID-hygiene signals for assign, lint, build, status.
    ///
    /// Detection is **content-based** and limited to traceability IDs — no SCM integration
    /// and no modeling of tool-specific merge artifacts. Teams using any VCS (or none)
    /// get the same advice when live IDs are duplicated after concurrent assigns.
    struct CollaborationHazards: Equatable, Sendable {
        /// Live IDs claimed by more than one eligible heading (often concurrent `ids assign`).
        let duplicateIDs: [String]
        /// Per-duplicate claim locations (`file:line — content`).
        let duplicateLocations: [String: [String]]

        var hasDuplicateIDs: Bool { !duplicateIDs.isEmpty }
        /// True when assign must not write / lint should fail.
        var hasBlockingProblems: Bool { hasDuplicateIDs }
    }

    /// Collect collaboration hazards from live headings (#39 — ID hygiene only).
    static func collectCollaborationHazards(project: SpecticusProject) throws -> CollaborationHazards {
        let headings = try IdsScanner.collectHeadings(project: project)
        return collectCollaborationHazards(project: project, headings: headings)
    }

    /// Same as `collectCollaborationHazards(project:)` when headings are already loaded.
    static func collectCollaborationHazards(
        project: SpecticusProject,
        headings: [IdsScanner.HeadingInfo]
    ) -> CollaborationHazards {
        var idToInfos: [String: [IdsScanner.HeadingInfo]] = [:]
        for h in headings {
            if let id = h.id {
                idToInfos[id, default: []].append(h)
            }
        }
        let duplicates = idToInfos.filter { $0.value.count > 1 }
        let duplicateIDs = duplicates.keys.sorted()
        var locations: [String: [String]] = [:]
        for id in duplicateIDs {
            locations[id] = (duplicates[id] ?? []).map { h in
                "\(h.file.lastPathComponent):\(h.lineIndex + 1) — \(h.content)"
            }
        }
        return CollaborationHazards(
            duplicateIDs: duplicateIDs,
            duplicateLocations: locations
        )
    }

    // MARK: - Assign options & safety (#35 / #38)

    /// How `scs build` may invoke ID assignment (#38).
    ///
    /// `ids.auto_assign: true` alone never rewrites Markdown during build — it only reports.
    /// Actual source mutation requires an explicit `scs build --assign-ids` (or a separate
    /// `scs ids assign --yes`). This reduces foot-guns in CI and shared repos.
    enum BuildAssignMode: String, Equatable, Sendable {
        /// Do not run assign during build.
        case off
        /// `ids.auto_assign` is on: dry-run report only (no writes).
        case reportOnly
        /// Explicit `--assign-ids`: may rewrite Markdown in place.
        case mutate
    }

    /// Resolve build-time assign policy from config + CLI (#38).
    ///
    /// - `--assign-ids` always wins (explicit consent for this invocation).
    /// - Else `ids.auto_assign: true` → report-only dry-run.
    /// - Else off.
    static func resolveBuildAssignMode(autoAssign: Bool, assignIdsFlag: Bool) -> BuildAssignMode {
        if assignIdsFlag { return .mutate }
        if autoAssign { return .reportOnly }
        return .off
    }

    /// Options for `ids assign` write safety and UX (#35 / #38).
    ///
    /// Programmatic / test callers typically use `assumeYes: true` (default) so confirmation
    /// is not required. The CLI sets `assumeYes` from `--yes` and enables interactive prompts.
    struct AssignOptions: Sendable {
        var dryRun: Bool = false
        /// When true, skip the interactive confirmation prompt.
        var assumeYes: Bool = true
        /// Print line-level before/after for planned Markdown rewrites.
        var showDiff: Bool = false
        /// Warn when git has uncommitted changes in files about to be rewritten.
        var checkGit: Bool = true
        /// When true, list every eligible heading considered for IDs (#43).
        var verbose: Bool = false
        /// Override TTY detection (`nil` = detect via `isatty`). Used by tests.
        var isInteractive: Bool? = nil
        /// Override confirmation prompt. Return `true` to proceed. Used by tests.
        var confirmHandler: (@Sendable (String) -> Bool)? = nil
        /// When true, print a stronger banner (e.g. build-time assign).
        var autoAssignContext: Bool = false
        /// Build-time mode for banner wording (#38). Ignored unless `autoAssignContext` is true.
        var buildAssignMode: BuildAssignMode? = nil

        static func dryRunOnly(showDiff: Bool = false, verbose: Bool = false) -> AssignOptions {
            AssignOptions(dryRun: true, assumeYes: true, showDiff: showDiff, verbose: verbose)
        }

        /// Options for build-time assign under #38 policy.
        static func forBuild(mode: BuildAssignMode) -> AssignOptions {
            switch mode {
            case .off:
                // Caller should not invoke assign; defensive defaults.
                return AssignOptions(dryRun: true, assumeYes: true, autoAssignContext: false)
            case .reportOnly:
                return AssignOptions(
                    dryRun: true,
                    assumeYes: true,
                    showDiff: false,
                    checkGit: false,
                    autoAssignContext: true,
                    buildAssignMode: .reportOnly
                )
            case .mutate:
                return AssignOptions(
                    dryRun: false,
                    assumeYes: true,
                    showDiff: false,
                    checkGit: true,
                    autoAssignContext: true,
                    buildAssignMode: .mutate
                )
            }
        }
    }

    enum AssignAbort: Error, Equatable, CustomStringConvertible, LocalizedError {
        case userDeclined
        case nonInteractiveRequiresYes(fileCount: Int)

        var description: String {
            switch self {
            case .userDeclined:
                return "Assign cancelled — no files were written. Re-run with --yes to skip the prompt, or --dry-run to preview."
            case .nonInteractiveRequiresYes(let n):
                return "Assign would rewrite \(n) Markdown source file(s) in place, but this session is non-interactive. Re-run with --yes to confirm, or --dry-run to preview (#35)."
            }
        }

        var errorDescription: String? { description }
    }

    /// What a planned assign will do after reporting (no writes until `apply`).
    enum AssignDisposition: Equatable, Sendable {
        case dryRun
        case blocked
        case saveBindings
        case mutate
    }

    /// Planned assign: findings + in-memory store. No files written.
    struct AssignPlan {
        let options: AssignOptions
        let store: IdStore
        let storeURL: URL
        let storeLoadFileName: String?
        let storeLoadErrorDescription: String?
        let sensitivity: SpecticusConfig.DriftSensitivity
        let scan: IdsScanner.HeadingScan
        let headings: [IdsScanner.HeadingInfo]
        let collab: CollaborationHazards
        let markdownHeadings: [IdsScanner.MarkdownHeadingFinding]
        let drifts: [DriftFinding]
        let orphans: [IdsStore.OrphanFinding]
        let newlyAssigned: [PendingAssignment]
        let assignSkips: [AssignSkip]
        let hasProblems: Bool
        let filesToRewrite: [URL]
        let gitDirtyPaths: [String]
        let disposition: AssignDisposition

        var headingsWithIDs: Int { headings.filter { $0.id != nil }.count }
        var headingsNeedingID: Int { headings.filter { $0.id == nil }.count }
        var storeLoadWarning: String? {
            guard let fileName = storeLoadFileName, let description = storeLoadErrorDescription else {
                return nil
            }
            return "⚠️  Could not read \(fileName), starting fresh: \(description)"
        }
    }

    /// Result of applying an assign plan (Markdown rewrites + store save).
    struct AssignApplyResult {
        let rewritten: [(file: URL, count: Int)]
        let storeURL: URL
        let savedStore: Bool
        let disposition: AssignDisposition
    }

    /// Snapshot of store vs Markdown for status / lint (#37 / #39).
    struct LifecycleReport: Equatable, Sendable {
        /// Whether `.specticus/ids.json` exists on disk.
        let storeExists: Bool
        /// Sorted live IDs claimed by exactly one eligible heading.
        let liveIDs: [String]
        /// Orphan bindings (in store, not in Markdown).
        let orphans: [IdsStore.OrphanFinding]
        /// IDs claimed by more than one heading.
        let duplicateIDs: [String]
        /// Live Markdown IDs that have no binding yet (will be bound on next successful assign).
        let unboundLiveIDs: [String]
        /// Content drift under the project's sensitivity.
        let drifts: [DriftFinding]
        /// Per-prefix high-water marks after raising from store bindings.
        let counters: [String: Int]
        /// Total bindings currently recorded.
        let bindingCount: Int
    }

    /// Result of a successful `ids accept-drift`.
    struct AcceptDriftResult: Equatable, Sendable {
        let id: String
        let oldContent: String
        let newContent: String
        let source: String
        let actor: String
        let note: String?
        let auditURL: URL
        let storeURL: URL
        let sensitivity: SpecticusConfig.DriftSensitivity
    }

    /// Failure modes for `acceptDrift`. Callers map these to user-facing errors / non-zero exit.
    enum AcceptDriftError: Error, Equatable, CustomStringConvertible, LocalizedError {
        case notInStore(id: String)
        case notInMarkdown(id: String)
        case duplicateClaims(id: String, locations: [String])
        case noDrift(id: String, content: String)
        case auditWriteFailed(message: String)
        case storeWriteFailed(message: String)

        var description: String {
            switch self {
            case .notInStore(let id):
                return "ID \(id) is not present in .specticus/ids.json bindings. Nothing to rebind."
            case .notInMarkdown(let id):
                return "ID \(id) is not claimed by any eligible heading in Markdown. Cannot accept drift for an orphan binding."
            case .duplicateClaims(let id, let locations):
                let locs = locations.joined(separator: ", ")
                return "ID \(id) is claimed by multiple headings (\(locs)). Resolve the duplicate before accept-drift; do not use accept-drift to merge duplicates."
            case .noDrift(let id, let content):
                return "ID \(id) has no content drift under the current sensitivity (bound text already matches: \"\(content)\"). No changes made."
            case .auditWriteFailed(let message):
                return "Failed to write audit log (binding not updated — fail closed): \(message)"
            case .storeWriteFailed(let message):
                return "Failed to update ids.json after audit log write: \(message)"
            }
        }

        var errorDescription: String? { description }
    }

    /// Result of a successful `ids prune-orphans` run.
    struct PruneOrphansResult: Equatable, Sendable {
        let pruned: [IdsStore.OrphanFinding]
        let actor: String
        let note: String?
        let auditURL: URL
        let storeURL: URL
        let dryRun: Bool
    }

    /// Failure modes for `pruneOrphans`.
    enum PruneOrphansError: Error, Equatable, CustomStringConvertible, LocalizedError {
        case noOrphans
        case idNotOrphan(id: String, reason: String)
        case auditWriteFailed(message: String)
        case storeWriteFailed(message: String)

        var description: String {
            switch self {
            case .noOrphans:
                return "No orphan bindings to prune. ids.json bindings all match live Markdown claims (or the store is empty)."
            case .idNotOrphan(let id, let reason):
                return "Cannot prune \(id): \(reason)"
            case .auditWriteFailed(let message):
                return "Failed to write audit log (bindings not pruned — fail closed): \(message)"
            case .storeWriteFailed(let message):
                return "Failed to update ids.json after audit log write: \(message)"
            }
        }

        var errorDescription: String? { description }
    }

    /// Analyze the project and return a plan. Does not write files.
    static func plan(project: SpecticusProject, options: AssignOptions) throws -> AssignPlan {
        let dryRun = options.dryRun
        let storeURL = project.idsURL
        let loaded = IdsStore.load(from: storeURL)
        var store = loaded.store
        let sensitivity = project.config.ids.driftSensitivity

        let scan = try IdsScanner.scanHeadings(project: project)
        let headings = scan.eligible

        let collab = collectCollaborationHazards(project: project, headings: headings)

        var idToInfos: [String: [IdsScanner.HeadingInfo]] = [:]
        var headingsNeedingID: [IdsScanner.HeadingInfo] = []
        var drifts: [DriftFinding] = []
        var markdownHeadings: [IdsScanner.MarkdownHeadingFinding] = []

        IdsStore.raiseHighWaterMarks(in: &store)

        for h in headings {
            let titleForMd = HeadingNumberer.stripOutlinePrefix(from: h.title)
            if IdsScanner.headingContainsDisallowedMarkdown(titleForMd) {
                markdownHeadings.append(IdsScanner.MarkdownHeadingFinding(
                    file: h.file.lastPathComponent,
                    lineIndex: h.lineIndex,
                    title: titleForMd
                ))
            }

            if let id = h.id {
                idToInfos[id, default: []].append(h)
                IdsStore.noteObservedID(id, in: &store)

                if let bound = store.bindings[id],
                   isContentDrift(bound: bound, current: h.content, sensitivity: sensitivity) {
                    drifts.append(DriftFinding(
                        id: id,
                        oldContent: bound,
                        newContent: h.content,
                        file: h.file.lastPathComponent
                    ))
                }

                store.bindings[id] = h.content
            } else {
                headingsNeedingID.append(h)
            }
        }

        var hasProblems = false
        if collab.hasDuplicateIDs {
            hasProblems = true
        }
        if !markdownHeadings.isEmpty {
            hasProblems = true
        }
        if !drifts.isEmpty {
            hasProblems = true
        }

        let liveIDs = Set(idToInfos.keys)
        let orphans = IdsStore.findOrphans(store: store, liveIDs: liveIDs)

        let fileContextPrefix = dominantPrefixByFile(in: headings)

        var newlyAssigned: [PendingAssignment] = []
        var assignSkips: [AssignSkip] = []
        for h in headingsNeedingID {
            let cleanedTitle = HeadingNumberer.stripOutlinePrefix(from: h.title)
            if let detail = IdsScanner.diagnoseUnrecognizedIDForm(in: cleanedTitle) {
                assignSkips.append(AssignSkip(info: h, reason: .unrecognizedIDForm(detail: detail)))
                continue
            }
            if IdsScanner.isStructuralSectionTitle(cleanedTitle, file: h.file) {
                assignSkips.append(AssignSkip(info: h, reason: .structuralSectionTitle))
                continue
            }
            guard let prefix = resolvePrefix(for: h, fileContextPrefix: fileContextPrefix[h.file]) else {
                assignSkips.append(AssignSkip(info: h, reason: .noPrefixInferred))
                continue
            }
            let newID = IdsStore.allocateNextID(prefix: prefix, store: &store)
            store.bindings[newID] = h.content
            newlyAssigned.append(PendingAssignment(info: h, newID: newID))
        }

        let byFile = Dictionary(grouping: newlyAssigned, by: { $0.info.file })
        let filesToRewrite = byFile.keys.sorted { $0.lastPathComponent < $1.lastPathComponent }

        let disposition: AssignDisposition
        if dryRun {
            disposition = .dryRun
        } else if hasProblems {
            disposition = .blocked
        } else if newlyAssigned.isEmpty {
            disposition = .saveBindings
        } else {
            disposition = .mutate
        }

        var gitDirtyPaths: [String] = []
        if disposition == .mutate, options.checkGit {
            var candidates = filesToRewrite
            candidates.append(storeURL)
            gitDirtyPaths = GitWorkspace.dirtyPaths(among: candidates, in: project.root)
        }

        return AssignPlan(
            options: options,
            store: store,
            storeURL: storeURL,
            storeLoadFileName: loaded.fileName,
            storeLoadErrorDescription: loaded.errorDescription,
            sensitivity: sensitivity,
            scan: scan,
            headings: headings,
            collab: collab,
            markdownHeadings: markdownHeadings,
            drifts: drifts,
            orphans: orphans,
            newlyAssigned: newlyAssigned,
            assignSkips: assignSkips,
            hasProblems: hasProblems,
            filesToRewrite: filesToRewrite,
            gitDirtyPaths: gitDirtyPaths,
            disposition: disposition
        )
    }

    /// Write Markdown rewrites and/or `ids.json` for a plan that is allowed to mutate.
    static func apply(_ plan: AssignPlan) throws -> AssignApplyResult {
        switch plan.disposition {
        case .dryRun, .blocked:
            return AssignApplyResult(
                rewritten: [],
                storeURL: plan.storeURL,
                savedStore: false,
                disposition: plan.disposition
            )
        case .saveBindings:
            try IdsStore.save(plan.store, to: plan.storeURL)
            return AssignApplyResult(
                rewritten: [],
                storeURL: plan.storeURL,
                savedStore: true,
                disposition: .saveBindings
            )
        case .mutate:
            let byFile = Dictionary(grouping: plan.newlyAssigned, by: { $0.info.file })
            var rewritten: [(file: URL, count: Int)] = []
            for file in plan.filesToRewrite {
                guard let items = byFile[file] else { continue }
                var lines = try String(contentsOf: file, encoding: .utf8)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)

                for item in items {
                    lines[item.info.lineIndex] = addIDPrefix(to: item.info.originalLine, id: item.newID)
                }

                let joined = lines.joined(separator: "\n")
                let final = lines.last == "" ? joined : joined + "\n"
                try final.write(to: file, atomically: true, encoding: .utf8)
                rewritten.append((file, items.count))
            }

            try IdsStore.save(plan.store, to: plan.storeURL)
            return AssignApplyResult(
                rewritten: rewritten,
                storeURL: plan.storeURL,
                savedStore: true,
                disposition: .mutate
            )
        }
    }

    /// Whether stdin is attached to a terminal (interactive session).
    static func isInteractiveTerminal() -> Bool {
        // Prefer STDIN_FILENO over `stdin` — the latter is a mutable global and
        // trips Swift 6 concurrency diagnostics on Linux.
        isatty(STDIN_FILENO) != 0
    }

    // MARK: - Accept drift (#66)

    /// Explicitly rebind a single ID’s stored content to the current heading text after review.
    ///
    /// This is **accept-drift**, not reassignment:
    /// - Updates only `ids.json` bindings for `<id>`
    /// - Never rewrites the Markdown ID token
    /// - Never mints, renumbers, reuses, or bulk-accepts other IDs
    /// - Requires true drift under `ids.drift_sensitivity` (#36)
    /// - Requires a durable audit log entry; if the log cannot be written, the binding is not updated
    @discardableResult
    static func acceptDrift(
        project: SpecticusProject,
        id rawID: String,
        note: String? = nil,
        actor: String? = nil,
        auditURL: URL? = nil,
        storeURL: URL? = nil,
        now: Date = Date()
    ) throws -> AcceptDriftResult {
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedStoreURL = storeURL ?? project.idsURL
        let resolvedAuditURL = auditURL ?? project.idsAuditURL
        let sensitivity = project.config.ids.driftSensitivity
        let resolvedActor = actor ?? IdsStore.currentActor()
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = (trimmedNote?.isEmpty == false) ? trimmedNote : nil

        let loaded = IdsStore.load(from: resolvedStoreURL)
        var store = loaded.store

        guard let oldContent = store.bindings[id] else {
            throw AcceptDriftError.notInStore(id: id)
        }

        let headings = try IdsScanner.collectHeadings(project: project)
        let claims = headings.filter { $0.id == id }

        if claims.isEmpty {
            throw AcceptDriftError.notInMarkdown(id: id)
        }
        if claims.count > 1 {
            let locations = claims.map { "\($0.file.lastPathComponent):\($0.lineIndex + 1)" }
            throw AcceptDriftError.duplicateClaims(id: id, locations: locations)
        }

        let heading = claims[0]
        let newContent = heading.content
        let source = "\(heading.file.lastPathComponent):\(heading.lineIndex + 1)"

        guard isContentDrift(bound: oldContent, current: newContent, sensitivity: sensitivity) else {
            throw AcceptDriftError.noDrift(id: id, content: oldContent)
        }

        let event = IdsStore.AuditEvent(
            timestamp: IdsStore.iso8601UTCString(from: now),
            event: "accept-drift",
            id: id,
            oldContent: oldContent,
            newContent: newContent,
            source: source,
            actor: resolvedActor,
            note: noteValue
        )

        do {
            try IdsStore.appendAuditEvent(event, to: resolvedAuditURL)
        } catch let err as AcceptDriftError {
            throw err
        } catch {
            throw AcceptDriftError.auditWriteFailed(message: error.localizedDescription)
        }

        store.bindings[id] = newContent
        do {
            try IdsStore.save(store, to: resolvedStoreURL)
        } catch let err as AcceptDriftError {
            throw err
        } catch {
            throw AcceptDriftError.storeWriteFailed(message: error.localizedDescription)
        }

        return AcceptDriftResult(
            id: id,
            oldContent: oldContent,
            newContent: newContent,
            source: source,
            actor: resolvedActor,
            note: noteValue,
            auditURL: resolvedAuditURL,
            storeURL: resolvedStoreURL,
            sensitivity: sensitivity
        )
    }

    /// Build a lifecycle report for `ids status` / lint (#37).
    static func lifecycleReport(project: SpecticusProject) throws -> LifecycleReport {
        let storeURL = project.idsURL
        let storeExists = FileManager.default.fileExists(atPath: storeURL.path)
        let loaded = IdsStore.load(from: storeURL)
        var store = loaded.store
        IdsStore.raiseHighWaterMarks(in: &store)

        let headings = try IdsScanner.collectHeadings(project: project)
        let sensitivity = project.config.ids.driftSensitivity

        var idToInfos: [String: [IdsScanner.HeadingInfo]] = [:]
        for h in headings {
            if let id = h.id {
                idToInfos[id, default: []].append(h)
            }
        }

        let liveIDs = Set(idToInfos.keys)
        let orphans = IdsStore.findOrphans(store: store, liveIDs: liveIDs)
        let duplicates = idToInfos.filter { $0.value.count > 1 }.keys.sorted()
        let unbound = liveIDs.filter { store.bindings[$0] == nil }.sorted()
        let drifts = findContentDrifts(headings: headings, store: store, sensitivity: sensitivity)

        return LifecycleReport(
            storeExists: storeExists,
            liveIDs: liveIDs.sorted(),
            orphans: orphans,
            duplicateIDs: duplicates,
            unboundLiveIDs: unbound,
            drifts: drifts,
            counters: store.counters,
            bindingCount: store.bindings.count
        )
    }

    /// Remove orphan bindings from the store after explicit review (#37).
    ///
    /// - Removes binding entries only (content history for that ID in the store).
    /// - **Never** lowers counters — pruned numbers remain reserved (#33).
    /// - Writes one audit event per pruned ID; fail closed if audit cannot be written.
    /// - Does not rewrite Markdown.
    @discardableResult
    static func pruneOrphans(
        project: SpecticusProject,
        onlyID: String? = nil,
        dryRun: Bool = false,
        note: String? = nil,
        actor: String? = nil,
        auditURL: URL? = nil,
        storeURL: URL? = nil,
        now: Date = Date()
    ) throws -> PruneOrphansResult {
        let resolvedStoreURL = storeURL ?? project.idsURL
        let resolvedAuditURL = auditURL ?? project.idsAuditURL
        let resolvedActor = actor ?? IdsStore.currentActor()
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = (trimmedNote?.isEmpty == false) ? trimmedNote : nil

        let loaded = IdsStore.load(from: resolvedStoreURL)
        var store = loaded.store
        IdsStore.raiseHighWaterMarks(in: &store)
        let countersBefore = store.counters

        let headings = try IdsScanner.collectHeadings(project: project)
        let liveIDs = IdsScanner.liveIDSet(from: headings)
        let allOrphans = IdsStore.findOrphans(store: store, liveIDs: liveIDs)

        let toPrune: [IdsStore.OrphanFinding]
        if let raw = onlyID {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if liveIDs.contains(id) {
                throw PruneOrphansError.idNotOrphan(
                    id: id,
                    reason: "it is claimed by a live Markdown heading. Remove or change the heading first, or leave the binding."
                )
            }
            guard let bound = store.bindings[id] else {
                throw PruneOrphansError.idNotOrphan(
                    id: id,
                    reason: "it is not present in ids.json bindings."
                )
            }
            toPrune = [IdsStore.OrphanFinding(id: id, content: bound)]
        } else {
            toPrune = allOrphans
        }

        guard !toPrune.isEmpty else {
            throw PruneOrphansError.noOrphans
        }

        if dryRun {
            return PruneOrphansResult(
                pruned: toPrune,
                actor: resolvedActor,
                note: noteValue,
                auditURL: resolvedAuditURL,
                storeURL: resolvedStoreURL,
                dryRun: true
            )
        }

        var events: [IdsStore.AuditEvent] = []
        events.reserveCapacity(toPrune.count)
        for o in toPrune {
            events.append(IdsStore.AuditEvent(
                timestamp: IdsStore.iso8601UTCString(from: now),
                event: "prune-orphan",
                id: o.id,
                oldContent: o.content,
                newContent: "",
                source: "ids.json (orphan)",
                actor: resolvedActor,
                note: noteValue
            ))
        }

        do {
            for event in events {
                try IdsStore.appendAuditEvent(event, to: resolvedAuditURL)
            }
        } catch let err as AcceptDriftError {
            if case .auditWriteFailed(let message) = err {
                throw PruneOrphansError.auditWriteFailed(message: message)
            }
            throw PruneOrphansError.auditWriteFailed(message: err.description)
        } catch let err as PruneOrphansError {
            throw err
        } catch {
            throw PruneOrphansError.auditWriteFailed(message: error.localizedDescription)
        }

        for o in toPrune {
            store.bindings.removeValue(forKey: o.id)
        }
        store.counters = countersBefore
        IdsStore.raiseHighWaterMarks(in: &store)
        for id in liveIDs {
            IdsStore.noteObservedID(id, in: &store)
        }

        do {
            try IdsStore.save(store, to: resolvedStoreURL)
        } catch {
            throw PruneOrphansError.storeWriteFailed(message: error.localizedDescription)
        }

        return PruneOrphansResult(
            pruned: toPrune,
            actor: resolvedActor,
            note: noteValue,
            auditURL: resolvedAuditURL,
            storeURL: resolvedStoreURL,
            dryRun: false
        )
    }

    // MARK: - Prefix resolution

    /// Resolves which ID prefix to use when assigning a new ID to a heading.
    ///
    /// Priority:
    /// 1. Keywords in the heading text itself
    /// 2. Section filename (skeleton `00N-technical-specifications.md`, etc.)
    /// 3. Dominant prefix already used by other owned IDs in the same file (sibling context)
    static func resolvePrefix(for heading: IdsScanner.HeadingInfo, fileContextPrefix: String?) -> String? {
        let normalized = IdsScanner.normalizeHeadingTitle(
            HeadingNumberer.stripOutlinePrefix(from: heading.content)
        )
        if !IdsScanner.structuralSectionTitles.contains(normalized),
           let fromContent = PrefixCatalog.inferFromTitle(heading.content)
        {
            return fromContent
        }
        if let fromFile = PrefixCatalog.inferFromFilename(heading.file.lastPathComponent) {
            return fromFile
        }
        return fileContextPrefix
    }

    /// Most common ID prefix among headings that already own an ID in each file.
    static func dominantPrefixByFile(in headings: [IdsScanner.HeadingInfo]) -> [URL: String] {
        var counts: [URL: [String: Int]] = [:]
        for h in headings {
            guard let id = h.id, let prefix = IdsStore.prefixOf(id: id) else { continue }
            counts[h.file, default: [:]][prefix, default: 0] += 1
        }
        var result: [URL: String] = [:]
        for (file, prefixCounts) in counts {
            if let best = prefixCounts.max(by: { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                let li = PrefixCatalog.index(of: lhs.key) ?? Int.max
                let ri = PrefixCatalog.index(of: rhs.key) ?? Int.max
                return li > ri
            }) {
                result[file] = best.key
            }
        }
        return result
    }

    // MARK: - Drift comparison (#36)

    /// Whether bound vs current heading text counts as content drift under `sensitivity`.
    static func isContentDrift(
        bound: String,
        current: String,
        sensitivity: SpecticusConfig.DriftSensitivity
    ) -> Bool {
        !contentsMatch(bound, current, sensitivity: sensitivity)
    }

    /// Compare two heading content strings according to #36 sensitivity rules.
    static func contentsMatch(
        _ a: String,
        _ b: String,
        sensitivity: SpecticusConfig.DriftSensitivity
    ) -> Bool {
        switch sensitivity {
        case .strict:
            return a == b
        case .contentStrict, .contentStrictPlus:
            return normalizeForDriftComparison(a, sensitivity: sensitivity)
                == normalizeForDriftComparison(b, sensitivity: sensitivity)
        }
    }

    /// Normalizes text for non-strict drift comparison.
    ///
    /// - `contentStrict`: lowercases letters; collapses whitespace runs to a single space
    ///   (whitespace may grow/shrink between tokens but not disappear so tokens merge).
    /// - `contentStrictPlus`: same, then treats punctuation/symbols as whitespace (so they
    ///   may change or vanish without counting as drift).
    static func normalizeForDriftComparison(
        _ text: String,
        sensitivity: SpecticusConfig.DriftSensitivity
    ) -> String {
        switch sensitivity {
        case .strict:
            return text
        case .contentStrict:
            return collapseWhitespace(text.lowercased())
        case .contentStrictPlus:
            let lowered = text.lowercased()
            var scalars: [UnicodeScalar] = []
            scalars.reserveCapacity(lowered.unicodeScalars.count)
            for s in lowered.unicodeScalars {
                if CharacterSet.punctuationCharacters.contains(s)
                    || CharacterSet.symbols.contains(s) {
                    scalars.append(" ")
                } else {
                    scalars.append(s)
                }
            }
            return collapseWhitespace(String(String.UnicodeScalarView(scalars)))
        }
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split { $0.isWhitespace }.joined(separator: " ")
    }

    /// Collect drift findings for lint/build using the project's configured sensitivity.
    static func findContentDrifts(
        headings: [IdsScanner.HeadingInfo],
        store: IdStore,
        sensitivity: SpecticusConfig.DriftSensitivity
    ) -> [DriftFinding] {
        var findings: [DriftFinding] = []
        for h in headings {
            guard let id = h.id, let bound = store.bindings[id] else { continue }
            if isContentDrift(bound: bound, current: h.content, sensitivity: sensitivity) {
                findings.append(DriftFinding(
                    id: id,
                    oldContent: bound,
                    newContent: h.content,
                    file: h.file.lastPathComponent
                ))
            }
        }
        return findings
    }

    /// Inserts a newly assigned ID into an ATX heading line.
    ///
    /// Per issue #34, if the heading already has a hierarchical outline prefix
    /// (e.g. `## 1.2. User Login`), the ID is placed **after** that prefix so the
    /// line becomes `## 1.2. BR1: User Login`. Putting the ID before the outline
    /// would break subsequent scans and pollute content bindings with outline text.
    /// We never invent or modify outline numbers here (disjoint from #4).
    static func addIDPrefix(to line: String, id: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*)(#{1,6})(\s+)(.*)$"#) else { return line }
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return line }

        let indent = ns.substring(with: m.range(at: 1))
        let hashes = ns.substring(with: m.range(at: 2))
        let space = ns.substring(with: m.range(at: 3))
        let rest = ns.substring(with: m.range(at: 4))

        if let outlineRange = rest.range(of: #"^\d+(?:\.\d+)*\.\s+"#, options: .regularExpression) {
            let outline = String(rest[outlineRange])
            let afterOutline = String(rest[outlineRange.upperBound...])
            let newTitle = "\(outline)\(id): \(afterOutline)"
            return "\(indent)\(hashes)\(space)\(newTitle)"
        }

        let newTitle = "\(id): \(rest)"
        return "\(indent)\(hashes)\(space)\(newTitle)"
    }
}
