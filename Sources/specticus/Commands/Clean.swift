import Foundation
import ArgumentParser

// MARK: - Clean Command

struct Clean: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove generated output files and directories.",
        discussion: "Removes the configured HTML output (from `.specticus/config.yml` when present). Structured output/ cleanup lands with issue #9."
    )

    func run() throws {
        let fm = FileManager.default
        let project = try SpecticusProject.load()
        var removed = 0

        // Classic default plus the configured path (resolved under project root).
        var candidateURLs: [URL] = [
            project.resolve("output.html"),
            project.resolve(project.defaultOutputPath)
        ]
        // De-dupe by standardized path
        var seen = Set<String>()
        candidateURLs = candidateURLs.filter { url in
            let key = url.standardizedFileURL.path
            return seen.insert(key).inserted
        }

        for url in candidateURLs {
            let resolved = url.standardizedFileURL.path
            guard fm.fileExists(atPath: resolved) else { continue }
            // Never delete directories here until #9 defines the output tree.
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: resolved, isDirectory: &isDir), !isDir.boolValue else { continue }
            try fm.removeItem(atPath: resolved)
            print("Removed \(displayPath(resolved, projectRoot: project.root.path))")
            removed += 1
        }

        // Future: also clean output/ dir, copied resources, etc. (#9)
        if removed == 0 {
            print("Nothing to clean.")
        } else {
            print("Clean complete (\(removed) file(s) removed).")
        }
    }

    private func displayPath(_ path: String, projectRoot: String) -> String {
        if path.hasPrefix(projectRoot + "/") {
            return String(path.dropFirst(projectRoot.count + 1))
        }
        return path
    }
}
