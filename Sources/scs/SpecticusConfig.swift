import Foundation
import Yams

// MARK: - Configuration model (implements #7)

/// User-facing project configuration loaded from `.specticus/config.yml`.
/// Missing optional fields fall back to sensible defaults so partial configs work.
struct SpecticusConfig: Codable, Equatable, Sendable {
    var version: Int
    var project: ProjectSection
    var build: BuildSection
    var decisionRecords: DecisionRecordsSection
    var ids: IdsSection
    /// Optional assembly layout overrides (#140). Merged onto pack defaults / layout.yml.
    var assembly: AssemblyConfigSection

    enum CodingKeys: String, CodingKey {
        case version
        case project
        case build
        case decisionRecords = "decision_records"
        case ids
        case assembly
    }

    init(
        version: Int = 1,
        project: ProjectSection = ProjectSection(),
        build: BuildSection = BuildSection(),
        decisionRecords: DecisionRecordsSection = DecisionRecordsSection(),
        ids: IdsSection = IdsSection(),
        assembly: AssemblyConfigSection = AssemblyConfigSection()
    ) {
        self.version = version
        self.project = project
        self.build = build
        self.decisionRecords = decisionRecords
        self.ids = ids
        self.assembly = assembly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        project = try container.decodeIfPresent(ProjectSection.self, forKey: .project) ?? ProjectSection()
        build = try container.decodeIfPresent(BuildSection.self, forKey: .build) ?? BuildSection()
        decisionRecords = try container.decodeIfPresent(DecisionRecordsSection.self, forKey: .decisionRecords)
            ?? DecisionRecordsSection()
        ids = try container.decodeIfPresent(IdsSection.self, forKey: .ids) ?? IdsSection()
        assembly = try container.decodeIfPresent(AssemblyConfigSection.self, forKey: .assembly)
            ?? AssemblyConfigSection()
    }

    static let `default` = SpecticusConfig()

    /// User overrides under `assembly:` in config.yml (#140).
    struct AssemblyConfigSection: Codable, Equatable, Sendable {
        var sections: [AssemblySectionSpec]

        init(sections: [AssemblySectionSpec] = []) {
            self.sections = sections
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sections = try c.decodeIfPresent([AssemblySectionSpec].self, forKey: .sections) ?? []
        }

        enum CodingKeys: String, CodingKey {
            case sections
        }
    }

    // MARK: Nested sections

    struct ProjectSection: Codable, Equatable, Sendable {
        var title: String?
        var author: String?

        init(title: String? = nil, author: String? = nil) {
            self.title = title
            self.author = author
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            author = try container.decodeIfPresent(String.self, forKey: .author)
        }
    }

    struct BuildSection: Codable, Equatable, Sendable {
        /// Preferred single-file input when multi-file discovery finds nothing (legacy projects).
        var defaultInput: String?
        /// Default HTML output path relative to the project root (structured default: `output/index.html`).
        var output: String
        /// Source stylesheet path relative to the project root (copied into `css/` next to the HTML when copy_assets is true).
        var css: String
        var diagramsEnabled: Bool
        /// Directory for diagram sources (Mermaid `.mmd`, future PlantUML, etc.).
        var diagramsDir: String
        /// When true, copy CSS/images/SVGs into a structured tree beside the HTML and rewrite references (#9).
        var copyAssets: Bool
        /// When true, increment `.specticus/build-number.yml` on each build and stamp the HTML footer (#8).
        var trackBuilds: Bool
        /// Maximum ATX heading level to auto-number (0 = off, default 3, max 6). Disjoint from traceability IDs (BR1, TS2, etc.) (#4 / #6).
        var headingNumberMaxLevel: Int
        /// When true, inject a hyperlinked table of contents (#12).
        var tocEnabled: Bool
        /// Maximum heading level included in the TOC (0 = off via disable, default 3, max 6).
        var tocMaxLevel: Int

        enum CodingKeys: String, CodingKey {
            case defaultInput = "default_input"
            case output
            case css
            case diagramsEnabled = "diagrams_enabled"
            case diagramsDir = "diagrams_dir"
            case copyAssets = "copy_assets"
            case trackBuilds = "track_builds"
            case headingNumberMaxLevel = "heading_number_max_level"
            case tocEnabled = "toc"
            case tocMaxLevel = "toc_max_level"
        }

