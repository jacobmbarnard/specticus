import Testing
import Foundation
@testable import scs

// MARK: - ID store (internals #20 / store)

// MARK: - Counter strategy max+1 never reuse (#33)

@Test func counterHighWaterMarkUsesBindingsAndCounters() {
    var store = IdsManager.IdStore()
    store.counters["BR"] = 2
    store.bindings["BR1"] = "One"
    store.bindings["BR5"] = "Orphan five" // higher than counter
    store.bindings["TS3"] = "Other prefix"

    #expect(IdsManager.highWaterMark(for: "BR", store: store) == 5)
    #expect(IdsManager.highWaterMark(for: "TS", store: store) == 3)
    #expect(IdsManager.highWaterMark(for: "UC", store: store) == 0)

    let nextBR = IdsManager.allocateNextID(prefix: "BR", store: &store)
    #expect(nextBR == "BR6")
    #expect(store.counters["BR"] == 6)

    let nextTS = IdsManager.allocateNextID(prefix: "TS", store: &store)
    #expect(nextTS == "TS4")
    #expect(store.counters["TS"] == 4)
    // BR counter untouched by TS allocation
    #expect(store.counters["BR"] == 6)
}

@Test func counterNeverReusesGapInLiveMarkdown() throws {
    // BR1 and BR3 present; BR2 missing → new IDs must be > 3, never BR2.
    // (H1 may also receive a BR via sibling context under #32; policy is still max+1.)
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-gap-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-section.md")
    try """
# Overview
## BR1: First
## BR3: Third
## Offline Mode requirement
""".write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    try IdsManager.assignIDs(project: project, dryRun: false)

    let rewritten = try String(contentsOf: mdURL, encoding: .utf8)
    let lines = rewritten.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #expect(lines.contains("## BR1: First"))
    #expect(lines.contains("## BR3: Third"))
    #expect(lines.contains { $0.hasPrefix("## BR") && $0.contains("Offline Mode requirement") })
    // Gap BR2 must never be filled
    #expect(!rewritten.contains("BR2:"))
    let offlineNum = lines
        .first { $0.contains("Offline Mode requirement") }
        .flatMap { line -> Int? in
            guard let r = line.range(of: #"BR(\d+)"#, options: .regularExpression) else { return nil }
            return Int(line[r].dropFirst(2))
        }
    #expect(offlineNum != nil)
    #expect((offlineNum ?? 0) >= 4)
}

@Test func counterOrphanBindingReservesNumber() throws {
    // Orphan BR2 in ids.json (no longer in Markdown) must not be reissued.
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-orphan-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-section.md")
    try """
# Overview
## BR1: Still Live
## New Requirement
""".write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)
    try """
    {
      "version": 1,
      "counters": { "BR": 2 },
      "bindings": {
        "BR1": "Still Live",
        "BR2": "Deleted requirement kept for history"
      }
    }
    """.write(to: specticusDir.appendingPathComponent("ids.json"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    try IdsManager.assignIDs(project: project, dryRun: false)

    let rewritten = try String(contentsOf: mdURL, encoding: .utf8)
    let lines = rewritten.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #expect(lines.contains { $0.contains("New Requirement") && $0.contains("BR") })
    #expect(!rewritten.contains("BR2: New Requirement"))
    #expect(!rewritten.contains("## BR2:"))

    let store = IdsManager.loadStore(from: project.idsURL)
    #expect(store.bindings["BR2"] == "Deleted requirement kept for history")
    #expect(store.counters["BR"] ?? 0 >= 3)
    // The new requirement binding must use a number > 2
    let newBinding = store.bindings.first { $0.value == "New Requirement" }
    #expect(newBinding != nil)
    #expect(newBinding?.key != "BR2")
    if let key = newBinding?.key, let num = Int(key.dropFirst(2)) {
        #expect(num >= 3)
    }
}

@Test func counterTrustsHighStaleCounterOverGaps() throws {
    // counters.BR = 10 even if only BR1 is live → new IDs are > 10, never fill 2…9.
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-stale-counter-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-section.md")
    try """
# Overview
## BR1: Only Live
## Another requirement item
""".write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)
    try """
    {
      "version": 1,
      "counters": { "BR": 10 },
      "bindings": { "BR1": "Only Live" }
    }
    """.write(to: specticusDir.appendingPathComponent("ids.json"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    try IdsManager.assignIDs(project: project, dryRun: false)

    let rewritten = try String(contentsOf: mdURL, encoding: .utf8)
    let lines = rewritten.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #expect(lines.contains { $0.hasPrefix("## BR") && $0.contains("Another requirement item") })
    #expect(!rewritten.contains("## BR2:"))
    let itemNum = lines
        .first { $0.contains("Another requirement item") }
        .flatMap { line -> Int? in
            guard let r = line.range(of: #"BR(\d+)"#, options: .regularExpression) else { return nil }
            return Int(line[r].dropFirst(2))
        }
    #expect((itemNum ?? 0) >= 11)
}

@Test func counterPrefixesAreIndependent() throws {
    var store = IdsManager.IdStore()
    store.bindings["BR3"] = "b"
    store.bindings["TS1"] = "t"
    #expect(IdsManager.allocateNextID(prefix: "BR", store: &store) == "BR4")
    #expect(IdsManager.allocateNextID(prefix: "TS", store: &store) == "TS2")
    #expect(IdsManager.allocateNextID(prefix: "UC", store: &store) == "UC1")
}

// MARK: - ids.json lifecycle (#37)

/// Fixture for lifecycle tests: live BR1 + orphan BR2 by default.
private func makeLifecycleFixture(
    markdownBody: String = """
    # Overview
    ## BR1: Still Live
    """,
    bindingsJSON: String = """
    {
      "version": 1,
      "counters": { "BR": 2 },
      "bindings": {
        "BR1": "Still Live",
        "BR2": "Deleted requirement"
      }
    }
    """,
    configYAML: String = """
    version: 1
    ids:
      drift_sensitivity: strict
    """,
    writeStore: Bool = true
) throws -> (tmp: URL, mdURL: URL, project: SpecticusProject) {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-lifecycle-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)

    let mdURL = tmp.appendingPathComponent("007-business-requirements.md")
    try markdownBody.write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try configYAML.write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)
    if writeStore {
        try bindingsJSON.write(to: specticusDir.appendingPathComponent("ids.json"), atomically: true, encoding: .utf8)
    }

    let project = try SpecticusProject.load(from: tmp.path)
    return (tmp, mdURL, project)
}

@Test func lifecycleFindOrphansDetectsStoreOnlyBindings() throws {
    let fm = FileManager.default
    let (tmp, _, project) = try makeLifecycleFixture()
    defer { try? fm.removeItem(at: tmp) }

    let headings = try IdsManager.collectHeadings(project: project)
    let store = IdsManager.loadStore(from: project.idsURL)
    let orphans = IdsManager.findOrphans(store: store, liveIDs: IdsManager.liveIDSet(from: headings))

    #expect(orphans.count == 1)
    #expect(orphans[0].id == "BR2")
    #expect(orphans[0].content == "Deleted requirement")
}

@Test func lifecycleReportSurfacesOrphansDriftAndLive() throws {
    let fm = FileManager.default
    let (tmp, _, project) = try makeLifecycleFixture(
        markdownBody: """
        # Overview
        ## BR1: Renamed Live
        """,
        bindingsJSON: """
        {
          "version": 1,
          "counters": { "BR": 2 },
          "bindings": {
            "BR1": "Still Live",
            "BR2": "Deleted requirement"
          }
        }
        """
    )
    defer { try? fm.removeItem(at: tmp) }

    let report = try IdsManager.lifecycleReport(project: project)
    #expect(report.storeExists)
    #expect(report.liveIDs == ["BR1"])
    #expect(report.orphans.map(\.id) == ["BR2"])
    #expect(report.drifts.count == 1)
    #expect(report.drifts[0].id == "BR1")
    #expect(report.bindingCount == 2)
    #expect((report.counters["BR"] ?? 0) >= 2)
}

@Test func lifecycleMissingStoreReportedAndRecoveredByAssign() throws {
    let fm = FileManager.default
    let (tmp, _, project) = try makeLifecycleFixture(
        markdownBody: """
        # Overview
        ## BR1: User Login
        ## BR3: Offline Mode
        """,
        writeStore: false
    )
    defer { try? fm.removeItem(at: tmp) }

    #expect(!fm.fileExists(atPath: project.idsURL.path))

    let reportBefore = try IdsManager.lifecycleReport(project: project)
    #expect(!reportBefore.storeExists)
    #expect(reportBefore.liveIDs == ["BR1", "BR3"])
    #expect(reportBefore.unboundLiveIDs == ["BR1", "BR3"])
    #expect(reportBefore.orphans.isEmpty)

    // Recovery path: assign bootstraps bindings + counters from Markdown
    try IdsManager.assignIDs(project: project, dryRun: false)

    #expect(fm.fileExists(atPath: project.idsURL.path))
    let store = IdsManager.loadStore(from: project.idsURL)
    #expect(store.bindings["BR1"] == "User Login")
    #expect(store.bindings["BR3"] == "Offline Mode")
    // Gap BR2 is intentional — high-water from live IDs is 3
    #expect((store.counters["BR"] ?? 0) >= 3)
    #expect(store.bindings["BR2"] == nil)

    let reportAfter = try IdsManager.lifecycleReport(project: project)
    #expect(reportAfter.storeExists)
    #expect(reportAfter.unboundLiveIDs.isEmpty)
    #expect(reportAfter.orphans.isEmpty)
}

@Test func lifecyclePruneOrphansRemovesBindingKeepsCounter() throws {
    let fm = FileManager.default
    let (tmp, mdURL, project) = try makeLifecycleFixture()
    defer { try? fm.removeItem(at: tmp) }

    let mdBefore = try String(contentsOf: mdURL, encoding: .utf8)
    let fixedNow = Date(timeIntervalSince1970: 1_700_000_100)

    let result = try IdsManager.pruneOrphans(
        project: project,
        dryRun: false,
        note: "retired under CR-99",
        actor: "tester",
        now: fixedNow
    )

    #expect(result.dryRun == false)
    #expect(result.pruned.count == 1)
    #expect(result.pruned[0].id == "BR2")
    #expect(result.note == "retired under CR-99")

    let storeAfter = IdsManager.loadStore(from: project.idsURL)
    #expect(storeAfter.bindings["BR2"] == nil)
    #expect(storeAfter.bindings["BR1"] == "Still Live")
    // Counter must not drop below the pruned high-water (was 2)
    #expect((storeAfter.counters["BR"] ?? 0) >= 2)

    // Markdown untouched
    let mdAfter = try String(contentsOf: mdURL, encoding: .utf8)
    #expect(mdAfter == mdBefore)

    let events = try IdsManager.loadAuditEvents(from: project.idsAuditURL)
    #expect(events.count == 1)
    #expect(events[0].event == "prune-orphan")
    #expect(events[0].id == "BR2")
    #expect(events[0].oldContent == "Deleted requirement")
    #expect(events[0].newContent == "")
    #expect(events[0].actor == "tester")
    #expect(events[0].note == "retired under CR-99")

    // Pruned number must not be reused
    try """
    # Overview
    ## BR1: Still Live
    ## New Requirement
    """.write(to: mdURL, atomically: true, encoding: .utf8)

    try IdsManager.assignIDs(project: project, dryRun: false)
    let storeAssigned = IdsManager.loadStore(from: project.idsURL)
    let newBinding = storeAssigned.bindings.first { $0.value == "New Requirement" }
    #expect(newBinding != nil)
    #expect(newBinding?.key != "BR2")
    if let key = newBinding?.key, let num = Int(key.dropFirst(2)) {
        #expect(num >= 3)
    }
}

@Test func lifecyclePruneOrphansDryRunDoesNotWrite() throws {
    let fm = FileManager.default
    let (tmp, _, project) = try makeLifecycleFixture()
    defer { try? fm.removeItem(at: tmp) }

    let storeBefore = IdsManager.loadStore(from: project.idsURL)
    let result = try IdsManager.pruneOrphans(project: project, dryRun: true, actor: "tester")
    #expect(result.dryRun)
    #expect(result.pruned.map(\.id) == ["BR2"])

    let storeAfter = IdsManager.loadStore(from: project.idsURL)
    #expect(storeAfter == storeBefore)
    #expect(!fm.fileExists(atPath: project.idsAuditURL.path))
}

@Test func lifecyclePruneSingleIDOnly() throws {
    let fm = FileManager.default
    let (tmp, _, project) = try makeLifecycleFixture(
        markdownBody: """
        # Overview
        ## BR1: Live One
        """,
        bindingsJSON: """
        {
          "version": 1,
          "counters": { "BR": 3 },
          "bindings": {
            "BR1": "Live One",
            "BR2": "Orphan Two",
            "BR3": "Orphan Three"
          }
        }
        """
    )
    defer { try? fm.removeItem(at: tmp) }

    _ = try IdsManager.pruneOrphans(project: project, onlyID: "BR2", actor: "tester")

    let storeAfter = IdsManager.loadStore(from: project.idsURL)
    #expect(storeAfter.bindings["BR2"] == nil)
    #expect(storeAfter.bindings["BR3"] == "Orphan Three")
    #expect(storeAfter.bindings["BR1"] == "Live One")
    #expect((storeAfter.counters["BR"] ?? 0) >= 3)

    let events = try IdsManager.loadAuditEvents(from: project.idsAuditURL)
    #expect(events.count == 1)
    #expect(events[0].id == "BR2")
}

@Test func lifecyclePruneRejectsLiveID() throws {
    let fm = FileManager.default
    let (tmp, _, project) = try makeLifecycleFixture()
    defer { try? fm.removeItem(at: tmp) }

    var threw = false
    do {
        _ = try IdsManager.pruneOrphans(project: project, onlyID: "BR1", actor: "tester")
    } catch let error as IdsManager.PruneOrphansError {
        threw = true
        guard case .idNotOrphan(let id, _) = error else {
            Issue.record("Expected idNotOrphan, got \(error)")
            return
        }
        #expect(id == "BR1")
    }
    #expect(threw)

    let storeAfter = IdsManager.loadStore(from: project.idsURL)
    #expect(storeAfter.bindings["BR1"] == "Still Live")
    #expect(storeAfter.bindings["BR2"] == "Deleted requirement")
    #expect(!fm.fileExists(atPath: project.idsAuditURL.path))
}

@Test func lifecyclePruneNoOrphansErrors() throws {
    let fm = FileManager.default
    let (tmp, _, project) = try makeLifecycleFixture(
        markdownBody: """
        # Overview
        ## BR1: Still Live
        """,
        bindingsJSON: """
        {
          "version": 1,
          "counters": { "BR": 1 },
          "bindings": { "BR1": "Still Live" }
        }
        """
    )
    defer { try? fm.removeItem(at: tmp) }

    var threw = false
    do {
        _ = try IdsManager.pruneOrphans(project: project, actor: "tester")
    } catch let error as IdsManager.PruneOrphansError {
        threw = true
        guard case .noOrphans = error else {
            Issue.record("Expected noOrphans, got \(error)")
            return
        }
    }
    #expect(threw)
}

@Test func lifecyclePruneAuditFailureDoesNotUpdateStore() throws {
    let fm = FileManager.default
    let (tmp, _, project) = try makeLifecycleFixture()
    defer { try? fm.removeItem(at: tmp) }

    try fm.createDirectory(at: project.idsAuditURL, withIntermediateDirectories: true)
    let storeBefore = IdsManager.loadStore(from: project.idsURL)

    var threw = false
    do {
        _ = try IdsManager.pruneOrphans(project: project, actor: "tester")
    } catch let error as IdsManager.PruneOrphansError {
        threw = true
        guard case .auditWriteFailed = error else {
            Issue.record("Expected auditWriteFailed, got \(error)")
            return
        }
    }
    #expect(threw)

    let storeAfter = IdsManager.loadStore(from: project.idsURL)
    #expect(storeAfter == storeBefore)
    #expect(storeAfter.bindings["BR2"] == "Deleted requirement")
}

@Test func lifecycleAssignDoesNotDropOrphans() throws {
    let fm = FileManager.default
    let (tmp, _, project) = try makeLifecycleFixture()
    defer { try? fm.removeItem(at: tmp) }

    try IdsManager.assignIDs(project: project, dryRun: false)

    let store = IdsManager.loadStore(from: project.idsURL)
    #expect(store.bindings["BR2"] == "Deleted requirement")
    #expect(store.bindings["BR1"] == "Still Live")
    #expect((store.counters["BR"] ?? 0) >= 2)
}

@Test func lifecycleUnboundLiveIDsBoundByAssign() throws {
    // Markdown has BR5; store only knows BR1 — assign should bind BR5 without reusing.
    let fm = FileManager.default
    let (tmp, _, project) = try makeLifecycleFixture(
        markdownBody: """
        # Overview
        ## BR1: Known
        ## BR5: Manual ID
        """,
        bindingsJSON: """
        {
          "version": 1,
          "counters": { "BR": 1 },
          "bindings": { "BR1": "Known" }
        }
        """
    )
    defer { try? fm.removeItem(at: tmp) }

    let reportBefore = try IdsManager.lifecycleReport(project: project)
    #expect(reportBefore.unboundLiveIDs == ["BR5"])

    try IdsManager.assignIDs(project: project, dryRun: false)

    let store = IdsManager.loadStore(from: project.idsURL)
    #expect(store.bindings["BR5"] == "Manual ID")
    #expect((store.counters["BR"] ?? 0) >= 5)
}
