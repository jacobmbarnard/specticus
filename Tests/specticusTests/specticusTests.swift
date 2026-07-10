import Testing
import Foundation
@testable import specticus

@Test func example() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    // Swift Testing Documentation
    // https://swiftpackageindex.com/swiftlang/swift-testing/documentation
}

@Test func multiFileAssemblyLexOrder() async throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-test-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    // Create files out of order + things that should be skipped
    try "CONTENT-003".write(to: tmp.appendingPathComponent("003-z.md"), atomically: true, encoding: .utf8)
    try "CONTENT-001".write(to: tmp.appendingPathComponent("001-a.md"), atomically: true, encoding: .utf8)
    try "CONTENT-002".write(to: tmp.appendingPathComponent("002-b.md"), atomically: true, encoding: .utf8)
    try "SHOULD-BE-SKIPPED".write(to: tmp.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    try "LEGACY".write(to: tmp.appendingPathComponent("welcome-template.md"), atomically: true, encoding: .utf8)

    let assembled = try DocumentGenerator.assembleSources(input: nil, baseDirectory: tmp.path)

    #expect(assembled.contains("CONTENT-001"))
    #expect(assembled.contains("CONTENT-002"))
    #expect(assembled.contains("CONTENT-003"))

    // Verify order
    let pos1 = assembled.range(of: "CONTENT-001")!.lowerBound
    let pos2 = assembled.range(of: "CONTENT-002")!.lowerBound
    let pos3 = assembled.range(of: "CONTENT-003")!.lowerBound

    #expect(pos1 < pos2)
    #expect(pos2 < pos3)

    #expect(!assembled.contains("SHOULD-BE-SKIPPED"))
    #expect(!assembled.contains("LEGACY"))
}

@Test func singleFileInputMode() async throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-test-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    try "ONLY-THIS".write(to: tmp.appendingPathComponent("specific.md"), atomically: true, encoding: .utf8)
    try "OTHER".write(to: tmp.appendingPathComponent("other.md"), atomically: true, encoding: .utf8)

    let assembled = try DocumentGenerator.assembleSources(input: "specific.md", baseDirectory: tmp.path)
    #expect(assembled.contains("ONLY-THIS"))
    #expect(!assembled.contains("OTHER"))
}

// MARK: - Config & project (#7)

@Test func configParsesFullYAML() throws {
    let yaml = """
    version: 1
    project:
      title: My Spec
      author: Ada
    build:
      default_input: "welcome-template.md"
      output: "dist/docs.html"
      css: "assets/theme.css"
      diagrams_enabled: false
      diagrams_dir: "pics"
    decision_records:
      adrs_enabled: true
      bdrs_enabled: false
    ids:
      auto_assign: true
    """
    let config = try SpecticusConfig.parse(yaml: yaml)
    #expect(config.version == 1)
    #expect(config.project.title == "My Spec")
    #expect(config.project.author == "Ada")
    #expect(config.build.defaultInput == "welcome-template.md")
    #expect(config.build.output == "dist/docs.html")
    #expect(config.build.css == "assets/theme.css")
    #expect(config.build.diagramsEnabled == false)
    #expect(config.build.diagramsDir == "pics")
    #expect(config.decisionRecords.adrsEnabled == true)
    #expect(config.decisionRecords.bdrsEnabled == false)
    #expect(config.ids.autoAssign == true)
}

@Test func configPartialYAMLUsesDefaults() throws {
    let yaml = """
    version: 1
    project:
      title: Partial
    build:
      output: "custom.html"
    """
    let config = try SpecticusConfig.parse(yaml: yaml)
    #expect(config.project.title == "Partial")
    #expect(config.build.output == "custom.html")
    #expect(config.build.css == "style.css")
    #expect(config.build.diagramsEnabled == true)
    #expect(config.build.diagramsDir == "diagrams")
    #expect(config.ids.autoAssign == false)
}

@Test func projectLoadUsesConfigAndTitle() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-proj-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)

    let configYAML = """
    version: 1
    project:
      title: FromConfig
    build:
      output: "build/out.html"
      css: "theme.css"
    """
    try configYAML.write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let titleYAML = """
    title: "From Title YML"
    author: "Tester"
    version: "1.0.0"
    """
    try titleYAML.write(to: tmp.appendingPathComponent("title.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    #expect(project.configSource == .file)
    #expect(project.config.build.output == "build/out.html")
    #expect(project.config.build.css == "theme.css")
    #expect(project.documentTitle == "From Title YML")
    #expect(project.titleMetadata?.author == "Tester")
    #expect(project.hasConfigFile)
    #expect(project.hasSpecticusDirectory)
}

@Test func projectLoadFallsBackToDefaultsWithoutConfig() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-legacy-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let project = try SpecticusProject.load(from: tmp.path)
    #expect(project.configSource == .defaults)
    #expect(project.config.build.output == "output.html")
    #expect(project.config.build.trackBuilds == true)
    #expect(project.documentTitle == "specticus • Documentation")
}

@Test func projectLoadRejectsInvalidConfig() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-bad-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    // Invalid YAML structure for our model: version as a nested map won't decode as Int
    try "version: { nested: true }\n".write(
        to: specticusDir.appendingPathComponent("config.yml"),
        atomically: true,
        encoding: .utf8
    )

    #expect(throws: (any Error).self) {
        try SpecticusProject.load(from: tmp.path)
    }
}

