import Foundation

// MARK: - Traceability IDs facade (internals #20)
//
// Scanning, the store, assignment, and user-facing text live in IdsScanner,
// IdsStore, IdsAssigner, and IdsReporter. This type only forwards so existing
// call sites stay stable for one PR.

enum IdsManager {
    /// Known ID prefixes — sourced from `PrefixCatalog` (#19).
    static var knownPrefixes: [String] { PrefixCatalog.prefixes }

    typealias IdStore = scs.IdStore
    typealias AuditEvent = IdsStore.AuditEvent
    typealias OrphanFinding = IdsStore.OrphanFinding
    typealias HeadingInfo = IdsScanner.HeadingInfo
    typealias HeadingSkipReason = IdsScanner.HeadingSkipReason
    typealias HeadingObservation = IdsScanner.HeadingObservation
    typealias HeadingScan = IdsScanner.HeadingScan
    typealias MarkdownHeadingFinding = IdsScanner.MarkdownHeadingFinding
    typealias DriftFinding = IdsAssigner.DriftFinding
    typealias CollaborationHazards = IdsAssigner.CollaborationHazards
    typealias BuildAssignMode = IdsAssigner.BuildAssignMode
    typealias AssignOptions = IdsAssigner.AssignOptions
    typealias AssignAbort = IdsAssigner.AssignAbort
    typealias LifecycleReport = IdsAssigner.LifecycleReport
    typealias AcceptDriftResult = IdsAssigner.AcceptDriftResult
    typealias AcceptDriftError = IdsAssigner.AcceptDriftError
    typealias PruneOrphansResult = IdsAssigner.PruneOrphansResult
    typealias PruneOrphansError = IdsAssigner.PruneOrphansError
    typealias CollaborationReportStyle = IdsReporter.CollaborationReportStyle

    static func loadStore(from url: URL) -> IdStore {
        let loaded = IdsStore.load(from: url)
        if let fileName = loaded.fileName, let description = loaded.errorDescription {
            IdsReporter.printStoreLoadWarning(
                "⚠️  Could not read \(fileName), starting fresh: \(description)"
            )
        }
        return loaded.store
    }

    static func saveStore(_ store: IdStore, to url: URL) throws {
        try IdsStore.save(store, to: url)
    }

    static func collectHeadings(project: SpecticusProject) throws -> [HeadingInfo] {
        try IdsScanner.collectHeadings(project: project)
    }

    static func scanHeadings(project: SpecticusProject) throws -> HeadingScan {
        try IdsScanner.scanHeadings(project: project)
    }

    static func collectCollaborationHazards(project: SpecticusProject) throws -> CollaborationHazards {
        try IdsAssigner.collectCollaborationHazards(project: project)
    }

    static func collectCollaborationHazards(
        project: SpecticusProject,
        headings: [HeadingInfo]
    ) -> CollaborationHazards {
        IdsAssigner.collectCollaborationHazards(project: project, headings: headings)
    }

    static func printDuplicateIDReport(
        hazards: CollaborationHazards,
        style: CollaborationReportStyle = .blocking
    ) {
        IdsReporter.printDuplicateIDReport(hazards: hazards, style: style)
    }

    static func resolveBuildAssignMode(autoAssign: Bool, assignIdsFlag: Bool) -> BuildAssignMode {
        IdsAssigner.resolveBuildAssignMode(autoAssign: autoAssign, assignIdsFlag: assignIdsFlag)
    }

    static func assignIDs(project: SpecticusProject, dryRun: Bool) throws {
        try assignIDs(project: project, options: AssignOptions(dryRun: dryRun, assumeYes: true))
    }

    static func assignIDs(project: SpecticusProject, options: AssignOptions) throws {
        try IdsReporter.performAssign(project: project, options: options)
    }

