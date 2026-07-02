import Ink
import Foundation

// Core generation logic for turning Markdown into styled HTML output.
// Will be expanded in future issues (multi-file, numbering, TOC, resources, etc.)

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
}
