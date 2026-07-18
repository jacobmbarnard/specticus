import Foundation
import ArgumentParser

// MARK: - Project paths & config resolution (implements #7)

/// Resolved view of a specticus project root: paths under `.specticus/`, loaded config, and title metadata.
struct SpecticusProject: Sendable {
    /// Absolute project root directory.
    let root: URL
    /// Loaded configuration (defaults if no config file).
    let config: SpecticusConfig
    /// Parsed `title.yml` when present.
    let titleMetadata: TitleMetadata?
    /// How config was obtained.
    let configSource: ConfigSource
    /// Non-fatal issues discovered while loading (e.g. unreadable title.yml).
    let warnings: [String]

    enum ConfigSource: String, Sendable {
        case file
        case defaults
    }

    // MARK: Standard paths

    static let hiddenDirectoryName = ".specticus"
    static let configFileName = "config.yml"
    static let titleFileName = "title.yml"
    static let idsFileName = "ids.json"  // stores BR1, TS2, ADR3 etc. (simple prefix+integer)
    /// Append-only audit log for deliberate ID rebinds (`ids accept-drift`, #66).
    static let idsAuditFileName = "ids-audit.jsonl"
    static let buildNumberFileName = "build-number.yml"

    var specticusDirectory: URL {
        root.appendingPathComponent(Self.hiddenDirectoryName, isDirectory: true)
    }

    var configURL: URL {
        specticusDirectory.appendingPathComponent(Self.configFileName)
    }

    var titleURL: URL {
        root.appendingPathComponent(Self.titleFileName)
    }

    var idsURL: URL {
        specticusDirectory.appendingPathComponent(Self.idsFileName)
    }

    var idsAuditURL: URL {
        specticusDirectory.appendingPathComponent(Self.idsAuditFileName)
    }

    var buildNumberURL: URL {
        specticusDirectory.appendingPathComponent(Self.buildNumberFileName)
    }

    var diagramsDirectory: URL {
        root.appendingPathComponent(config.build.diagramsDir, isDirectory: true)
    }

    var styleSheetPath: String {
        config.build.css
    }

    var defaultOutputPath: String {
        config.build.output
    }

    /// Prefer title.yml title, then config.project.title, then a generic fallback.
    var documentTitle: String {
        if let t = titleMetadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        if let t = config.project.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        return "specticus • Documentation"
    }

    var hasSpecticusDirectory: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: specticusDirectory.path, isDirectory: &isDir) && isDir.boolValue
    }

    var hasConfigFile: Bool {
        FileManager.default.fileExists(atPath: configURL.path)
    }

    /// Resolve a project-relative path against the project root.
    func resolve(_ relativePath: String) -> URL {
        if relativePath.hasPrefix("/") {
            return URL(fileURLWithPath: relativePath)
        }
        return root.appendingPathComponent(relativePath)
    }

    // MARK: Loading

    /// Load project state from `directory` (defaults to the current working directory).
    /// - Uses `.specticus/config.yml` when present and valid.
    /// - Falls back to `SpecticusConfig.default` when the config file is missing (legacy projects).
    /// - Throws if the config file exists but cannot be parsed.
    static func load(from directory: String = ".") throws -> SpecticusProject {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL
        var warnings: [String] = []

        let configURL = rootURL
            .appendingPathComponent(hiddenDirectoryName, isDirectory: true)
            .appendingPathComponent(configFileName)

        let config: SpecticusConfig
        let source: ConfigSource

        if fm.fileExists(atPath: configURL.path) {
            do {
                config = try SpecticusConfig.load(from: configURL)
                source = .file
            } catch {
                throw ValidationError(
                    "Failed to parse \(hiddenDirectoryName)/\(configFileName): \(error.localizedDescription)"
                )
            }
        } else {
            config = .default
            source = .defaults
        }

        let titleURL = rootURL.appendingPathComponent(titleFileName)
        var titleMeta: TitleMetadata?
        if fm.fileExists(atPath: titleURL.path) {
            do {
                titleMeta = try TitleMetadata.load(from: titleURL)
            } catch {
                warnings.append("Could not parse \(titleFileName): \(error.localizedDescription)")
            }
        }

        return SpecticusProject(
            root: rootURL,
            config: config,
            titleMetadata: titleMeta,
            configSource: source,
            warnings: warnings
        )
    }
}