    static func isInteractiveTerminal() -> Bool {
        IdsAssigner.isInteractiveTerminal()
    }

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
        let result = try IdsAssigner.acceptDrift(
            project: project,
            id: rawID,
            note: note,
            actor: actor,
            auditURL: auditURL,
            storeURL: storeURL,
            now: now
        )
        IdsReporter.printAcceptDrift(result)
        return result
    }

    static func appendAuditEvent(_ event: AuditEvent, to url: URL) throws {
        try IdsStore.appendAuditEvent(event, to: url)
    }

    static func loadAuditEvents(from url: URL) throws -> [AuditEvent] {
        try IdsStore.loadAuditEvents(from: url)
    }

    static func findOrphans(store: IdStore, liveIDs: Set<String>) -> [OrphanFinding] {
        IdsStore.findOrphans(store: store, liveIDs: liveIDs)
    }

    static func liveIDSet(from headings: [HeadingInfo]) -> Set<String> {
        IdsScanner.liveIDSet(from: headings)
    }

    static func lifecycleReport(project: SpecticusProject) throws -> LifecycleReport {
        try IdsAssigner.lifecycleReport(project: project)
    }

    static func printStatus(project: SpecticusProject) throws {
        try IdsReporter.printStatus(project: project)
    }

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
        let result = try IdsAssigner.pruneOrphans(
            project: project,
            onlyID: onlyID,
            dryRun: dryRun,
            note: note,
            actor: actor,
            auditURL: auditURL,
            storeURL: storeURL,
            now: now
        )
        IdsReporter.printPruneOrphans(result)
        return result
    }

    static func diagnoseUnrecognizedIDForm(in title: String) -> String? {
        IdsScanner.diagnoseUnrecognizedIDForm(in: title)
    }

    static func parseOwningID(from title: String) -> (id: String, content: String)? {
        IdsScanner.parseOwningID(from: title)
    }

    static func isStructuralSectionTitle(_ title: String, file: URL) -> Bool {
        IdsScanner.isStructuralSectionTitle(title, file: file)
    }

    static func humanizePathComponent(_ name: String) -> String {
        IdsScanner.humanizePathComponent(name)
    }

    static func normalizeHeadingTitle(_ text: String) -> String {
        IdsScanner.normalizeHeadingTitle(text)
    }

    static func isContentDrift(
        bound: String,
        current: String,
        sensitivity: SpecticusConfig.DriftSensitivity
    ) -> Bool {
        IdsAssigner.isContentDrift(bound: bound, current: current, sensitivity: sensitivity)
    }

    static func contentsMatch(
        _ a: String,
        _ b: String,
        sensitivity: SpecticusConfig.DriftSensitivity
    ) -> Bool {
        IdsAssigner.contentsMatch(a, b, sensitivity: sensitivity)
    }

    static func normalizeForDriftComparison(
        _ text: String,
        sensitivity: SpecticusConfig.DriftSensitivity
    ) -> String {
        IdsAssigner.normalizeForDriftComparison(text, sensitivity: sensitivity)
    }

    static func headingContainsDisallowedMarkdown(_ title: String) -> Bool {
        IdsScanner.headingContainsDisallowedMarkdown(title)
    }

    static func findContentDrifts(
        headings: [HeadingInfo],
        store: IdStore,
        sensitivity: SpecticusConfig.DriftSensitivity
    ) -> [DriftFinding] {
        IdsAssigner.findContentDrifts(headings: headings, store: store, sensitivity: sensitivity)
    }

    static func findMarkdownFormattedHeadings(in headings: [HeadingInfo]) -> [MarkdownHeadingFinding] {
        IdsScanner.findMarkdownFormattedHeadings(in: headings)
    }

    static func highWaterMark(for prefix: String, store: IdStore) -> Int {
        IdsStore.highWaterMark(for: prefix, store: store)
    }

    static func allocateNextID(prefix: String, store: inout IdStore) -> String {
        IdsStore.allocateNextID(prefix: prefix, store: &store)
    }
}
