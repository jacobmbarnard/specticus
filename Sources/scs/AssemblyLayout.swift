import Foundation
import Yams

// MARK: - Assembly layout (#140)

/// How files under a section vertical are ordered (by relative path).
enum AssemblySortPolicy: String, Codable, Equatable, Sendable, CaseIterable {
    case lexical
    case reverseLexical = "reverse_lexical"
    case alphanumeric

    static let `default`: AssemblySortPolicy = .alphanumeric
}

/// One section vertical in the assembly pipeline.
struct AssemblySectionSpec: Codable, Equatable, Sendable {
    var id: String
    /// Lower sorts earlier. When equal, pack/default order breaks ties.
    var order: Int
    var sort: AssemblySortPolicy

    enum CodingKeys: String, CodingKey {
        case id
        case order
        case sort
    }

    init(id: String, order: Int, sort: AssemblySortPolicy = .default) {
        self.id = id
        self.order = order
        self.sort = sort
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        if let raw = try c.decodeIfPresent(String.self, forKey: .sort) {
            switch raw {
            case "lexical": sort = .lexical
            case "reverse_lexical", "reverseLexical": sort = .reverseLexical
            case "alphanumeric": sort = .alphanumeric
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .sort,
                    in: c,
                    debugDescription: "Unknown assembly sort '\(raw)'. Use lexical, reverse_lexical, or alphanumeric."
                )
            }
        } else {
            sort = .default
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(order, forKey: .order)
        try c.encode(sort.rawValue, forKey: .sort)
    }
}

/// Resolved assembly layout: section order + per-section sort (#140).
struct AssemblyLayout: Equatable, Sendable {
    /// Sections sorted by `order`, then by default pack index for stability.
    var sections: [AssemblySectionSpec]

    /// Pack default: `TemplateSections.defaultOrder` with `alphanumeric` sort and spaced orders.
    static let packDefault: AssemblyLayout = {
        let specs = TemplateSections.defaultOrder.enumerated().map { index, id in
            AssemblySectionSpec(id: id, order: index * 10, sort: .alphanumeric)
        }
        return AssemblyLayout(sections: specs)
    }()

    init(sections: [AssemblySectionSpec]) {
        self.sections = Self.sortedSpecs(sections)
    }

    /// Section ids in assembly order.
    var orderedSectionIDs: [String] {
        sections.map(\.id)
    }

    func sortPolicy(forSectionID id: String) -> AssemblySortPolicy {
        sections.first { $0.id == id }?.sort ?? .default
    }

    /// Merge pack/base layout with user overrides (by section id). Unlisted base sections remain.
    /// User-only unknown ids are appended (for forward-compat / custom folders).
    static func merge(base: AssemblyLayout, overrides: [AssemblySectionSpec]) -> AssemblyLayout {
        var byID: [String: AssemblySectionSpec] = [:]
        for spec in base.sections {
            byID[spec.id] = spec
        }
        for over in overrides {
            if var existing = byID[over.id] {
                existing.order = over.order
                existing.sort = over.sort
                byID[over.id] = existing
            } else {
                byID[over.id] = over
            }
        }
        return AssemblyLayout(sections: Array(byID.values))
    }

    private static func sortedSpecs(_ specs: [AssemblySectionSpec]) -> [AssemblySectionSpec] {
        let packIndex: [String: Int] = Dictionary(
            uniqueKeysWithValues: TemplateSections.defaultOrder.enumerated().map { ($1, $0) }
        )
        return specs.sorted { a, b in
            if a.order != b.order { return a.order < b.order }
            let ia = packIndex[a.id] ?? Int.max
            let ib = packIndex[b.id] ?? Int.max
            if ia != ib { return ia < ib }
            return a.id < b.id
        }
    }

    // MARK: Path sorting

    /// Compare relative paths under a section using `policy`.
    static func comparePaths(_ a: String, _ b: String, policy: AssemblySortPolicy) -> Bool {
        switch policy {
        case .lexical:
            return a < b
        case .reverseLexical:
            return a > b
        case .alphanumeric:
            return compareAlphanumeric(a, b)
        }
    }

    /// Natural / alphanumeric compare: numeric runs compared as integers (`9` < `10`).
    static func compareAlphanumeric(_ a: String, _ b: String) -> Bool {
        let ak = alphanumericKey(a)
        let bk = alphanumericKey(b)
        let count = min(ak.count, bk.count)
        for i in 0..<count {
            if ak[i] != bk[i] { return ak[i] < bk[i] }
        }
        if ak.count != bk.count { return ak.count < bk.count }
        return a < b
    }

    private static func alphanumericKey(_ string: String) -> [AlnumChunk] {
        var chunks: [AlnumChunk] = []
        var i = string.startIndex
        while i < string.endIndex {
            if string[i].isNumber {
                var j = i
                while j < string.endIndex, string[j].isNumber { j = string.index(after: j) }
                let digits = String(string[i..<j])
                chunks.append(.number(Int(digits) ?? 0))
                i = j
            } else {
                var j = i
                while j < string.endIndex, !string[j].isNumber { j = string.index(after: j) }
                chunks.append(.text(String(string[i..<j]).lowercased()))
                i = j
            }
        }
        return chunks
    }

    private enum AlnumChunk: Comparable {
        case text(String)
        case number(Int)

        static func < (lhs: AlnumChunk, rhs: AlnumChunk) -> Bool {
            switch (lhs, rhs) {
            case let (.text(a), .text(b)): return a < b
            case let (.number(a), .number(b)): return a < b
            case (.number, .text): return true
            case (.text, .number): return false
            }
        }
    }
}

// MARK: - YAML root for `.specticus/layout.yml`

struct AssemblyLayoutFile: Codable, Equatable, Sendable {
    var sections: [AssemblySectionSpec]

    enum CodingKeys: String, CodingKey {
        case sections
    }

    init(sections: [AssemblySectionSpec]) {
        self.sections = sections
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sections = try c.decodeIfPresent([AssemblySectionSpec].self, forKey: .sections) ?? []
    }

    static func load(from url: URL) throws -> AssemblyLayoutFile {
        let yaml = try String(contentsOf: url, encoding: .utf8)
        return try YAMLDecoder().decode(AssemblyLayoutFile.self, from: yaml)
    }
}

extension AssemblyLayout {
    /// Load pack/user `layout.yml` if present and merge onto `packDefault`.
    static func loadMerged(layoutFileURL: URL?, configOverrides: [AssemblySectionSpec]) -> AssemblyLayout {
        var base = AssemblyLayout.packDefault
        if let url = layoutFileURL, FileManager.default.fileExists(atPath: url.path) {
            if let file = try? AssemblyLayoutFile.load(from: url), !file.sections.isEmpty {
                base = merge(base: base, overrides: file.sections)
            }
        }
        if !configOverrides.isEmpty {
            base = merge(base: base, overrides: configOverrides)
        }
        return base
    }

    /// Lint helpers: duplicate orders among listed sections (same order value twice).
    var duplicateOrders: [Int] {
        var counts: [Int: Int] = [:]
        for s in sections { counts[s.order, default: 0] += 1 }
        return counts.filter { $0.value > 1 }.map(\.key).sorted()
    }

    /// Section ids not in the default pack map (custom / typo).
    var unknownSectionIDs: [String] {
        sections.map(\.id).filter { !TemplateSections.defaultOrderSet.contains($0) }.sorted()
    }
}
