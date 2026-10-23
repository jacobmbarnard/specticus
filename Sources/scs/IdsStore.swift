import Foundation

// MARK: - Traceability ID store (internals #20)
//
// Load/save `.specticus/ids.json` and append-only `.specticus/ids-audit.jsonl`.
// Counters, bindings, and orphans live here. No printing.

/// On-disk snapshot of counters and content bindings (`ids.json`).
///
/// Counter policy (#33): monotonic per-prefix high-water mark; never reuse numbers.
/// New IDs always use (max seen for that prefix) + 1. Gaps left by deleted or retired
/// requirements are intentional — orphaned entries still reserve their numbers.
struct IdStore: Codable, Equatable, Sendable {
    var version: Int = 1
    /// Per-prefix high-water mark (largest number ever issued or observed). Never decreases (#33).
    var counters: [String: Int] = [:]   // e.g. "BR": 3
    /// ID → descriptive content. Orphan bindings (ID not in Markdown) still reserve numbers (#33).
    var bindings: [String: String] = [:] // e.g. "BR1": "User Login"
}

enum IdsStore {
    /// Result of reading `ids.json`. Decode failure yields an empty store plus the error.
    struct LoadResult: Sendable {
        var store: IdStore
        /// Set when the file existed but could not be decoded.
        var fileName: String?
        var errorDescription: String?
    }

    /// Structured audit event for deliberate ID rebinds / prunes. Appended as one JSON
    /// line to `.specticus/ids-audit.jsonl` (never rewritten in place).
    struct AuditEvent: Codable, Equatable, Sendable {
        var timestamp: String
        var event: String
        var id: String
        var oldContent: String
        var newContent: String
        var source: String
        var actor: String
        var note: String?

        enum CodingKeys: String, CodingKey {
            case timestamp
            case event
            case id
            case oldContent = "old_content"
            case newContent = "new_content"
            case source
            case actor
            case note
        }
    }

    /// An orphan binding: present in `ids.json` but not claimed by any eligible Markdown heading.
    struct OrphanFinding: Equatable, Sendable {
        let id: String
        let content: String
    }

