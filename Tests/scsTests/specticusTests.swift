import Testing
import Foundation
@testable import scs

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
      heading_max_level: 4
      drift_sensitivity: contentStrict
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
    #expect(config.ids.headingMaxLevel == 4)
    #expect(config.ids.driftSensitivity == .contentStrict)
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
    #expect(config.ids.headingMaxLevel == SpecticusConfig.IdsSection.defaultHeadingMaxLevel)
    #expect(config.ids.headingMaxLevel == 2)
    #expect(config.ids.driftSensitivity == .strict)
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
    #expect(project.config.build.output == "output/index.html")
    #expect(project.config.build.copyAssets == true)
    #expect(project.config.build.trackBuilds == true)
    #expect(project.config.build.headingNumberMaxLevel == 3)
    #expect(project.config.build.tocEnabled == true)
    #expect(project.config.build.tocMaxLevel == 3)
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

// MARK: - Structured output & assets (#9)

@Test func resourcePublisherCopiesCSSAndImages() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-assets-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    try "body{color:red}".write(to: tmp.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tmp.appendingPathComponent("logo.png")) // tiny fake PNG header
    try fm.createDirectory(at: tmp.appendingPathComponent("images"), withIntermediateDirectories: true)
    try Data([0x47, 0x49, 0x46]).write(to: tmp.appendingPathComponent("images/chart.gif"))
    try fm.createDirectory(at: tmp.appendingPathComponent("diagrams"), withIntermediateDirectories: true)
    try "<svg/>".write(to: tmp.appendingPathComponent("diagrams/flow.svg"), atomically: true, encoding: .utf8)

    let result = try ResourcePublisher.publish(
        projectRoot: tmp,
        outputHTMLPath: "output/index.html",
        sourceCSS: "style.css",
        diagramsDir: "diagrams",
        copyAssets: true
    )

    #expect(result.stylesheetHref == "css/style.css")
    #expect(fm.fileExists(atPath: tmp.appendingPathComponent("output/css/style.css").path))
    #expect(fm.fileExists(atPath: tmp.appendingPathComponent("output/img/logo.png").path))
    #expect(fm.fileExists(atPath: tmp.appendingPathComponent("output/img/chart.gif").path))
    #expect(fm.fileExists(atPath: tmp.appendingPathComponent("output/svg/flow.svg").path))

    #expect(result.pathRewrites["logo.png"] == "img/logo.png")
    #expect(result.pathRewrites["images/chart.gif"] == "img/chart.gif" || result.pathRewrites["chart.gif"] == "img/chart.gif")
    #expect(result.pathRewrites["diagrams/flow.svg"] == "svg/flow.svg" || result.pathRewrites["flow.svg"] == "svg/flow.svg")
}

