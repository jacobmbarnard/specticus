import Foundation
import ArgumentParser

// MARK: - Open Command (#122)

struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Open the built HTML documentation in the default browser.",
        discussion: """
        Resolves the HTML path the same way as `build` / `clean`:
        --output when provided, else build.output from `.specticus/config.yml`, \
        else the default `output/index.html`. Opens the file with the OS default \
        application (macOS `open`, Linux `xdg-open`). Does not start a local server. \
        Run `specticus build` first if the file is missing.
        """
    )

    @Option(name: .shortAndLong, help: "HTML path to open (defaults to build.output in .specticus/config.yml, or output/index.html)")
    var output: String?

    func run() throws {
        let project = try SpecticusProject.load()
        let relativePath = OpenHTML.resolvedRelativePath(
            outputOverride: output,
            defaultOutput: project.defaultOutputPath
        )
        let absoluteURL = project.resolve(relativePath).standardizedFileURL

        try OpenHTML.requireExistingFile(at: absoluteURL, displayPath: relativePath)

        try SystemBrowser.open(fileURL: absoluteURL)

        let display = displayPath(absoluteURL.path, projectRoot: project.root.path)
        print("Opened \(display)")
        if display != absoluteURL.path {
            print("  \(absoluteURL.path)")
        }
    }

    private func displayPath(_ path: String, projectRoot: String) -> String {
        if path.hasPrefix(projectRoot + "/") {
            return String(path.dropFirst(projectRoot.count + 1))
        }
        if path == projectRoot { return "." }
        return path
    }
}

// MARK: - Path resolution (testable)

enum OpenHTML {
    /// Prefer CLI `--output`, otherwise the project's configured default.
    static func resolvedRelativePath(outputOverride: String?, defaultOutput: String) -> String {
        if let outputOverride, !outputOverride.isEmpty {
            return outputOverride
        }
        return defaultOutput
    }

    /// Fail clearly when HTML has not been built yet.
    static func requireExistingFile(at url: URL, displayPath: String) throws {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        guard exists else {
            throw ValidationError(
                """
                HTML output not found: \(displayPath)
                Run `specticus build` first, or pass --output to an existing HTML file.
                """
            )
        }
        if isDir.boolValue {
            throw ValidationError(
                """
                Path is a directory, not an HTML file: \(displayPath)
                Pass --output to the HTML file (e.g. output/index.html).
                """
            )
        }
    }
}

// MARK: - Platform default application

enum SystemBrowser {
    /// Open a local file with the platform default handler (browser for HTML).
    static func open(fileURL: URL) throws {
        let path = fileURL.path
        let (executable, arguments) = try launchSpec(for: path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ValidationError(
                "Failed to launch \(executable) to open \(path): \(error.localizedDescription)"
            )
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ValidationError(
                "Failed to open \(path) (\(executable) exited with status \(process.terminationStatus))."
            )
        }
    }

    /// Resolve executable + args for unit tests and the open command.
    static func launchSpec(for path: String) throws -> (executable: String, arguments: [String]) {
        #if os(macOS)
        return ("/usr/bin/open", [path])
        #elseif os(Windows)
        // Windows support is secondary (#62); best-effort when the toolchain targets it.
        return ("cmd.exe", ["/c", "start", "", path])
        #else
        // Linux and other Unix: prefer xdg-open from PATH, then common absolute path.
        if let xdg = findExecutable(named: "xdg-open") {
            return (xdg, [path])
        }
        let fallback = "/usr/bin/xdg-open"
        if FileManager.default.isExecutableFile(atPath: fallback) {
            return (fallback, [path])
        }
        throw ValidationError(
            """
            Could not find `xdg-open` to open \(path).
            Install xdg-utils (or open the HTML file manually).
            """
        )
        #endif
    }

    #if !os(macOS) && !os(Windows)
    private static func findExecutable(named name: String) -> String? {
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        for dir in pathEnv.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
    #endif
}
