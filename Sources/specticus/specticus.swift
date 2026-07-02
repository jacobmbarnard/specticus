import Ink
import Foundation

@main
struct specticus {
    static func main() throws {
        let templateURL = URL(fileURLWithPath: "welcome-template.md")
        let markdown = try String(contentsOf: templateURL, encoding: .utf8)

        let bodyHTML = MarkdownParser().html(from: markdown)

        let fullHTML = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>specticus • Documentation</title>
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

        let outputURL = URL(fileURLWithPath: "output.html")
        try fullHTML.write(to: outputURL, atomically: true, encoding: .utf8)

        print("Wrote \(outputURL.lastPathComponent)")
    }
}
