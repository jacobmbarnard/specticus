import Ink
import Foundation
import ArgumentParser

// Core generation logic for turning Markdown into styled HTML output.
// Expanded for #3: multi-file Markdown assembly in lex order.


struct DocumentGenerator {
    static func generateHTML(from markdown: String, title: String = "specticus • Documentation") throws -> String {
        let bodyHTML = MarkdownParser().html(from: markdown)

        return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>\(title)</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <header class="site-header">
        <div class="site-header-inner">
            <a href="#" class="site-title">specticus</a>
            <span class="site-nav text-muted">Documentation</span>
        </div>
    </header>

    <main class="main-content">
        <div class="page-content">
            \(bodyHTML)
        </div>
    </main>
</body>
</html>
"""
    }

    static func writeOutput(_ html: String, to path: String = "output.html") throws {
        let outputURL = URL(fileURLWithPath: path)
        try html.write(to: outputURL, atomically: true, encoding: .utf8)
        print("Wrote \(outputURL.lastPathComponent)")
    }

    /// Assembles Markdown content.
    /// - If `input` is provided: loads that single file (single-file mode).
    /// - If `input` is nil: discovers all *.md / *.markdown files in the directory,
    ///   sorts them lexicographically, skips README* and welcome-template.md,
    ///   and concatenates them. (implements #3)
    /// Falls back to welcome-template.md for legacy single-file projects when no other .md files are present.
    static func assembleSources(input: String? = nil, baseDirectory: String = ".") throws -> String {
        let fm = FileManager.default
        let baseURL = URL(fileURLWithPath: baseDirectory)

        if let input = input {
            let inputURL = URL(fileURLWithPath: input, relativeTo: baseURL).standardized
            guard fm.fileExists(atPath: inputURL.path) else {
                throw ValidationError("Input file not found: \(input).")
            }
            return try String(contentsOf: inputURL, encoding: .utf8)
        }

        // Multi-file discovery (lexicographic order)
        let contents = try fm.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let mdFiles = contents
            .filter { url in
                let name = url.lastPathComponent.lowercased()
                return (name.hasSuffix(".md") || name.hasSuffix(".markdown")) &&
                       name != "readme.md" &&
                       name != "readme.markdown" &&
                       name != "welcome-template.md"
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        if mdFiles.isEmpty {
            // Legacy fallback for projects without numbered .md files
            let legacy = baseURL.appendingPathComponent("welcome-template.md")
            if fm.fileExists(atPath: legacy.path) {
                return try String(contentsOf: legacy, encoding: .utf8)
            }
            throw ValidationError("No Markdown files found to assemble (looked for *.md / *.markdown). Specify --input or add content files.")
        }

        let parts = try mdFiles.map { try String(contentsOf: $0, encoding: .utf8) }
        // Join with blank lines; each file typically starts with its own heading
        return parts.joined(separator: "\n\n")
    }
}
