import Foundation
import ArgumentParser

// MARK: - Init Command (implements #2)

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Initialize a new specticus documentation project with templates and structure.",
        discussion: "Creates numbered section Markdown files, ADRs/ with status folders, diagrams/, .specticus/config.yml, title.yml, style.css, and a starter welcome-template.md."
    )

    @Argument(help: "Directory name for the new project (defaults to current directory)")
    var directory: String?

    @Flag(name: .long, help: "Initialize even if the target directory is not empty (may overwrite files)")
    var force: Bool = false

    func run() throws {
        let fm = FileManager.default
        let (targetDir, projectName) = resolveTarget(fm: fm)

        // Ensure target directory
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: targetDir, isDirectory: &isDir) {
            if !isDir.boolValue {
                throw ValidationError("'\(targetDir)' exists and is a file, not a directory.")
            }
            // Safety: refuse to init into visibly non-empty dir unless --force
            let contents = try fm.contentsOfDirectory(atPath: targetDir)
            let nonDot = contents.filter { !$0.hasPrefix(".") }
            if !nonDot.isEmpty && !force {
                throw ValidationError("Target '\(targetDir)' is not empty. Use --force if you want to scaffold here anyway.")
            }
        } else if targetDir != "." {
            try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)
        }

        // Locate embedded skeleton
        guard let skeletonURL = Bundle.module.url(forResource: "Skeleton", withExtension: nil, subdirectory: "Resources") else {
            throw ValidationError("Internal error: embedded template resources not found (Skeleton).")
        }

        let targetURL = URL(fileURLWithPath: targetDir)
        try copySkeleton(from: skeletonURL, to: targetURL, projectName: projectName, fm: fm)

        let displayTarget = (targetDir == ".") ? "." : targetDir
        print("✅ Initialized specticus project '\(projectName)' in '\(displayTarget)'.")
        print("")
        print("Contents created:")
        print("  • title.yml, welcome-template.md, style.css")
        print("  • 001-007 numbered section templates (lex order for future builds)")
        print("  • ADRs/ (proposed/accepted/deprecated/superseded) + example ADR")
        print("  • diagrams/ (starter PlantUML files)")
        print("  • .specticus/config.yml")
        print("")
        print("Next steps:")
        if targetDir != "." {
            print("  cd \(targetDir)")
        }
        print("  specticus build")
        print("  # Edit files, then re-build. See README.md for more.")
    }

    private func resolveTarget(fm: FileManager) -> (targetDir: String, projectName: String) {
        if let dir = directory, !dir.isEmpty, dir != "." {
            let name = URL(fileURLWithPath: dir).lastPathComponent
            return (dir, name.isEmpty ? dir : name)
        }
        let cwd = fm.currentDirectoryPath
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return (".", name.isEmpty ? "specticus-project" : name)
    }

    private func copySkeleton(from src: URL, to dst: URL, projectName: String, fm: FileManager) throws {
        // Walk the skeleton (include dot-dirs like .specticus and dot-files like .gitkeep)
        let enumerator = fm.enumerator(
            at: src,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [] // do NOT skip hidden files/dirs
        )

        guard let enumerator = enumerator else {
            throw ValidationError("Failed to enumerate template skeleton.")
        }

        for case let fileURL as URL in enumerator {
            let filePath = fileURL.path
            let srcBase = src.path
            var rel = ""
            if filePath.hasPrefix(srcBase) {
                rel = String(filePath.dropFirst(srcBase.count))
            }
            rel = rel.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            if rel.isEmpty { continue }

            let destURL = dst.appendingPathComponent(rel)

            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: filePath, isDirectory: &isDirectory), isDirectory.boolValue {
                try fm.createDirectory(at: destURL, withIntermediateDirectories: true)
                continue
            }

            // Regular file: load, substitute placeholders, write
            var content = try String(contentsOf: fileURL, encoding: .utf8)
            content = content.replacingOccurrences(of: "{{PROJECT_NAME}}", with: projectName)

            try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: destURL, atomically: true, encoding: .utf8)
        }
    }
}
