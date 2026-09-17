import Foundation

// MARK: - Build-time Mermaid `.mmd` → SVG (#21)

/// Process lookup + exec, injectable for tests.
protocol ProcessRunning: Sendable {
    func findExecutable(_ name: String) -> String?
    func run(executable: String, arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String)
}

struct FoundationProcessRunner: ProcessRunning {
    func findExecutable(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("/") || trimmed.hasPrefix(".") {
            let path = (trimmed as NSString).expandingTildeInPath
            return FileManager.default.isExecutableFile(atPath: path) ? path : nil
        }
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in pathEnv.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(trimmed).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    func run(executable: String, arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}

/// Discover Mermaid sources, render to `output/svg/`, rewrite HTML references.
enum DiagramPipeline {
    struct Outcome: Sendable {
        var rewrites: [String: String]
        var generatedRelative: [String]
        var warnings: [String]
        var skipped: Bool
        /// CLI was missing while `.mmd` files existed.
        var missingCLI: Bool
    }

    /// Render `*.mmd` under `diagramsDir` into `outputRoot/svg/`.
    static func renderMMDFiles(
        projectRoot: URL,
        diagramsDir: String,
        outputRoot: URL,
        enabled: Bool,
        cliName: String = "mmdc",
        runner: any ProcessRunning = FoundationProcessRunner()
    ) throws -> Outcome {
        guard enabled else {
            return Outcome(rewrites: [:], generatedRelative: [], warnings: [], skipped: true, missingCLI: false)
        }

        let sources = try discoverMMDFiles(
            projectRoot: projectRoot,
            diagramsDir: diagramsDir
        )
        guard !sources.isEmpty else {
            return Outcome(rewrites: [:], generatedRelative: [], warnings: [], skipped: false, missingCLI: false)
        }

        let cli = ProcessInfo.processInfo.environment["SCS_MERMAID_CLI"].flatMap { raw -> String? in
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        } ?? cliName

        guard let executable = runner.findExecutable(cli) else {
            let warning = """
            Mermaid CLI '\(cli)' not found; skipping SVG generation for \(sources.count) .mmd file(s). \
            Install: npm install -g @mermaid-js/mermaid-cli  (or set SCS_MERMAID_CLI / build.mermaid_cli).
            """
            return Outcome(
                rewrites: [:],
                generatedRelative: [],
                warnings: [warning],
                skipped: true,
                missingCLI: true
            )
        }

        let fm = FileManager.default
        let svgRoot = outputRoot.appendingPathComponent("svg", isDirectory: true)
        try fm.createDirectory(at: svgRoot, withIntermediateDirectories: true)

        var rewrites: [String: String] = [:]
        var generated: [String] = []
        var warnings: [String] = []
        let diagramsName = diagramsDir.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        for source in sources {
            let relMMD = source.relativePath
            let relSVG = (relMMD as NSString).deletingPathExtension + ".svg"
            let destURL = svgRoot.appendingPathComponent(relSVG)
            try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            let args = ["-i", source.url.path, "-o", destURL.path, "-b", "transparent"]
            let result: (status: Int32, stdout: String, stderr: String)
            do {
                result = try runner.run(executable: executable, arguments: args)
            } catch {
                warnings.append("Failed to run \(cli) for \(relMMD): \(error.localizedDescription)")
                continue
            }
            if result.status != 0 {
                let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                warnings.append(
                    "\(cli) failed for \(relMMD) (exit \(result.status))\(detail.isEmpty ? "" : ": \(detail)")"
                )
                continue
            }
            guard fm.fileExists(atPath: destURL.path) else {
                warnings.append("\(cli) reported success for \(relMMD) but \(relSVG) was not written")
                continue
            }

            let destRelative = "svg/\(relSVG)"
            generated.append(destRelative)
            var keys = [
                relMMD,
                source.url.lastPathComponent,
                destRelative,
            ]
            if !diagramsName.isEmpty {
                keys.append("\(diagramsName)/\(relMMD)")
                keys.append("./\(diagramsName)/\(relMMD)")
            }
            for key in keys where !key.isEmpty {
                rewrites[key] = destRelative
            }
        }

        return Outcome(
            rewrites: rewrites,
            generatedRelative: generated,
            warnings: warnings,
            skipped: false,
            missingCLI: false
        )
    }

    struct MMDSource: Equatable, Sendable {
        var url: URL
        /// Path relative to the diagrams directory (`foo.mmd` or `nested/foo.mmd`).
        var relativePath: String
    }

    static func discoverMMDFiles(projectRoot: URL, diagramsDir: String) throws -> [MMDSource] {
        let fm = FileManager.default
        let dirURL = projectRoot.appendingPathComponent(diagramsDir, isDirectory: true).standardizedFileURL
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        guard let enumerator = fm.enumerator(
            at: dirURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var found: [MMDSource] = []
        let dirPath = dirURL.path
        for case let fileURL as URL in enumerator {
            var isFileDir: ObjCBool = false
            if fm.fileExists(atPath: fileURL.path, isDirectory: &isFileDir), isFileDir.boolValue {
                continue
            }
            guard fileURL.pathExtension.lowercased() == "mmd" else { continue }
            let filePath = fileURL.standardizedFileURL.path
            var rel = fileURL.lastPathComponent
            if filePath.hasPrefix(dirPath + "/") {
                rel = String(filePath.dropFirst(dirPath.count + 1))
            }
            found.append(MMDSource(url: fileURL.standardizedFileURL, relativePath: rel))
        }
        return found.sorted { $0.relativePath < $1.relativePath }
    }

    /// Turn `<code>diagrams/foo.mmd</code>` (and similar) into `<img src="svg/foo.svg">`.
    static func embedRenderedDiagrams(in html: String, rewrites: [String: String]) -> String {
        let mmdRewrites = rewrites.filter { $0.key.lowercased().hasSuffix(".mmd") }
        guard !mmdRewrites.isEmpty else { return html }

        var result = html
        let keys = mmdRewrites.keys.sorted { $0.count > $1.count }
        for original in keys {
            guard let dest = mmdRewrites[original] else { continue }
            let alt = altText(forSVGPath: dest)
            let img = #"<img class="scs-diagram" src="\#(escapeHTMLAttribute(dest))" alt="\#(escapeHTMLAttribute(alt))">"#
            let escaped = NSRegularExpression.escapedPattern(for: original)

            // <code>diagrams/foo.mmd</code>
            if let regex = try? NSRegularExpression(
                pattern: #"<code>\s*\#(escaped)\s*</code>"#,
                options: [.caseInsensitive]
            ) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(
                    in: result, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: img)
                )
            }
        }
        return result
    }

    static func whichMermaidCLI(_ name: String, runner: any ProcessRunning = FoundationProcessRunner()) -> String? {
        let env = ProcessInfo.processInfo.environment["SCS_MERMAID_CLI"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, !env.isEmpty {
            return runner.findExecutable(env)
        }
        return runner.findExecutable(name)
    }

    // MARK: - Helpers

    private static func altText(forSVGPath path: String) -> String {
        let base = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return base.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    }

    private static func escapeHTMLAttribute(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