@Test func rewriteReferencesUpdatesImgAndHref() {
    let html = #"""
    <img src="logo.png" alt="L">
    <img src='images/chart.gif'>
    <a href="diagrams/flow.svg">flow</a>
    <link rel="stylesheet" href="style.css">
    """#
    let rewrites = [
        "logo.png": "img/logo.png",
        "images/chart.gif": "img/chart.gif",
        "diagrams/flow.svg": "svg/flow.svg",
        "style.css": "css/style.css"
    ]
    let out = ResourcePublisher.rewriteReferences(in: html, rewrites: rewrites)
    #expect(out.contains(#"src="img/logo.png""#))
    #expect(out.contains("src='img/chart.gif'"))
    #expect(out.contains(#"href="svg/flow.svg""#))
    #expect(out.contains(#"href="css/style.css""#))
    #expect(!out.contains(#"src="logo.png""#))
}

@Test func publishSkipsAssetsWhenDisabled() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-noassets-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    try "body{}".write(to: tmp.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
    try Data([0x89]).write(to: tmp.appendingPathComponent("logo.png"))

    let result = try ResourcePublisher.publish(
        projectRoot: tmp,
        outputHTMLPath: "output/index.html",
        sourceCSS: "style.css",
        diagramsDir: "diagrams",
        copyAssets: false
    )

    #expect(result.stylesheetHref == "style.css")
    #expect(result.copiedDescriptions.isEmpty)
    #expect(!fm.fileExists(atPath: tmp.appendingPathComponent("output/css/style.css").path))
}

@Test func cleanableOutputDirectoryForStructuredPath() {
    let root = URL(fileURLWithPath: "/tmp/proj", isDirectory: true)
    let dir = ResourcePublisher.cleanableOutputDirectory(outputHTMLPath: "output/index.html", projectRoot: root)
    #expect(dir?.lastPathComponent == "output")

    let flat = ResourcePublisher.cleanableOutputDirectory(outputHTMLPath: "output.html", projectRoot: root)
    #expect(flat == nil)

    let dist = ResourcePublisher.cleanableOutputDirectory(outputHTMLPath: "dist/docs.html", projectRoot: root)
    #expect(dist?.lastPathComponent == "dist")
}

@Test func configParsesCopyAssets() throws {
    let yaml = """
    build:
      copy_assets: false
      output: "site/index.html"
    """
    let config = try SpecticusConfig.parse(yaml: yaml)
    #expect(config.build.copyAssets == false)
    #expect(config.build.output == "site/index.html")
}

@Test func endToEndBuildTreeHasWorkingCSSLink() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-e2e-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    try "# Hello\n\n![Logo](logo.png)\n".write(to: tmp.appendingPathComponent("001-intro.md"), atomically: true, encoding: .utf8)
    try "body { font-family: sans-serif; }".write(to: tmp.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tmp.appendingPathComponent("logo.png"))

    let publish = try ResourcePublisher.publish(
        projectRoot: tmp,
        outputHTMLPath: "output/index.html",
        sourceCSS: "style.css",
        diagramsDir: "diagrams",
        copyAssets: true
    )
    let record = BuildRecord(number: 1, lastBuilt: "2026-07-10T00:00:00Z")
    var html = try DocumentGenerator.generateHTML(
        from: try DocumentGenerator.assembleSources(input: nil, baseDirectory: tmp.path),
        title: "E2E",
        stylesheet: publish.stylesheetHref,
        buildInfo: record
    )
    html = ResourcePublisher.rewriteReferences(in: html, rewrites: publish.pathRewrites)
    try DocumentGenerator.writeOutput(html, to: tmp.appendingPathComponent("output/index.html").path)

    let written = try String(contentsOf: tmp.appendingPathComponent("output/index.html"), encoding: .utf8)
    #expect(written.contains(#"href="css/style.css""#))
    #expect(written.contains(#"src="img/logo.png""#) || written.contains("img/logo.png"))
    #expect(written.contains("site-footer"))
    #expect(written.contains("build 1"))
    #expect(fm.fileExists(atPath: tmp.appendingPathComponent("output/css/style.css").path))
    #expect(fm.fileExists(atPath: tmp.appendingPathComponent("output/img/logo.png").path))
}

@Test func numberedMarkdownRendersInHTML() throws {
    let md = """
    # Doc
    ## BR7: The system shall
    """
    let numbered = HeadingNumberer.numberHeadings(in: md, maxLevel: 3)
    let html = try DocumentGenerator.generateHTML(from: numbered, title: "T", tocMaxLevel: 0)
    #expect(html.contains("1. Doc") || html.contains("1. Doc"))
    #expect(html.contains("BR7"))
    #expect(html.contains("1.1.") || html.contains("1.1. The system shall"))
    // Owning ID demoted to chip — not left as `BR7:` inside the heading (#149)
    #expect(html.contains("class=\"scs-id-chip\""))
    #expect(!html.contains(">1.1. BR7:"))
}

// MARK: - Traceability chips (#149 / #42)

@Test func traceabilityChipsPartsSplitOutlineAndID() {
    let withBoth = TraceabilityChips.parts(from: "1.1. BR1: User Login")
    #expect(withBoth.outlinePrefix == "1.1. ")
    #expect(withBoth.owningID == "BR1")
    #expect(withBoth.titleText == "User Login")
    #expect(withBoth.visibleHeadingText == "1.1. User Login")

    let idOnly = TraceabilityChips.parts(from: "BR2: Dashboard")
    #expect(idOnly.outlinePrefix.isEmpty)
    #expect(idOnly.owningID == "BR2")
    #expect(idOnly.titleText == "Dashboard")

    let plain = TraceabilityChips.parts(from: "1.2. Overview")
    #expect(plain.owningID == nil)
    #expect(plain.visibleHeadingText == "1.2. Overview")
}

@Test func traceabilityChipsDemoteInHTML() throws {
    let md = """
    # Requirements
    ## BR1: User Login
    ## Plain Section
    The user shall reference BR1 in prose without a chip.
    """
    let numbered = HeadingNumberer.numberHeadings(in: md, maxLevel: 3)
    let html = try DocumentGenerator.generateHTML(from: numbered, title: "T", tocMaxLevel: 3)

    #expect(html.contains("data-scs-id=\"BR1\""))
    #expect(html.contains("class=\"scs-id-chip\""))
    #expect(html.contains("<span class=\"scs-id\">BR1</span>"))
    #expect(html.contains(">1.1. User Login</h2>"))
    #expect(!html.contains("BR1: User Login"))
    #expect(html.contains("id=\"br1\""))
    // TOC: human title only (no owning-ID prefix in the link label)
    #expect(html.contains("class=\"toc\""))
    #expect(html.contains("href=\"#br1\">1.1. User Login</a>")
            || html.contains("href=\"#br1\">User Login</a>"))
    #expect(!html.contains("href=\"#br1\">BR1:"))
    #expect(!html.contains("href=\"#br1\">1.1. BR1"))
    // Body mention stays prose (not wrapped in a chip)
    #expect(html.contains("reference BR1 in prose"))
    #expect(html.contains("Plain Section"))
}

@Test func traceabilityChipsPreferIDAnchorAndCleanTOC() {
    let md = """
    ## BR9: Authentication
    ## No ID Here
    """
    let headings = TableOfContents.extractHeadings(from: md, maxLevel: 3)
    #expect(headings.count == 2)
    #expect(headings[0].text == "Authentication")
    #expect(headings[0].id == "br9")
    #expect(headings[1].text == "No ID Here")
    #expect(headings[1].id != "br9")
}

// MARK: - Shared Markdown discovery (#35)

@Test func markdownSourcesDiscoverContentFilesLexOrderAndFilters() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-md-sources-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    try "C".write(to: tmp.appendingPathComponent("003-z.md"), atomically: true, encoding: .utf8)
    try "A".write(to: tmp.appendingPathComponent("001-a.md"), atomically: true, encoding: .utf8)
    try "B".write(to: tmp.appendingPathComponent("002-b.markdown"), atomically: true, encoding: .utf8)
    try "SKIP".write(to: tmp.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    try "SKIP2".write(to: tmp.appendingPathComponent("welcome-template.md"), atomically: true, encoding: .utf8)
    try "NOTMD".write(to: tmp.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

    // Hidden dir content must not appear (skipsHiddenFiles)
    let hidden = tmp.appendingPathComponent(".specticus", isDirectory: true)
    try fm.createDirectory(at: hidden, withIntermediateDirectories: true)
    try "HIDDEN".write(to: hidden.appendingPathComponent("secret.md"), atomically: true, encoding: .utf8)

    let files = try MarkdownSources.discoverContentFiles(in: tmp)
    let names = files.map(\.lastPathComponent)
    #expect(names == ["001-a.md", "002-b.markdown", "003-z.md"])
    #expect(MarkdownSources.isContentMarkdownFilename("007-business-requirements.md"))
    #expect(!MarkdownSources.isContentMarkdownFilename("README.md"))
    #expect(!MarkdownSources.isContentMarkdownFilename("welcome-template.md"))
    #expect(!MarkdownSources.isContentMarkdownFilename("style.css"))
}


// MARK: - Open command (#122)

@Test func openResolvedPathPrefersCLIOverride() {
    let path = OpenHTML.resolvedRelativePath(
        outputOverride: "custom/out.html",
        defaultOutput: "output/index.html"
    )
    #expect(path == "custom/out.html")
}

@Test func openResolvedPathUsesDefaultWhenOverrideNil() {
    let path = OpenHTML.resolvedRelativePath(
        outputOverride: nil,
        defaultOutput: "output/index.html"
    )
    #expect(path == "output/index.html")
}

@Test func openResolvedPathTreatsEmptyOverrideAsDefault() {
    let path = OpenHTML.resolvedRelativePath(
        outputOverride: "",
        defaultOutput: "dist/docs.html"
    )
    #expect(path == "dist/docs.html")
}

@Test func openRequireExistingFileAcceptsPresentFile() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-open-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let html = tmp.appendingPathComponent("index.html")
    try "<html></html>".write(to: html, atomically: true, encoding: .utf8)

    try OpenHTML.requireExistingFile(at: html, displayPath: "index.html")
}

@Test func openRequireExistingFileRejectsMissingFile() {
    let missing = URL(fileURLWithPath: "/tmp/specticus-does-not-exist-\(UUID().uuidString).html")
    do {
        try OpenHTML.requireExistingFile(at: missing, displayPath: "output/index.html")
        Issue.record("Expected error for missing HTML")
    } catch {
        let message = String(describing: error)
        #expect(message.contains("scs build") || message.contains("not found"))
    }
}

@Test func openRequireExistingFileRejectsDirectory() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-open-dir-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    do {
        try OpenHTML.requireExistingFile(at: tmp, displayPath: "output")
        Issue.record("Expected error for directory path")
    } catch {
        #expect(String(describing: error).contains("directory"))
    }
}

@Test func openLaunchSpecIsPlatformAppropriate() throws {
    let (executable, args) = try SystemBrowser.launchSpec(for: "/tmp/example.html")
    #expect(args.contains("/tmp/example.html"))
    #if os(macOS)
    #expect(executable == "/usr/bin/open")
    #elseif os(Windows)
    #expect(executable == "cmd.exe")
    #else
    #expect(executable.contains("xdg-open"))
    #endif
}

// MARK: - Brand chrome (#135)

@Test func brandVersionIsSemver() {
    #expect(Brand.version.contains("."))
    #expect(!Brand.version.isEmpty)
}

@Test func brandWordmarkContainsSpecticusShape() {
    let mark = Brand.wordmark
    #expect(mark.contains("_"))
    #expect(mark.contains("|"))
    #expect(mark.split(separator: "\n").count >= 5)
    #expect(!mark.hasSuffix(" "))
}

@Test func brandRootVersionInvocationDetection() {
    #expect(Brand.isRootVersionInvocation(arguments: ["scs", "--version"]))
    #expect(!Brand.isRootVersionInvocation(arguments: ["scs", "build", "--version"]))
    #expect(!Brand.isRootVersionInvocation(arguments: ["scs", "--help"]))
}

@Test func brandHelpInvocationDetection() {
    #expect(Brand.isHelpInvocation(arguments: ["scs", "--help"]))
    #expect(Brand.isHelpInvocation(arguments: ["scs", "-h"]))
    #expect(Brand.isHelpInvocation(arguments: ["scs", "help"]))
    #expect(Brand.isHelpInvocation(arguments: ["scs", "build", "--help"]))
    #expect(!Brand.isHelpInvocation(arguments: ["scs", "build"]))
}

// MARK: - Vertical template sections (#139)

@Test func templateSectionsDefaultOrderIncludesRequiredVerticals() {
    let ids = Set(TemplateSections.defaultOrder)
    for required in [
        "document-metadata", "business-requirements", "technical-specifications",
        "business-glossary", "technical-glossary", "business-notes", "technical-notes",
        "quality-attributes", "external-interfaces", "appendices", "ADRs", "BDRs",
        "assumptions-and-open-questions", "stakeholders-and-scope"
    ] {
        #expect(ids.contains(required))
    }
    #expect(!ids.contains("glossary"))
    #expect(!ids.contains("non-functional-requirements"))
    #expect(TemplateSections.decisionStatusFolders.contains("rejected"))
}

@Test func discoverContentFilesVerticalLayoutOrdersSectionsAndNests() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-vertical-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    // Create two sections out of narrative order on disk; discovery must follow TemplateSections.defaultOrder
    let tech = tmp.appendingPathComponent("technical-specifications/login-screen", isDirectory: true)
    let biz = tmp.appendingPathComponent("business-requirements", isDirectory: true)
    try fm.createDirectory(at: tech, withIntermediateDirectories: true)
    try fm.createDirectory(at: biz, withIntermediateDirectories: true)
    try "# TS nested".write(to: tech.appendingPathComponent("010-auth.md"), atomically: true, encoding: .utf8)
    try "# TS root".write(
        to: tmp.appendingPathComponent("technical-specifications/001-overview.md"),
        atomically: true,
        encoding: .utf8
    )
    try "# BR".write(to: biz.appendingPathComponent("001-reqs.md"), atomically: true, encoding: .utf8)
    try "# Skip".write(to: biz.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

    #expect(TemplateSections.usesVerticalLayout(at: tmp))

    let files = try MarkdownSources.discoverContentFiles(in: tmp)
    let rels = files.map { url -> String in
        let path = url.path
        let root = tmp.path + "/"
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : url.lastPathComponent
    }

    #expect(rels.contains("business-requirements/001-reqs.md"))
    #expect(rels.contains("technical-specifications/001-overview.md"))
    #expect(rels.contains("technical-specifications/login-screen/010-auth.md"))
    #expect(!rels.contains { $0.lowercased().contains("readme") })

    // business-requirements comes before technical-specifications in defaultOrder
    let bizIdx = rels.firstIndex(of: "business-requirements/001-reqs.md")!
    let techIdx = rels.firstIndex(of: "technical-specifications/001-overview.md")!
    #expect(bizIdx < techIdx)

    // Within technical-specifications, lex by relative path: 001-overview before login-screen/010-auth
    let overviewIdx = rels.firstIndex(of: "technical-specifications/001-overview.md")!
    let nestedIdx = rels.firstIndex(of: "technical-specifications/login-screen/010-auth.md")!
    #expect(overviewIdx < nestedIdx)
}

@Test func discoverContentFilesFlatLayoutStillWorks() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-flat-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    try "# A".write(to: tmp.appendingPathComponent("002-b.md"), atomically: true, encoding: .utf8)
    try "# B".write(to: tmp.appendingPathComponent("001-a.md"), atomically: true, encoding: .utf8)
    try "# Skip".write(to: tmp.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

    #expect(!TemplateSections.usesVerticalLayout(at: tmp))
    let files = try MarkdownSources.discoverContentFiles(in: tmp)
    #expect(files.map(\.lastPathComponent) == ["001-a.md", "002-b.md"])
}

@Test func defaultSkeletonOnDiskUsesVerticalFoldersAndRejected() throws {
    // Resolve repo Skeleton via this test file path (resources live with Sources, not in test bundle).
    let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let skeleton = testsDir
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
        .appendingPathComponent("Sources/scs/Resources/Skeleton", isDirectory: true)

    let fm = FileManager.default
    var isDir: ObjCBool = false
    #expect(fm.fileExists(atPath: skeleton.path, isDirectory: &isDir) && isDir.boolValue)

    #expect(TemplateSections.usesVerticalLayout(at: skeleton))
    for id in [
        "business-requirements", "technical-glossary", "business-glossary",
        "document-metadata", "appendices", "quality-attributes",
        "external-interfaces", "technical-notes", "business-notes"
    ] {
        var sectionIsDir: ObjCBool = false
        #expect(
            fm.fileExists(atPath: skeleton.appendingPathComponent(id).path, isDirectory: &sectionIsDir)
                && sectionIsDir.boolValue
        )
    }
    #expect(fm.fileExists(atPath: skeleton.appendingPathComponent("document-metadata/document-revisions/001-revision-history.md").path))
    #expect(fm.fileExists(atPath: skeleton.appendingPathComponent("appendices/tech-specs-to-business-reqs/001-tech-specs-to-business-reqs.md").path))
    #expect(fm.fileExists(atPath: skeleton.appendingPathComponent("ADRs/000-adrs.md").path))
    #expect(fm.fileExists(atPath: skeleton.appendingPathComponent("ADRs/rejected").path))
    #expect(fm.fileExists(atPath: skeleton.appendingPathComponent("BDRs/rejected").path))
    #expect(!fm.fileExists(atPath: skeleton.appendingPathComponent("001-document-metadata.md").path))

    let files = try MarkdownSources.discoverContentFiles(in: skeleton)
    #expect(files.count >= 15)
    #expect(files.contains { $0.path.contains("business-requirements") })
    #expect(files.contains { $0.path.hasSuffix("ADRs/000-adrs.md") })
}

// MARK: - Assembly layout (#140)

@Test func alphanumericSortPutsNineBeforeTen() {
    #expect(AssemblyLayout.compareAlphanumeric("section/9-x.md", "section/10-x.md"))
    #expect(!AssemblyLayout.compareAlphanumeric("section/10-x.md", "section/9-x.md"))
    #expect(AssemblyLayout.comparePaths("a/9-b.md", "a/10-b.md", policy: .alphanumeric))
    #expect(AssemblyLayout.comparePaths("b.md", "a.md", policy: .reverseLexical))
    #expect(AssemblyLayout.comparePaths("a.md", "b.md", policy: .lexical))
}

@Test func assemblyLayoutMergeOverridesOrderAndSort() {
    let base = AssemblyLayout.packDefault
    let merged = AssemblyLayout.merge(
        base: base,
        overrides: [
            AssemblySectionSpec(id: "appendices", order: -10, sort: .reverseLexical),
            AssemblySectionSpec(id: "custom-vertical", order: -5, sort: .lexical),
        ]
    )
    #expect(merged.orderedSectionIDs.first == "appendices")
    #expect(merged.sortPolicy(forSectionID: "appendices") == .reverseLexical)
    #expect(merged.orderedSectionIDs.contains("custom-vertical"))
    #expect(merged.unknownSectionIDs.contains("custom-vertical"))
}

@Test func loadMergedUsesLayoutFileAsCompleteSectionMap() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-layout-complete-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let layoutURL = tmp.appendingPathComponent("layout.yml")
    try """
    sections:
      - id: document-metadata
        order: 0
        sort: alphanumeric
      - id: business-requirements
        order: 10
        sort: lexical
    """.write(to: layoutURL, atomically: true, encoding: .utf8)

    let layout = AssemblyLayout.loadMerged(layoutFileURL: layoutURL, configOverrides: [])
    #expect(layout.orderedSectionIDs == ["document-metadata", "business-requirements"])
    #expect(!layout.orderedSectionIDs.contains("technical-specifications"))
    #expect(layout.sortPolicy(forSectionID: "business-requirements") == .lexical)
}

@Test func assemblyLayoutParsesFromConfigYAML() throws {
    let yaml = """
    version: 1
    assembly:
      sections:
        - id: technical-specifications
          order: 0
          sort: reverse_lexical
        - id: business-requirements
          order: 10
          sort: alphanumeric
    """
    let config = try SpecticusConfig.parse(yaml: yaml)
    #expect(config.assembly.sections.count == 2)
    #expect(config.assembly.sections[0].id == "technical-specifications")
    #expect(config.assembly.sections[0].sort == .reverseLexical)
}

@Test func discoverRespectsSectionOrderOverride() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-layout-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let tech = tmp.appendingPathComponent("technical-specifications", isDirectory: true)
    let biz = tmp.appendingPathComponent("business-requirements", isDirectory: true)
    try fm.createDirectory(at: tech, withIntermediateDirectories: true)
    try fm.createDirectory(at: biz, withIntermediateDirectories: true)
    try "# TS".write(to: tech.appendingPathComponent("001.md"), atomically: true, encoding: .utf8)
    try "# BR".write(to: biz.appendingPathComponent("001.md"), atomically: true, encoding: .utf8)

    let layout = AssemblyLayout(sections: [
        AssemblySectionSpec(id: "technical-specifications", order: 0, sort: .alphanumeric),
        AssemblySectionSpec(id: "business-requirements", order: 10, sort: .alphanumeric),
    ])
    let files = try MarkdownSources.discoverContentFiles(in: tmp, layout: layout)
    let rels = files.map { $0.path.replacingOccurrences(of: tmp.path + "/", with: "") }
    #expect(rels.first == "technical-specifications/001.md")
    #expect(rels.contains("business-requirements/001.md"))
}

@Test func discoverAlphanumericWithinSection() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-alnum-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let tech = tmp.appendingPathComponent("technical-specifications", isDirectory: true)
    try fm.createDirectory(at: tech, withIntermediateDirectories: true)
    try "# 10".write(to: tech.appendingPathComponent("10-later.md"), atomically: true, encoding: .utf8)
    try "# 9".write(to: tech.appendingPathComponent("9-earlier.md"), atomically: true, encoding: .utf8)

    let layout = AssemblyLayout(sections: [
        AssemblySectionSpec(id: "technical-specifications", order: 0, sort: .alphanumeric),
    ])
    let files = try MarkdownSources.discoverContentFiles(in: tmp, layout: layout)
    let names = files.map(\.lastPathComponent)
    #expect(names == ["9-earlier.md", "10-later.md"])
}


// MARK: - Style packs (#141)

@Test func stylePackRegistryIncludesDefaultAndMinimal() throws {
    #expect(StylePackRegistry.pack(id: "default") != nil)
    #expect(StylePackRegistry.pack(id: "DEFAULT")?.id == "default")
    #expect(StylePackRegistry.pack(id: "minimal")?.id == "minimal")
    #expect(StylePackRegistry.pack(id: "nope") == nil)
    let def = try StylePackRegistry.skeletonURL(forPackID: "default")
    #expect(def.lastPathComponent == "Skeleton" || def.path.contains("Skeleton"))
    let min = try StylePackRegistry.skeletonURL(forPackID: "minimal")
    #expect(min.lastPathComponent == "minimal" || min.path.contains("Styles"))
    #expect(StylePackRegistry.helpListing.contains("default"))
    #expect(StylePackRegistry.helpListing.contains("minimal"))
}

@Test func unknownStyleDiagnostic() {
    #expect(StylePackRegistry.unknownStyleDiagnostic("default") == nil)
    #expect(StylePackRegistry.unknownStyleDiagnostic("minimal") == nil)
    #expect(StylePackRegistry.unknownStyleDiagnostic("ieee-official") != nil)
}

@Test func configParsesDocStyle() throws {
    let yaml = """
    version: 1
    doc:
      style: default
    """
    let config = try SpecticusConfig.parse(yaml: yaml)
    #expect(config.doc.style == "default")
}

@Test func configDefaultsDocStyleWhenMissing() throws {
    let yaml = "version: 1\n"
    let config = try SpecticusConfig.parse(yaml: yaml)
    #expect(config.doc.style == StylePackRegistry.defaultPackID)
}

@Test func initMinimalStylePackScaffoldsSubset() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-init-minimal-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: tmp) }

    var cmd = Init()
    cmd.directory = tmp.path
    cmd.style = "minimal"
    try cmd.run()

    #expect(fm.fileExists(atPath: tmp.appendingPathComponent("business-requirements").path))
    #expect(fm.fileExists(atPath: tmp.appendingPathComponent("ADRs/rejected").path))
    #expect(!fm.fileExists(atPath: tmp.appendingPathComponent("technical-specifications").path))
    #expect(!fm.fileExists(atPath: tmp.appendingPathComponent("BDRs").path))

    let configText = try String(
        contentsOf: tmp.appendingPathComponent(".specticus/config.yml"),
        encoding: .utf8
    )
    #expect(configText.contains("style: \"minimal\"") || configText.contains("style: minimal"))

    let project = try SpecticusProject.load(from: tmp.path)
    #expect(project.config.doc.style == "minimal")
    #expect(project.assemblyLayout.orderedSectionIDs == [
        "document-metadata",
        "system-overview",
        "business-requirements",
        "diagrams",
        "ADRs",
    ])
    #expect(StylePackRegistry.unknownStyleDiagnostic(project.config.doc.style) == nil)
}

@Test func initUnknownStyleThrows() throws {
    var cmd = Init()
    cmd.directory = "/tmp/specticus-should-not-exist-\(UUID().uuidString)"
    cmd.style = "not-a-real-pack"
    #expect(throws: (any Error).self) {
        try cmd.run()
    }
}

// MARK: - GFM export (#5)

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
