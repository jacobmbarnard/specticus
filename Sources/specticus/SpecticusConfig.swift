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
        /// Default HTML output path relative to the project root.
        var output: String
        /// Stylesheet path referenced from the generated HTML (relative to the HTML location).
        var css: String
        var diagramsEnabled: Bool
        /// Directory for diagram sources (Mermaid `.mmd`, future PlantUML, etc.).
        var diagramsDir: String

        enum CodingKeys: String, CodingKey {
            case defaultInput = "default_input"
            case output
            case css
            case diagramsEnabled = "diagrams_enabled"
            case diagramsDir = "diagrams_dir"
        }

        init(
            defaultInput: String? = nil,
            output: String = "output.html",
            css: String = "style.css",
            diagramsEnabled: Bool = true,
            diagramsDir: String = "diagrams"
        ) {
            self.defaultInput = defaultInput
            self.output = output
            self.css = css
            self.diagramsEnabled = diagramsEnabled
            self.diagramsDir = diagramsDir
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            defaultInput = try container.decodeIfPresent(String.self, forKey: .defaultInput)
            output = try container.decodeIfPresent(String.self, forKey: .output) ?? "output.html"
            css = try container.decodeIfPresent(String.self, forKey: .css) ?? "style.css"
            diagramsEnabled = try container.decodeIfPresent(Bool.self, forKey: .diagramsEnabled) ?? true
            diagramsDir = try container.decodeIfPresent(String.self, forKey: .diagramsDir) ?? "diagrams"
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
