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

    enum CodingKeys: String, CodingKey {
        case version
        case project
        case build
        case decisionRecords = "decision_records"
        case ids
    }

    init(
        version: Int = 1,
        project: ProjectSection = ProjectSection(),
        build: BuildSection = BuildSection(),
        decisionRecords: DecisionRecordsSection = DecisionRecordsSection(),
        ids: IdsSection = IdsSection()
    ) {
        self.version = version
        self.project = project
        self.build = build
        self.decisionRecords = decisionRecords
        self.ids = ids
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        project = try container.decodeIfPresent(ProjectSection.self, forKey: .project) ?? ProjectSection()
        build = try container.decodeIfPresent(BuildSection.self, forKey: .build) ?? BuildSection()
        decisionRecords = try container.decodeIfPresent(DecisionRecordsSection.self, forKey: .decisionRecords)
            ?? DecisionRecordsSection()
        ids = try container.decodeIfPresent(IdsSection.self, forKey: .ids) ?? IdsSection()
    }

    static let `default` = SpecticusConfig()

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
        /// Maximum ATX heading level to auto-number (0 = off, default 3, max 6). Disjoint from traceability IDs (#4 / #6).
        var headingNumberMaxLevel: Int

        enum CodingKeys: String, CodingKey {
            case defaultInput = "default_input"
            case output
            case css
            case diagramsEnabled = "diagrams_enabled"
            case diagramsDir = "diagrams_dir"
            case copyAssets = "copy_assets"
            case trackBuilds = "track_builds"
            case headingNumberMaxLevel = "heading_number_max_level"
        }

        init(
            defaultInput: String? = nil,
            output: String = "output/index.html",
            css: String = "style.css",
            diagramsEnabled: Bool = true,
            diagramsDir: String = "diagrams",
            copyAssets: Bool = true,
            trackBuilds: Bool = true,
            headingNumberMaxLevel: Int = HeadingNumberer.defaultMaxLevel
        ) {
            self.defaultInput = defaultInput
            self.output = output
            self.css = css
            self.diagramsEnabled = diagramsEnabled
            self.diagramsDir = diagramsDir
            self.copyAssets = copyAssets
            self.trackBuilds = trackBuilds
            self.headingNumberMaxLevel = HeadingNumberer.clampMaxLevel(headingNumberMaxLevel)
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

    struct IdsSection: Codable, Equatable, Sendable {
        var autoAssign: Bool

        enum CodingKeys: String, CodingKey {
            case autoAssign = "auto_assign"
        }

        init(autoAssign: Bool = false) {
            self.autoAssign = autoAssign
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            autoAssign = try container.decodeIfPresent(Bool.self, forKey: .autoAssign) ?? false
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
