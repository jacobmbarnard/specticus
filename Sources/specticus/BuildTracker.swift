import Foundation
import Yams

// MARK: - Build number tracking (implements #8)

/// Persistent build counter stored in `.specticus/build-number.yml`.
/// Survives `clean` and is intended to be source-control friendly.
struct BuildRecord: Codable, Equatable, Sendable {
    /// Monotonic build counter (starts at 1 after first successful increment).
    var number: Int
    /// ISO-8601 timestamp of the last build that wrote this record.
    var lastBuilt: String

    enum CodingKeys: String, CodingKey {
        case number
        case lastBuilt = "last_built"
    }

    init(number: Int = 0, lastBuilt: String = "") {
        self.number = number
        self.lastBuilt = lastBuilt
    }

    /// Human-readable line for HTML chrome, e.g. "Generated on 2026-07-09 21:08 UTC · build 3".
    var displayLine: String {
        let when = Self.prettyTimestamp(fromISO: lastBuilt) ?? lastBuilt
        if when.isEmpty {
            return "Build \(number)"
        }
        return "Generated on \(when) · build \(number)"
    }

    private static func prettyTimestamp(fromISO iso: String) -> String? {
        guard !iso.isEmpty else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = isoFormatter.date(from: iso)
        if date == nil {
            isoFormatter.formatOptions = [.withInternetDateTime]
            date = isoFormatter.date(from: iso)
        }
        guard let date else { return iso }

        let display = DateFormatter()
        display.locale = Locale(identifier: "en_US_POSIX")
        display.timeZone = TimeZone(secondsFromGMT: 0)
        display.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return display.string(from: date)
    }
}

enum BuildTracker {
    /// Read current record without mutating. Returns nil if the file is missing.
    static func load(from url: URL) throws -> BuildRecord? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let yaml = try String(contentsOf: url, encoding: .utf8)
        return try YAMLDecoder().decode(BuildRecord.self, from: yaml)
    }

    /// Increment the build number, stamp the current time, persist, and return the new record.
    /// Creates `.specticus/` (and the file) as needed.
    static func incrementAndSave(at url: URL, now: Date = Date()) throws -> BuildRecord {
        let fm = FileManager.default
        var record = (try? load(from: url)) ?? BuildRecord()
        record.number += 1

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        record.lastBuilt = iso.string(from: now)

        try fm.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let yaml = try YAMLEncoder().encode(record)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        return record
    }
}
