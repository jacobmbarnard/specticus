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
        let tocHTML = tocApplied.tocHTML
        let hasTOC = !tocHTML.isEmpty
        let sidebarTOC = hasTOC
            ? tocHTML.replacingOccurrences(of: "\n", with: "\n            ")
            : "<p class=\"sidebar-empty text-muted\">No contents</p>"

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

        // Layout: left sidebar (browser) + main column; print CSS hides sidebar (#143).
        return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="color-scheme" content="light dark">
    <title>\(escapedTitle)</title>
    <link rel="stylesheet" href="\(escapeHTML(stylesheet))">
</head>
<body>
    <div class="layout">
        <aside class="sidebar" aria-label="Document navigation">
            <div class="sidebar-header">
                <a href="#" class="sidebar-brand">specticus</a>
                <p class="sidebar-tagline text-muted">documentation as code</p>
            </div>
            <div class="sidebar-nav">
            \(sidebarTOC)
            </div>
        </aside>
        <div class="layout-main">
            <main class="main-content" id="main">
                <article class="page-content">
            \(bodyHTML)
                </article>
            </main>\(footerHTML)
        </div>
    </div>
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
    /// - If `input` is nil: discovers content files via `MarkdownSources` (#35 / #3) —
    ///   top-level `*.md` / `*.markdown`, lex order, skips README* and welcome-template.md —
    ///   and concatenates them.
    /// - Falls back to `fallbackInput` (from config) when set, then `welcome-template.md`
    ///   for legacy single-file projects when no other .md files are present.
    /// Hidden directories (e.g. `.specticus/`) are never treated as content sources.
    static func assembleSources(
        input: String? = nil,
        baseDirectory: String = ".",
        fallbackInput: String? = nil,
        layout: AssemblyLayout = .packDefault
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

        // Multi-file discovery (#35 / #139 / #140): shared with IdsManager via MarkdownSources.
        let mdFiles = try MarkdownSources.discoverContentFiles(in: baseURL, layout: layout)

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