@Test func assembleUsesConfigFallbackInput() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-fallback-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    try "FALLBACK-CONTENT".write(to: tmp.appendingPathComponent("main.md"), atomically: true, encoding: .utf8)
    // No numbered sections — only main.md which is not welcome-template

    // Without fallback, main.md is discovered as a normal md file
    let withDiscovery = try DocumentGenerator.assembleSources(input: nil, baseDirectory: tmp.path)
    #expect(withDiscovery.contains("FALLBACK-CONTENT"))

    // Empty of all md except a custom fallback file (remove main, add only custom)
    try fm.removeItem(at: tmp.appendingPathComponent("main.md"))
    try "CUSTOM-ONLY".write(to: tmp.appendingPathComponent("custom-source.md"), atomically: true, encoding: .utf8)

    // custom-source.md is still a discoverable .md, so multi-file uses it
    let discovered = try DocumentGenerator.assembleSources(
        input: nil,
        baseDirectory: tmp.path,
        fallbackInput: "custom-source.md"
    )
    #expect(discovered.contains("CUSTOM-ONLY"))

    // When only non-md files exist, fallbackInput is used
    try fm.removeItem(at: tmp.appendingPathComponent("custom-source.md"))
    try "FROM-FALLBACK".write(to: tmp.appendingPathComponent("solo.md"), atomically: true, encoding: .utf8)
    // Hide from multi-file by naming as welcome path... use fallback when zero md except we need zero md
    try fm.removeItem(at: tmp.appendingPathComponent("solo.md"))
    try "ONLY-FALLBACK".write(to: tmp.appendingPathComponent("entry.md"), atomically: true, encoding: .utf8)
    // entry.md will be discovered. Create a dir with only a non-standard name used solely as fallback:
    // Put content only in a file that assembly skips: welcome-template is skipped in multi-file
    try fm.removeItem(at: tmp.appendingPathComponent("entry.md"))
    try "WELCOME-SKIPPED-IN-MULTI".write(to: tmp.appendingPathComponent("welcome-template.md"), atomically: true, encoding: .utf8)
    try "ALT-FALLBACK".write(to: tmp.appendingPathComponent("alt.md"), atomically: true, encoding: .utf8)

    // alt.md is discovered — multi-file wins over fallback
    let multiWins = try DocumentGenerator.assembleSources(
        input: nil,
        baseDirectory: tmp.path,
        fallbackInput: "alt.md"
    )
    #expect(multiWins.contains("ALT-FALLBACK"))
    #expect(!multiWins.contains("WELCOME-SKIPPED-IN-MULTI"))

    // Only welcome-template (skipped in multi) → fallbackInput if set and exists, else welcome
    try fm.removeItem(at: tmp.appendingPathComponent("alt.md"))
    let onlyLegacy = try DocumentGenerator.assembleSources(
        input: nil,
        baseDirectory: tmp.path,
        fallbackInput: "welcome-template.md"
    )
    #expect(onlyLegacy.contains("WELCOME-SKIPPED-IN-MULTI"))
}

@Test func generateHTMLUsesTitleAndStylesheet() throws {
    let html = try DocumentGenerator.generateHTML(
        from: "# Hello",
        title: "My Doc <Title>",
        stylesheet: "css/app.css"
    )
    #expect(html.contains("<title>My Doc &lt;Title&gt;</title>"))
    #expect(html.contains("href=\"css/app.css\""))
    #expect(html.contains("Hello"))
}

@Test func assembleIgnoresHiddenSpecticusDirectory() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-hidden-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    try "VISIBLE".write(to: tmp.appendingPathComponent("001-main.md"), atomically: true, encoding: .utf8)
    let hidden = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: hidden, withIntermediateDirectories: true)
    try "SHOULD-NOT-APPEAR".write(to: hidden.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

    let assembled = try DocumentGenerator.assembleSources(input: nil, baseDirectory: tmp.path)
    #expect(assembled.contains("VISIBLE"))
    #expect(!assembled.contains("SHOULD-NOT-APPEAR"))
}

// MARK: - Build tracking (#8)

@Test func buildTrackerIncrementsAndPersists() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-buildtrack-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp.appendingPathComponent(".specticus"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let url = tmp.appendingPathComponent(".specticus/build-number.yml")
    let fixed = Date(timeIntervalSince1970: 1_720_000_000) // fixed for determinism

    let first = try BuildTracker.incrementAndSave(at: url, now: fixed)
    #expect(first.number == 1)
    #expect(!first.lastBuilt.isEmpty)
    #expect(fm.fileExists(atPath: url.path))

    let second = try BuildTracker.incrementAndSave(at: url, now: fixed.addingTimeInterval(60))
    #expect(second.number == 2)

    let loaded = try BuildTracker.load(from: url)
    #expect(loaded?.number == 2)
    #expect(loaded?.lastBuilt == second.lastBuilt)
}

@Test func buildRecordDisplayLineIncludesNumberAndDate() {
    let record = BuildRecord(number: 7, lastBuilt: "2026-07-09T21:08:00Z")
    let line = record.displayLine
    #expect(line.contains("build 7"))
    #expect(line.contains("2026-07-09"))
    #expect(line.contains("Generated on"))
}

@Test func generateHTMLIncludesBuildFooterWhenProvided() throws {
    let record = BuildRecord(number: 3, lastBuilt: "2026-07-09T12:00:00Z")
    let html = try DocumentGenerator.generateHTML(
        from: "# Hi",
        title: "Doc",
        stylesheet: "style.css",
        buildInfo: record
    )
    #expect(html.contains("site-footer"))
    #expect(html.contains("build 3"))
    #expect(html.contains("Generated on"))
}

@Test func generateHTMLOmitsFooterWithoutBuildInfo() throws {
    let html = try DocumentGenerator.generateHTML(from: "# Hi", title: "Doc")
    #expect(!html.contains("site-footer"))
}

@Test func configParsesTrackBuilds() throws {
    let yaml = """
    build:
      track_builds: false
    """
    let config = try SpecticusConfig.parse(yaml: yaml)
    #expect(config.build.trackBuilds == false)
}
