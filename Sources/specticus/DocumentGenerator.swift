import Ink
import Foundation
import ArgumentParser

// Core generation logic for turning Markdown into styled HTML output.
// Expanded for #3: multi-file Markdown assembly in lex order.
// Expanded for #7: config-driven title, stylesheet, and fallback input.
// Expanded for #8: optional build number + timestamp footer.
// Expanded for #9: stylesheet href is typically a path under the structured output tree.
// Expanded for #4: heading auto-numbering applied to Markdown before HTML (see HeadingNumberer).
// Expanded for #12: hyperlinked TOC + heading anchors (see TableOfContents).


struct DocumentGenerator {
    static func generateHTML(
        from markdown: String,
        title: String = "specticus • Documentation",
        stylesheet: String = "style.css",
        buildInfo: BuildRecord? = nil,
        tocMaxLevel: Int = TableOfContents.defaultMaxLevel
    ) throws -> String {
        let rawBody = MarkdownParser().html(from: markdown)
        let tocApplied = TableOfContents.apply(
            markdown: markdown,
            bodyHTML: rawBody,
            maxLevel: tocMaxLevel
        )
        let bodyHTML = tocApplied.bodyHTML
        let tocBlock = tocApplied.tocHTML.isEmpty
            ? ""
            : "\n            \(tocApplied.tocHTML.replacingOccurrences(of: "\n", with: "\n            "))\n"

        let escapedTitle = escapeHTML(title)

        let footerHTML: String
        if let buildInfo {
            let line = escapeHTML(buildInfo.displayLine)
            footerHTML = """

    <footer class="site-footer">
        <div class="site-footer-inner text-muted">
            \(line)
        </div>
    </footer>
"""
        } else {
            footerHTML = ""
        }

        let tocNavLink = tocApplied.tocHTML.isEmpty
            ? "<span class=\"site-nav text-muted\">Documentation</span>"
            : "<a class=\"site-nav\" href=\"#toc\">Contents</a>"

        return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>\(escapedTitle)</title>
    <link rel="stylesheet" href="\(escapeHTML(stylesheet))">
</head>
<body>
    <header class="site-header">
        <div class="site-header-inner">
            <a href="#" class="site-title">specticus</a>
            \(tocNavLink)
        </div>
    </header>

    <main class="main-content">
        <div class="page-content">\(tocBlock)
            \(bodyHTML)
        </div>
    </main>
\(footerHTML)
</body>
</html>
"""
    }

    static func writeOutput(_ html: String, to path: String = "output.html") throws {
        let outputURL = URL(fileURLWithPath: path)
        let parent = outputURL.deletingLastPathComponent()
        if parent.path != "" && parent.path != "." {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try html.write(to: outputURL, atomically: true, encoding: .utf8)
        print("Wrote \(path)")
    }

    /// Assembles Markdown content.
    /// - If `input` is provided: loads that single file (single-file mode).
    /// - If `input` is nil: discovers all *.md / *.markdown files in the directory,
    ///   sorts them lexicographically, skips README* and welcome-template.md,
    ///   and concatenates them. (implements #3)
    /// - Falls back to `fallbackInput` (from config) when set, then `welcome-template.md`
    ///   for legacy single-file projects when no other .md files are present.
    /// Hidden directories (e.g. `.specticus/`) are never treated as content sources.
    static func assembleSources(
        input: String? = nil,
        baseDirectory: String = ".",
        fallbackInput: String? = nil
    ) throws -> String {
        let fm = FileManager.default
        let baseURL = URL(fileURLWithPath: baseDirectory)

        if let input = input {
            let inputURL = URL(fileURLWithPath: input, relativeTo: baseURL).standardized
            guard fm.fileExists(atPath: inputURL.path) else {
                throw ValidationError("Input file not found: \(input).")
            }
            return try String(contentsOf: inputURL, encoding: .utf8)
        }

        // Multi-file discovery (lexicographic order). skipsHiddenFiles excludes `.specticus/`.
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
            // Config-driven fallback, then legacy welcome-template.md
            let candidates = [fallbackInput, "welcome-template.md"].compactMap { $0 }
            for name in candidates {
                let url = baseURL.appendingPathComponent(name)
                if fm.fileExists(atPath: url.path) {
                    return try String(contentsOf: url, encoding: .utf8)
                }
            }
            throw ValidationError("No Markdown files found to assemble (looked for *.md / *.markdown). Specify --input or add content files.")
        }

        let parts = try mdFiles.map { try String(contentsOf: $0, encoding: .utf8) }
        // Join with blank lines; each file typically starts with its own heading
        return parts.joined(separator: "\n\n")
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
