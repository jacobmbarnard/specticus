import Testing
import Foundation
@testable import scs

// MARK: - GFM export

@Test func markdownExporterKeepsOwningIDsAndBuildsTOC() {
    let md = """
    # Intro

    ## BR1: Login flow

    Text.

    ## TS1: Auth service

    More.
    """
    let out = MarkdownExporter.render(
        markdown: md,
        title: "Demo Spec",
        tocMaxLevel: 2
    )
    #expect(out.contains("Derived GFM export of **Demo Spec**"))
    #expect(out.contains("## Contents"))
    #expect(out.contains("[Login flow](#br1)"))
    #expect(out.contains("[Auth service](#ts1)"))
    #expect(out.contains("## BR1: Login flow"))
    #expect(out.contains("## TS1: Auth service"))
    #expect(out.contains("scs export markdown"))
}

@Test func markdownExporterRewritesImagePaths() {
    let md = "See ![logo](images/logo.png) and [doc](images/logo.png)."
    let rewritten = MarkdownExporter.rewriteReferences(
        in: md,
        rewrites: ["images/logo.png": "img/logo.png", "logo.png": "img/logo.png"]
    )
    #expect(rewritten.contains("![logo](img/logo.png)"))
    #expect(rewritten.contains("[doc](img/logo.png)"))
    #expect(!rewritten.contains("images/logo.png"))
}

@Test func markdownExporterDefaultPathBesideHTML() {
    #expect(MarkdownExporter.defaultPathBesideHTML("output/index.html") == "output/export.md")
    #expect(MarkdownExporter.defaultPathBesideHTML("dist/docs.html") == "dist/export.md")
    #expect(MarkdownExporter.defaultPathBesideHTML("flat.html") == "export.md")
}

@Test func configDefaultsMarkdownExportBesideOutput() throws {
    let yaml = """
    version: 1
    build:
      output: "dist/docs.html"
    """
    let config = try SpecticusConfig.parse(yaml: yaml)
    #expect(config.build.markdownExport == "dist/export.md")
}

@Test func configParsesMarkdownExportOverride() throws {
    let yaml = """
    version: 1
    build:
      output: "output/index.html"
      markdown_export: "review/spec.md"
    """
    let config = try SpecticusConfig.parse(yaml: yaml)
    #expect(config.build.markdownExport == "review/spec.md")
}

@Test func exportMarkdownCommandWritesDerivedFile() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-export-md-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try """
    version: 1
    project:
      title: Export Demo
    build:
      output: "output/index.html"
      markdown_export: "output/export.md"
      css: "style.css"
      copy_assets: true
      toc: true
      toc_max_level: 2
      heading_number_max_level: 2
    """.write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    try "body { color: #111; }\n".write(
        to: tmp.appendingPathComponent("style.css"),
        atomically: true,
        encoding: .utf8
    )
    try """
    # Business Requirements

    ## BR1: Must export GFM

    Reviewers read this in PRs.
    """.write(to: tmp.appendingPathComponent("001-business-requirements.md"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let result = try MarkdownExporter.export(project: project)

    let exportURL = tmp.appendingPathComponent("output/export.md")
    #expect(result.outputPath == "output/export.md")
    #expect(fm.fileExists(atPath: exportURL.path))
    let text = try String(contentsOf: exportURL, encoding: .utf8)
    #expect(text.contains("## BR1: Must export GFM") || text.contains("BR1: Must export GFM"))
    #expect(text.contains("## Contents"))
    #expect(text.contains("Derived GFM export"))
    #expect(fm.fileExists(atPath: tmp.appendingPathComponent("output/css/style.css").path))
}