        init(
            defaultInput: String? = nil,
            output: String = "output/index.html",
            css: String = "style.css",
            diagramsEnabled: Bool = true,
            diagramsDir: String = "diagrams",
            copyAssets: Bool = true,
            trackBuilds: Bool = true,
            headingNumberMaxLevel: Int = HeadingNumberer.defaultMaxLevel,
            tocEnabled: Bool = true,
            tocMaxLevel: Int = TableOfContents.defaultMaxLevel
        ) {
            self.defaultInput = defaultInput
            self.output = output
            self.css = css
            self.diagramsEnabled = diagramsEnabled
            self.diagramsDir = diagramsDir
            self.copyAssets = copyAssets
            self.trackBuilds = trackBuilds
            self.headingNumberMaxLevel = HeadingNumberer.clampMaxLevel(headingNumberMaxLevel)
            self.tocEnabled = tocEnabled
            self.tocMaxLevel = TableOfContents.clampMaxLevel(tocMaxLevel)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            defaultInput = try container.decodeIfPresent(String.self, forKey: .defaultInput)
            output = try container.decodeIfPresent(String.self, forKey: .output) ?? "output/index.html"
            css = try container.decodeIfPresent(String.self, forKey: .css) ?? "style.css"
            diagramsEnabled = try container.decodeIfPresent(Bool.self, forKey: .diagramsEnabled) ?? true
            diagramsDir = try container.decodeIfPresent(String.self, forKey: .diagramsDir) ?? "diagrams"
            copyAssets = try container.decodeIfPresent(Bool.self, forKey: .copyAssets) ?? true
            trackBuilds = try container.decodeIfPresent(Bool.self, forKey: .trackBuilds) ?? true
            let rawMax = try container.decodeIfPresent(Int.self, forKey: .headingNumberMaxLevel)
                ?? HeadingNumberer.defaultMaxLevel
            headingNumberMaxLevel = HeadingNumberer.clampMaxLevel(rawMax)
            tocEnabled = try container.decodeIfPresent(Bool.self, forKey: .tocEnabled) ?? true
            let rawToc = try container.decodeIfPresent(Int.self, forKey: .tocMaxLevel)
                ?? TableOfContents.defaultMaxLevel
            tocMaxLevel = TableOfContents.clampMaxLevel(rawToc)
        }
    }

    struct DecisionRecordsSection: Codable, Equatable, Sendable {
        var adrsEnabled: Bool
        var bdrsEnabled: Bool

        enum CodingKeys: String, CodingKey {
            case adrsEnabled = "adrs_enabled"
            case bdrsEnabled = "bdrs_enabled"
        }

        init(adrsEnabled: Bool = true, bdrsEnabled: Bool = true) {
            self.adrsEnabled = adrsEnabled
            self.bdrsEnabled = bdrsEnabled
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            adrsEnabled = try container.decodeIfPresent(Bool.self, forKey: .adrsEnabled) ?? true
            bdrsEnabled = try container.decodeIfPresent(Bool.self, forKey: .bdrsEnabled) ?? true
        }
    }

    /// How strictly heading text is compared to `ids.json` bindings when detecting content drift (#36).
    ///
    /// Config values (YAML `ids.drift_sensitivity`):
    /// - `strict` (default) — any character difference is drift
    /// - `contentStrict` — allow case changes and whitespace grow/shrink (not removal between tokens)
    /// - `contentStrictPlus` — same as `contentStrict`, plus ignore punctuation/symbol differences
    ///
    /// Snake_case aliases `content_strict` / `content_strict_plus` are also accepted.
    enum DriftSensitivity: String, Codable, Equatable, Sendable, CaseIterable {
        case strict
        case contentStrict
        case contentStrictPlus