    static func load(from url: URL) -> LoadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return LoadResult(store: IdStore(), fileName: nil, errorDescription: nil)
        }
        do {
            let data = try Data(contentsOf: url)
            let store = try JSONDecoder().decode(IdStore.self, from: data)
            return LoadResult(store: store, fileName: nil, errorDescription: nil)
        } catch {
            return LoadResult(
                store: IdStore(),
                fileName: url.lastPathComponent,
                errorDescription: "\(error)"
            )
        }
    }

    static func save(_ store: IdStore, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        try data.write(to: url, options: .atomic)
    }

    /// Appends one JSON object as a single line to the audit log (creates parent dir / file as needed).
    static func appendAuditEvent(_ event: AuditEvent, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Refuse to clobber a directory or other non-file at the audit path.
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            throw IdsAssigner.AcceptDriftError.auditWriteFailed(
                message: "\(url.lastPathComponent) exists and is a directory"
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event)
        guard var line = String(data: data, encoding: .utf8) else {
            throw IdsAssigner.AcceptDriftError.auditWriteFailed(message: "could not encode audit event as UTF-8")
        }
        line.append("\n")
        guard let lineData = line.data(using: .utf8) else {
            throw IdsAssigner.AcceptDriftError.auditWriteFailed(message: "could not encode audit line as UTF-8")
        }

        // Read-modify-write keeps us off newer FileHandle APIs that require a higher
        // macOS deployment target than the package declares (CI builds on macOS).
        // Audit logs stay small; atomic rewrite is appropriate and portable.
        if fm.fileExists(atPath: url.path) {
            var combined = try Data(contentsOf: url)
            combined.append(lineData)
            try combined.write(to: url, options: .atomic)
        } else {
            try lineData.write(to: url, options: .atomic)
        }
    }

    /// Loads all audit events from a JSONL file (skips blank lines). Used by tests and tooling.
    static func loadAuditEvents(from url: URL) throws -> [AuditEvent] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        var events: [AuditEvent] = []
        for (idx, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            do {
                let data = Data(trimmed.utf8)
                events.append(try decoder.decode(AuditEvent.self, from: data))
            } catch {
                throw IdsAssigner.AcceptDriftError.auditWriteFailed(
                    message: "malformed audit log line \(idx + 1): \(error.localizedDescription)"
                )
            }
        }
        return events
    }

    static func currentActor() -> String {
        if let user = ProcessInfo.processInfo.environment["USER"], !user.isEmpty {
            return user
        }
        if let logname = ProcessInfo.processInfo.environment["LOGNAME"], !logname.isEmpty {
            return logname
        }
        return "unknown"
    }

    static func iso8601UTCString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    /// IDs present in store bindings but not among `liveIDs` (sorted by ID for stable output).
    static func findOrphans(store: IdStore, liveIDs: Set<String>) -> [OrphanFinding] {
        store.bindings
            .filter { !liveIDs.contains($0.key) }
            .map { OrphanFinding(id: $0.key, content: $0.value) }
            .sorted { lhs, rhs in
                // Prefer natural ID order: prefix then number.
                let lp = prefixOf(id: lhs.id) ?? lhs.id
                let rp = prefixOf(id: rhs.id) ?? rhs.id
                if lp != rp {
                    let li = PrefixCatalog.index(of: lp) ?? Int.max
                    let ri = PrefixCatalog.index(of: rp) ?? Int.max
                    if li != ri { return li < ri }
                    return lp < rp
                }
                return numberOf(id: lhs.id) < numberOf(id: rhs.id)
            }
    }

    // MARK: - Counter policy (#33)

    /// Policy: **monotonic per-prefix high-water mark; never reuse.**
    ///
    /// When allocating a new ID for prefix `P`:
    /// 1. Compute `high = max(store.counters[P], max number among bindings with prefix P)`.
    /// 2. Issue `P(high + 1)` and set `counters[P] = high + 1`.
    ///
    /// Consequences (intentional):
    /// - Deleting a heading leaves a **gap** (e.g. BR1, BR3 present → next is BR4, not BR2).
    /// - Orphan bindings in `ids.json` (ID removed from Markdown but still recorded) **reserve**
    ///   their numbers so historical references stay unambiguous.
    /// - Counters never decrease; a stale high counter is trusted over gap-filling.
    /// - Prefixes are independent (BR and TS counters do not interact).
    ///
    /// Non-goals: lowest-unused reuse, renumbering/compaction, configurable reuse modes.
    static func highWaterMark(for prefix: String, store: IdStore) -> Int {
        var high = store.counters[prefix] ?? 0
        for id in store.bindings.keys {
            guard let p = prefixOf(id: id), p == prefix else { continue }
            high = max(high, numberOf(id: id))
        }
        return high
    }

    /// Raises `store.counters` so each known prefix is at least the max number in bindings.
    static func raiseHighWaterMarks(in store: inout IdStore) {
        var raised: [String: Int] = store.counters
        for id in store.bindings.keys {
            guard let prefix = prefixOf(id: id) else { continue }
            let num = numberOf(id: id)
            raised[prefix] = max(raised[prefix] ?? 0, num)
        }
        store.counters = raised
    }

    /// Records an observed ID into the high-water mark (does not create bindings).
    static func noteObservedID(_ id: String, in store: inout IdStore) {
        guard let prefix = prefixOf(id: id) else { return }
        let num = numberOf(id: id)
        store.counters[prefix] = max(store.counters[prefix] ?? 0, num)
    }

    /// Allocates the next ID for `prefix` using the #33 max+1 policy and advances the counter.
    static func allocateNextID(prefix: String, store: inout IdStore) -> String {
        let next = highWaterMark(for: prefix, store: store) + 1
        store.counters[prefix] = next
        return "\(prefix)\(next)"
    }

    static func prefixOf(id: String) -> String? {
        // Longest prefix first so e.g. BDR wins over BR if both ever matched.
        let ordered = PrefixCatalog.prefixes.sorted { $0.count > $1.count }
        for p in ordered where id.hasPrefix(p) {
            // Require that the remainder starts with a digit (BR1, not BROKEN)
            let rest = id.dropFirst(p.count)
            if let first = rest.first, first.isNumber {
                return p
            }
        }
        return nil
    }

    static func numberOf(id: String) -> Int {
        let digits = id.drop { !$0.isNumber }
        return Int(digits) ?? 0
    }
}
