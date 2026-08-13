import Foundation
import ArgumentParser

// MARK: - Clean Command

struct Clean: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove generated output files and directories.",
        discussion: """
        Removes the configured HTML output and its structured asset tree (css/, img/, svg/) when present. \
        Does not reset `.specticus/build-number.yml` (#8). See `.specticus/config.yml` build.output and issue #9.
        """
    )

    func run() throws {
        let fm = FileManager.default
        let project = try SpecticusProject.load()
        var removed = 0

        let configured = project.defaultOutputPath
        // Legacy flat default + current config
        let htmlCandidates = ["output.html", "output/index.html", configured]

        // Prefer removing a whole generated directory (e.g. output/) when applicable.
        var dirsToRemove: [URL] = []
        var filesToRemove: [URL] = []
        var seen = Set<String>()

        for path in htmlCandidates {
            let htmlURL = project.resolve(path).standardizedFileURL
            if let dir = ResourcePublisher.cleanableOutputDirectory(
                outputHTMLPath: path,
                projectRoot: project.root
            ) {
                let key = dir.standardizedFileURL.path
                if seen.insert(key).inserted {
                    dirsToRemove.append(dir)
                }
            } else {
                // Flat HTML at project root (legacy): remove only the HTML file.
                // Never delete project-level img/css/svg — those may be source assets.
                let key = htmlURL.path
                if seen.insert(key).inserted {
                    filesToRemove.append(htmlURL)
                }
            }
        }

        for dir in dirsToRemove {
            let path = dir.standardizedFileURL.path
            guard fm.fileExists(atPath: path) else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            // Safety: never delete project root or .specticus
            if path == project.root.standardizedFileURL.path { continue }
            if dir.lastPathComponent == ".specticus" { continue }
            try fm.removeItem(atPath: path)
            print("Removed \(displayPath(path, projectRoot: project.root.path))/")
            removed += 1
        }

        for file in filesToRemove {
            let path = file.standardizedFileURL.path
            guard fm.fileExists(atPath: path) else { continue }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue { continue }
            try fm.removeItem(atPath: path)
            print("Removed \(displayPath(path, projectRoot: project.root.path))")
            removed += 1
        }

        if removed == 0 {
            print("Nothing to clean.")
        } else {
            print("Clean complete (\(removed) item(s) removed).")
        }
    }

    private func displayPath(_ path: String, projectRoot: String) -> String {
        if path.hasPrefix(projectRoot + "/") {
            return String(path.dropFirst(projectRoot.count + 1))
        }
        return path
    }
}