        static let `default`: DriftSensitivity = .strict

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            switch raw {
            case "strict":
                self = .strict
            case "contentStrict", "content_strict":
                self = .contentStrict
            case "contentStrictPlus", "content_strict_plus":
                self = .contentStrictPlus
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown ids.drift_sensitivity '\(raw)'. Use strict, contentStrict, or contentStrictPlus."
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .strict: try c.encode("strict")
            case .contentStrict: try c.encode("contentStrict")
            case .contentStrictPlus: try c.encode("contentStrictPlus")
            }
        }
    }

    struct IdsSection: Codable, Equatable, Sendable {
        /// When true, `scs build` reports pending ID assignments (dry-run only) (#6 / #38).
        ///
        /// **Does not rewrite Markdown by itself.** Actual source mutation during build requires
        /// an explicit `scs build --assign-ids`. Prefer `scs ids assign --dry-run`
        /// then `--yes` (#35). Leaving this true in CI is safe for reporting; never pass
        /// `--assign-ids` in shared or automated checkouts unless intentional.
        var autoAssign: Bool
        /// Maximum ATX heading level that may own a traceability ID (#32).
        /// Levels **1…headingMaxLevel** are eligible (default **2** = H1+H2; max **6**).
        /// Completely disjoint from `build.heading_number_max_level` (#4) and TOC max (#12).
        var headingMaxLevel: Int
        /// Drift comparison sensitivity (#36). Default **strict**.
        var driftSensitivity: DriftSensitivity

        /// Minimum ATX level that can ever own an ID (always H1).
        static let minHeadingLevel = 1
        /// Absolute maximum ATX level for ID ownership.
        static let absoluteMaxHeadingLevel = 6
        /// Product default: H1 and H2 only.
        static let defaultHeadingMaxLevel = 2

        enum CodingKeys: String, CodingKey {
            case autoAssign = "auto_assign"
            case headingMaxLevel = "heading_max_level"
            case driftSensitivity = "drift_sensitivity"
        }

        init(
            autoAssign: Bool = false,
            headingMaxLevel: Int = defaultHeadingMaxLevel,
            driftSensitivity: DriftSensitivity = .default
        ) {
            self.autoAssign = autoAssign
            self.headingMaxLevel = Self.clampHeadingMaxLevel(headingMaxLevel)
            self.driftSensitivity = driftSensitivity
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            autoAssign = try container.decodeIfPresent(Bool.self, forKey: .autoAssign) ?? false
            let rawMax = try container.decodeIfPresent(Int.self, forKey: .headingMaxLevel)
                ?? Self.defaultHeadingMaxLevel
            headingMaxLevel = Self.clampHeadingMaxLevel(rawMax)
            driftSensitivity = try container.decodeIfPresent(DriftSensitivity.self, forKey: .driftSensitivity)
                ?? .default
        }

        /// Clamp configured max into **1…6** (IDs cannot be fully disabled via 0; use assign sparingly instead).
        static func clampHeadingMaxLevel(_ value: Int) -> Int {
            min(max(value, minHeadingLevel), absoluteMaxHeadingLevel)
        }
    }

    // MARK: Loading

    /// Decode a config from YAML text.
    static func parse(yaml: String) throws -> SpecticusConfig {
        try YAMLDecoder().decode(SpecticusConfig.self, from: yaml)
    }

    /// Load config from a file URL. Throws if the file is missing or invalid.
    static func load(from url: URL) throws -> SpecticusConfig {
        let yaml = try String(contentsOf: url, encoding: .utf8)
        return try parse(yaml: yaml)
    }
}

// MARK: - title.yml metadata

/// Optional root-level project metadata (`title.yml`). Takes precedence over `config.project` for document title.
struct TitleMetadata: Codable, Equatable, Sendable {
    var title: String?
    var subtitle: String?
    var version: String?
    var author: String?
    var organization: String?
    var date: String?
    var description: String?
    var rights: String?

    init(
        title: String? = nil,
        subtitle: String? = nil,
        version: String? = nil,
        author: String? = nil,
        organization: String? = nil,
        date: String? = nil,
        description: String? = nil,
        rights: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.version = version
        self.author = author
        self.organization = organization
        self.date = date
        self.description = description
        self.rights = rights
    }

    static func load(from url: URL) throws -> TitleMetadata {
        let yaml = try String(contentsOf: url, encoding: .utf8)
        return try YAMLDecoder().decode(TitleMetadata.self, from: yaml)
    }
}
