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

// MARK: - Heading auto-numbering (#4)

@Test func headingNumbererDefaultsToLevel3() {
    let md = """
    # Alpha
    ## Beta
    ### Gamma
    #### Delta
    ## Epsilon
    """
    let out = HeadingNumberer.numberHeadings(in: md, maxLevel: 3)
    #expect(out.contains("# 1. Alpha"))
    #expect(out.contains("## 1.1. Beta"))
    #expect(out.contains("### 1.1.1. Gamma"))
    #expect(out.contains("#### Delta")) // level 4 not numbered
    #expect(!out.contains("#### 1."))
    #expect(out.contains("## 1.2. Epsilon"))
}

@Test func headingNumbererCanNumberThroughLevel6() {
    let md = """
    # A
    ## B
    ### C
    #### D
    ##### E
    ###### F
    """
    let out = HeadingNumberer.numberHeadings(in: md, maxLevel: 6)
    #expect(out.contains("# 1. A"))
    #expect(out.contains("## 1.1. B"))
    #expect(out.contains("### 1.1.1. C"))
    #expect(out.contains("#### 1.1.1.1. D"))
    #expect(out.contains("##### 1.1.1.1.1. E"))
    #expect(out.contains("###### 1.1.1.1.1.1. F"))
}

@Test func headingNumbererZeroDisables() {
    let md = "# Only\n## Two\n"
    let out = HeadingNumberer.numberHeadings(in: md, maxLevel: 0)
    #expect(out == md)
}

@Test func headingNumbererPreservesTraceabilityIDs() {
    // Outline numbers are presentation-only; BRx/TSx IDs must remain intact (#4 disjoint from #6).
    let md = """
    # Requirements
    ## BR1: User Login
    ## BR2: View Dashboard
    ### TS10: Login Screen
    """
    let out = HeadingNumberer.numberHeadings(in: md, maxLevel: 3)
    #expect(out.contains("# 1. Requirements"))
    #expect(out.contains("## 1.1. BR1: User Login"))
    #expect(out.contains("## 1.2. BR2: View Dashboard"))
    #expect(out.contains("### 1.2.1. TS10: Login Screen"))
    #expect(out.contains("BR1"))
    #expect(out.contains("BR2"))
    #expect(out.contains("TS10"))
    // Must not invent/replace IDs as section counters
    #expect(!out.contains("BR1."))
}

@Test func headingNumbererSkipsFencedCode() {
    let md = """
    # Intro
    ```
    # not a heading
    ## also not
    ```
    ## Real
    """
    let out = HeadingNumberer.numberHeadings(in: md, maxLevel: 3)
    #expect(out.contains("# 1. Intro"))
    #expect(out.contains("# not a heading"))
    #expect(out.contains("## also not"))
    #expect(out.contains("## 1.1. Real"))
}

@Test func headingNumbererIsIdempotentOnOutlinePrefix() {
    let once = HeadingNumberer.numberHeadings(in: "# Title\n## Sub\n", maxLevel: 3)
    let twice = HeadingNumberer.numberHeadings(in: once, maxLevel: 3)
    #expect(once == twice)
    #expect(twice.contains("# 1. Title"))
    #expect(twice.contains("## 1.1. Sub"))
    #expect(!twice.contains("1. 1. Title"))
}

@Test func headingNumbererClampAndConfig() throws {
    #expect(HeadingNumberer.clampMaxLevel(-1) == 0)
    #expect(HeadingNumberer.clampMaxLevel(99) == 6)
    #expect(HeadingNumberer.clampMaxLevel(3) == 3)

    let yaml = """
    build:
      heading_number_max_level: 5
    """
    let config = try SpecticusConfig.parse(yaml: yaml)
    #expect(config.build.headingNumberMaxLevel == 5)
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
    #expect(html.contains("1.1.") || html.contains("1.1. BR7"))
}

// MARK: - Table of contents (#12)

@Test func tocExtractsHeadingsAndSlugs() {
    let md = """
    # Alpha
    ## Beta
    ### Gamma
    #### Delta
    """
    let headings = TableOfContents.extractHeadings(from: md, maxLevel: 3)
    #expect(headings.count == 4)
    #expect(headings[0].id != nil)
    #expect(headings[1].id != nil)
    #expect(headings[2].id != nil)
    #expect(headings[3].id == nil) // level 4 excluded from TOC
    #expect(TableOfContents.slugify("1. Hello World") == "1-hello-world"
            || TableOfContents.slugify("1. Hello World").contains("hello"))
}

@Test func tocFullPipelineInHTML() throws {
    let md = """
    # Intro
    ## Details
    #### Deep
    """
    let numbered = HeadingNumberer.numberHeadings(in: md, maxLevel: 3)
    let html = try DocumentGenerator.generateHTML(
        from: numbered,
        title: "Spec",
        tocMaxLevel: 3
    )
    #expect(html.contains("class=\"toc\""))
    #expect(html.contains("id=\"toc\""))
    #expect(html.contains("Contents"))
    #expect(html.contains("href=\"#"))
    #expect(html.contains("<h1 id=\""))
    #expect(html.contains("<h2 id=\""))
    // H4 present but no requirement for id when beyond toc max
    #expect(html.contains("<h4") || html.contains("Deep"))
    #expect(html.contains("href=\"#toc\"") || html.contains("Contents"))
}

@Test func tocDisabledProducesNoNav() throws {
    let md = "# Only\n"
    let html = try DocumentGenerator.generateHTML(from: md, title: "T", tocMaxLevel: 0)
    #expect(!html.contains("class=\"toc\""))
}

@Test func tocUniqueSlugsForDuplicates() {
    let md = """
    # Same
    ## Same
    """
    let headings = TableOfContents.extractHeadings(from: md, maxLevel: 3)
    let ids = headings.compactMap(\.id)
    #expect(ids.count == 2)
    #expect(ids[0] != ids[1])
}

@Test func tocSkipsFencedHeadings() {
    let md = """
    # Real
    ```
    # Fake
    ```
    ## Also Real
    """
    let headings = TableOfContents.extractHeadings(from: md, maxLevel: 3)
    #expect(headings.count == 2)
    #expect(headings[0].text == "Real")
    #expect(headings[1].text == "Also Real")
}

@Test func tocConfigKeys() throws {
    let yaml = """
    build:
      toc: false
      toc_max_level: 2
    """
    let config = try SpecticusConfig.parse(yaml: yaml)
    #expect(config.build.tocEnabled == false)
    #expect(config.build.tocMaxLevel == 2)
}

@Test func tocInjectAnchorsOnBodyHTML() {
    let md = """
    # Alpha
    ## Beta
    """
    let headings = TableOfContents.extractHeadings(from: md, maxLevel: 3)
    let body = "<h1>Alpha</h1><p>x</p><h2>Beta</h2>"
    let out = TableOfContents.injectAnchors(into: body, headings: headings)
    #expect(out.contains(#"<h1 id=""#) || out.contains("id=\""))
    #expect(headings[0].id.map { out.contains($0) } ?? false)
    #expect(headings[1].id.map { out.contains($0) } ?? false)
}

// MARK: - Ignore IDs in non-content constructs (#30)

@Test func idsCollectHeadingsSkipsFencedCodeBlocks() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-idfilter-fence-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let content = """
# Real Doc

## BR1: Actual Requirement

Text.

```
## BR99: Example in code fence
```

~~~
### TS77: Another fenced example
~~~

## BR2: Second Real
"""
    try content.write(to: tmp.appendingPathComponent("001-req.md"), atomically: true, encoding: .utf8)

    // Need minimal project structure for load
    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let headings = try IdsManager.collectHeadings(project: project)

    let ids = headings.compactMap { $0.id }
    #expect(ids.contains("BR1"))
    #expect(ids.contains("BR2"))
    #expect(!ids.contains("BR99"))
    #expect(!ids.contains("TS77"))
}

@Test func idsCollectHeadingsSkipsBlockquotes() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-idfilter-bq-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let content = """
# Doc

## BR1: Real Heading

> ## BR42: This is example in blockquote
> Do not assign IDs here.

## BR2: Another Real
"""
    try content.write(to: tmp.appendingPathComponent("002-bq.md"), atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let headings = try IdsManager.collectHeadings(project: project)

    let ids = headings.compactMap { $0.id }
    #expect(ids.contains("BR1"))
    #expect(ids.contains("BR2"))
    #expect(!ids.contains("BR42"))
}

@Test func idsCollectHeadingsSkipsHtmlComments() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-idfilter-comment-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let content = """
# Doc

<!-- 
## BR88: Commented out requirement
-->

## BR1: Visible

<!--
### TS99: Multi-line
comment block
-->

## BR2: Also Visible
"""
    try content.write(to: tmp.appendingPathComponent("003-comments.md"), atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let headings = try IdsManager.collectHeadings(project: project)

    let ids = headings.compactMap { $0.id }
    #expect(ids.contains("BR1"))
    #expect(ids.contains("BR2"))
    #expect(!ids.contains("BR88"))
    #expect(!ids.contains("TS99"))
}

@Test func idsCollectHeadingsSkipsTables() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-idfilter-table-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let content = """
# Doc

| ID | Desc |
|----|------|
| BR77 | Fake in table |

## BR1: Real Table Test Case
"""
    try content.write(to: tmp.appendingPathComponent("004-tables.md"), atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let headings = try IdsManager.collectHeadings(project: project)

    let ids = headings.compactMap { $0.id }
    #expect(ids.contains("BR1"))
    #expect(!ids.contains("BR77"))
}

@Test func idsAssignIgnoresNonContentHeadings() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-idassign-filter-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let content = """
# Spec

```
## BR99: Should never be assigned in fence
```

> ## TS55: Also never in quote

## BR1: Real One
"""
    try content.write(to: tmp.appendingPathComponent("005-assign.md"), atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)

    // collectHeadings must ignore headings inside fences, blockquotes, comments, and tables (#30).
    // The only recognized heading with an ID should be the real BR1 outside any exclusion zone.
    let headings = try IdsManager.collectHeadings(project: project)
    let idsFound = headings.compactMap { $0.id }

    #expect(idsFound == ["BR1"])
    #expect(!idsFound.contains("BR99"))
    #expect(!idsFound.contains("TS55"))

    // Also ensure we did not surface the example headings at all (even without IDs)
    let allContent = headings.map { $0.content }
    #expect(!allContent.contains { $0.contains("Should never") })
    #expect(!allContent.contains { $0.contains("Also never") })
    #expect(allContent.contains { $0.contains("Real One") })
}

// MARK: - ID scanner strips outline numbering (#34)

@Test func stripOutlinePrefixLeavesIDsAndPlainTitles() {
    // Shared utility used by both #4 renumbering and #34 ID scanning.
    #expect(HeadingNumberer.stripOutlinePrefix(from: "1.2. BR1: User Login") == "BR1: User Login")
    #expect(HeadingNumberer.stripOutlinePrefix(from: "1.2.3. TS10: Login Screen") == "TS10: Login Screen")
    #expect(HeadingNumberer.stripOutlinePrefix(from: "12. User Login") == "User Login")
    #expect(HeadingNumberer.stripOutlinePrefix(from: "BR1: User Login") == "BR1: User Login")
    #expect(HeadingNumberer.stripOutlinePrefix(from: "User Login") == "User Login")
    // Must not treat ID-like tokens as outline numbers
    #expect(HeadingNumberer.stripOutlinePrefix(from: "BR1: 1.2. Nested mention") == "BR1: 1.2. Nested mention")
}

@Test func idsCollectHeadingsStripsOutlineBeforeDetectingIDs() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-outline-scan-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    // Numbered form as produced by HeadingNumberer (#4): outline prefix before the ID.
    // H3 ID included with heading_max_level: 3 so outline strip is tested at nested depth.
    let numbered = """
# Requirements
## 1.1. BR1: User Login
## 1.2. BR2: View Dashboard
### 1.2.1. TS10: Login Screen
"""
    try numbered.write(to: tmp.appendingPathComponent("007-business-requirements.md"), atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try """
    version: 1
    ids:
      heading_max_level: 3
    """.write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let headings = try IdsManager.collectHeadings(project: project)

    let byID = Dictionary(uniqueKeysWithValues: headings.compactMap { h -> (String, IdsManager.HeadingInfo)? in
        guard let id = h.id else { return nil }
        return (id, h)
    })

    #expect(byID["BR1"]?.content == "User Login")
    #expect(byID["BR2"]?.content == "View Dashboard")
    #expect(byID["TS10"]?.content == "Login Screen")
    // Outline digits must not leak into content bindings (would cause false drift).
    #expect(byID["BR1"]?.content.contains("1.1") != true)
    #expect(byID["BR2"]?.content.contains("1.2") != true)
}

@Test func idsCollectHeadingsHandlesMixedNumberedAndUnnumberedFiles() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-outline-mixed-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    // File A: already numbered in source (e.g. from a previous build paste or manual outline)
    let numberedFile = """
# Spec A
## 1.1. BR1: User Login
## 1.2. Business requirement for logout
"""
    // File B: unnumbered source (normal authoring style)
    let plainFile = """
# Spec B
## BR2: View Dashboard
## Technical specification for API
"""
    try numberedFile.write(to: tmp.appendingPathComponent("007-a.md"), atomically: true, encoding: .utf8)
    try plainFile.write(to: tmp.appendingPathComponent("008-b.md"), atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let headings = try IdsManager.collectHeadings(project: project)

    let withIDs = headings.filter { $0.id != nil }
    let withoutIDs = headings.filter { $0.id == nil }

    #expect(Set(withIDs.compactMap(\.id)) == Set(["BR1", "BR2"]))
    #expect(withIDs.first { $0.id == "BR1" }?.content == "User Login")
    #expect(withIDs.first { $0.id == "BR2" }?.content == "View Dashboard")

    // Unnumbered-by-ID headings still have outline stripped from content for assign/bindings.
    let logout = withoutIDs.first { $0.content.contains("logout") }
    let api = withoutIDs.first { $0.content.contains("API") }
    #expect(logout?.content == "Business requirement for logout")
    #expect(api?.content == "Technical specification for API")
    #expect(logout?.content.hasPrefix("1.") != true)
}

@Test func idsAssignPreservesOutlinePrefixWhenInsertingID() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-outline-assign-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    // Numbered heading without an ID yet — assign must insert ID after the outline, not before.
    let mdURL = tmp.appendingPathComponent("007-business-requirements.md")
    let content = """
# Requirements
## 1.1. Business requirement for user login
## BR2: Already tagged view
"""
    try content.write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    try IdsManager.assignIDs(project: project, dryRun: false)

    let rewritten = try String(contentsOf: mdURL, encoding: .utf8)
    // ID after outline: "## 1.1. BRn: …" — never "## BRn: 1.1. …"
    #expect(rewritten.contains("## 1.1. BR") || rewritten.contains("## 1.1. BR1:"))
    #expect(!rewritten.contains("## BR1: 1.1."))
    #expect(!rewritten.contains("## BR3: 1.1."))
    #expect(rewritten.contains("## BR2: Already tagged view"))

    // Re-scan: content binding must be outline-free descriptive text only.
    let headings = try IdsManager.collectHeadings(project: project)
    let assigned = headings.first { $0.content.lowercased().contains("user login") }
    #expect(assigned?.id != nil)
    #expect(assigned?.content == "Business requirement for user login")
    #expect(assigned?.content.contains("1.1") != true)
}

@Test func idsScanMatchesNumberedPipelineOutput() throws {
    // End-to-end disjointness: build-time numbering then ID scan must still see real IDs.
    let md = """
# Requirements
## BR1: User Login
## BR2: View Dashboard
### TS10: Login Screen
"""
    let numbered = HeadingNumberer.numberHeadings(in: md, maxLevel: 3)
    #expect(numbered.contains("## 1.1. BR1: User Login"))
    #expect(numbered.contains("## 1.2. BR2: View Dashboard"))
    #expect(numbered.contains("### 1.2.1. TS10: Login Screen"))

    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-outline-pipeline-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    try numbered.write(to: tmp.appendingPathComponent("007-reqs.md"), atomically: true, encoding: .utf8)
    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    // Raise max so H3 TS10 is in scope for this pipeline check (#32).
    try """
    version: 1
    ids:
      heading_max_level: 3
    """.write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let headings = try IdsManager.collectHeadings(project: project)
    let ids = Set(headings.compactMap(\.id))
    #expect(ids == Set(["BR1", "BR2", "TS10"]))
    #expect(headings.first { $0.id == "BR1" }?.content == "User Login")
    #expect(headings.first { $0.id == "TS10" }?.content == "Login Screen")
}

// MARK: - ID heading levels (#32)

@Test func idsHeadingMaxLevelClampAndConfigDefaults() throws {
    #expect(SpecticusConfig.IdsSection.clampHeadingMaxLevel(0) == 1)
    #expect(SpecticusConfig.IdsSection.clampHeadingMaxLevel(-5) == 1)
    #expect(SpecticusConfig.IdsSection.clampHeadingMaxLevel(2) == 2)
    #expect(SpecticusConfig.IdsSection.clampHeadingMaxLevel(6) == 6)
    #expect(SpecticusConfig.IdsSection.clampHeadingMaxLevel(99) == 6)
    #expect(SpecticusConfig.IdsSection.defaultHeadingMaxLevel == 2)

    let yaml = """
    version: 1
    ids:
      heading_max_level: 5
    """
    let config = try SpecticusConfig.parse(yaml: yaml)
    #expect(config.ids.headingMaxLevel == 5)

    let over = try SpecticusConfig.parse(yaml: """
    ids:
      heading_max_level: 99
    """)
    #expect(over.ids.headingMaxLevel == 6)
}

@Test func idsCollectHeadingsDefaultAllowsH1AndH2Only() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-levels-default-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let content = """
# BR10: Document-level requirement
## BR1: Section requirement
### BR2: Nested should be ignored by default
#### BR3: Deeper still ignored
"""
    try content.write(to: tmp.appendingPathComponent("007-reqs.md"), atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    // No heading_max_level → default 2
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    #expect(project.config.ids.headingMaxLevel == 2)

    let headings = try IdsManager.collectHeadings(project: project)
    let ids = Set(headings.compactMap(\.id))
    #expect(ids == Set(["BR10", "BR1"]))
    #expect(!ids.contains("BR2"))
    #expect(!ids.contains("BR3"))
    #expect(headings.allSatisfy { $0.level <= 2 })
}

@Test func idsCollectHeadingsRespectsRaisedHeadingMaxLevel() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-levels-raised-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let content = """
# Doc
## BR1: Top
### TC1: Nested test case
#### TS9: Too deep for max 3
"""
    try content.write(to: tmp.appendingPathComponent("010-test-plan.md"), atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try """
    version: 1
    ids:
      heading_max_level: 3
    """.write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let headings = try IdsManager.collectHeadings(project: project)
    let ids = Set(headings.compactMap(\.id))
    #expect(ids == Set(["BR1", "TC1"]))
    #expect(!ids.contains("TS9"))
    #expect(headings.allSatisfy { $0.level <= 3 })
}

@Test func idsCollectHeadingsCanIncludeThroughH6() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-levels-h6-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let content = """
# BR1: L1
## BR2: L2
### BR3: L3
#### BR4: L4
##### BR5: L5
###### BR6: L6
"""
    try content.write(to: tmp.appendingPathComponent("007-deep.md"), atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try """
    version: 1
    ids:
      heading_max_level: 6
    """.write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let headings = try IdsManager.collectHeadings(project: project)
    let ids = Set(headings.compactMap(\.id))
    #expect(ids == Set(["BR1", "BR2", "BR3", "BR4", "BR5", "BR6"]))
}

@Test func idsAssignOnlyTargetsEligibleHeadingLevels() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-levels-assign-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    // Neutral filename so H1 does not pick up a prefix from the path (#32 assign scope).
    let mdURL = tmp.appendingPathComponent("007-section.md")
    let content = """
# Overview
## Business requirement for login flow
### Business requirement nested should not get an ID at default max
"""
    try content.write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    try IdsManager.assignIDs(project: project, dryRun: false)

    let rewritten = try String(contentsOf: mdURL, encoding: .utf8)
    let lines = rewritten.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #expect(lines.contains("## BR1: Business requirement for login flow"))
    #expect(lines.contains("# Overview"))
    // H1 / H3 must not have received an ID under default heading_max_level: 2
    #expect(!lines.contains { $0.hasPrefix("# BR") && !$0.hasPrefix("##") })
    #expect(lines.contains("### Business requirement nested should not get an ID at default max"))
    #expect(!lines.contains { $0.hasPrefix("### BR") })

    let headings = try IdsManager.collectHeadings(project: project)
    let assigned = headings.compactMap(\.id)
    #expect(assigned == ["BR1"])
    #expect(headings.filter { $0.id != nil }.allSatisfy { $0.level == 2 })
}

// MARK: - Prefix inference for new headings (assign recognition)

@Test func idsAssignRecognizesPlainH2InTechnicalSpecificationsFile() throws {
    // Regression: plain-language H2 titles in 008-technical-specifications.md must get TS IDs
    // even when the title itself has no "specification"/"shall" keywords.
    // (With #32, H1 may also receive a TS from section title/filename; assert H2s specifically.)
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-new-ts-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("008-technical-specifications.md")
    let content = """
# Technical Specifications
## TS1: Login Screen Appearance
## TS2: Login Help Dialog
## Brand Color Palette
## Password Reset Flow
"""
    try content.write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    try IdsManager.assignIDs(project: project, dryRun: false)

    let rewritten = try String(contentsOf: mdURL, encoding: .utf8)
    let lines = rewritten.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #expect(lines.contains("## TS1: Login Screen Appearance"))
    #expect(lines.contains("## TS2: Login Help Dialog"))
    #expect(lines.contains { $0.hasPrefix("## TS") && $0.contains("Brand Color Palette") })
    #expect(lines.contains { $0.hasPrefix("## TS") && $0.contains("Password Reset Flow") })

    let headings = try IdsManager.collectHeadings(project: project)
    let h2IDs = headings.filter { $0.level == 2 }.compactMap(\.id)
    #expect(Set(h2IDs).isSuperset(of: ["TS1", "TS2"]))
    #expect(h2IDs.filter { $0.hasPrefix("TS") }.count >= 4)
}

@Test func idsAssignInheritsPrefixFromSiblingIDsInSameFile() throws {
    // Even with a non-skeleton filename, existing TS* siblings imply TS for new plain H2s.
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-sibling-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("misc-notes.md")
    try """
# Notes
## TS1: Existing Spec
## Brand Color Palette
""".write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    try IdsManager.assignIDs(project: project, dryRun: false)

    let rewritten = try String(contentsOf: mdURL, encoding: .utf8)
    let lines = rewritten.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    // Plain H2 inherits TS from sibling TS1 (H1 may also inherit under #32 H1 eligibility).
    #expect(lines.contains { $0.hasPrefix("## TS") && $0.contains("Brand Color Palette") })
    #expect(lines.contains("## TS1: Existing Spec"))
}

@Test func idsAssignUsesBusinessRequirementsFilenameForPlainH2() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-new-br-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-business-requirements.md")
    // Neutral H1 (no "requirement" keyword) so only the plain H2 is the focus; filename still → BR.
    try """
# Section
## BR1: User Login
## Offline Mode
""".write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    try IdsManager.assignIDs(project: project, dryRun: false)

    let rewritten = try String(contentsOf: mdURL, encoding: .utf8)
    let lines = rewritten.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    // H2 Offline Mode must get a BR* ID via filename (and/or siblings). H1 may also get one from filename.
    #expect(lines.contains { $0.hasPrefix("## BR") && $0.contains("Offline Mode") })
    #expect(lines.contains("## BR1: User Login"))
}

// MARK: - Counter strategy max+1 never reuse (#33)

@Test func counterHighWaterMarkUsesBindingsAndCounters() {
    var store = IdsManager.IdStore()
    store.counters["BR"] = 2
    store.bindings["BR1"] = "One"
    store.bindings["BR5"] = "Orphan five" // higher than counter
    store.bindings["TS3"] = "Other prefix"

    #expect(IdsManager.highWaterMark(for: "BR", store: store) == 5)
    #expect(IdsManager.highWaterMark(for: "TS", store: store) == 3)
    #expect(IdsManager.highWaterMark(for: "UC", store: store) == 0)

    let nextBR = IdsManager.allocateNextID(prefix: "BR", store: &store)
    #expect(nextBR == "BR6")
    #expect(store.counters["BR"] == 6)

    let nextTS = IdsManager.allocateNextID(prefix: "TS", store: &store)
    #expect(nextTS == "TS4")
    #expect(store.counters["TS"] == 4)
    // BR counter untouched by TS allocation
    #expect(store.counters["BR"] == 6)
}

@Test func counterNeverReusesGapInLiveMarkdown() throws {
    // BR1 and BR3 present; BR2 missing → new IDs must be > 3, never BR2.
    // (H1 may also receive a BR via sibling context under #32; policy is still max+1.)
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-gap-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-section.md")
    try """
# Overview
## BR1: First
## BR3: Third
## Offline Mode requirement
""".write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    try IdsManager.assignIDs(project: project, dryRun: false)

    let rewritten = try String(contentsOf: mdURL, encoding: .utf8)
    let lines = rewritten.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #expect(lines.contains("## BR1: First"))
    #expect(lines.contains("## BR3: Third"))
    #expect(lines.contains { $0.hasPrefix("## BR") && $0.contains("Offline Mode requirement") })
    // Gap BR2 must never be filled
    #expect(!rewritten.contains("BR2:"))
    let offlineNum = lines
        .first { $0.contains("Offline Mode requirement") }
        .flatMap { line -> Int? in
            guard let r = line.range(of: #"BR(\d+)"#, options: .regularExpression) else { return nil }
            return Int(line[r].dropFirst(2))
        }
    #expect(offlineNum != nil)
    #expect((offlineNum ?? 0) >= 4)
}

@Test func counterOrphanBindingReservesNumber() throws {
    // Orphan BR2 in ids.json (no longer in Markdown) must not be reissued.
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-orphan-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-section.md")
    try """
# Overview
## BR1: Still Live
## New Requirement
""".write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)
    try """
    {
      "version": 1,
      "counters": { "BR": 2 },
      "bindings": {
        "BR1": "Still Live",
        "BR2": "Deleted requirement kept for history"
      }
    }
    """.write(to: specticusDir.appendingPathComponent("ids.json"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    try IdsManager.assignIDs(project: project, dryRun: false)

    let rewritten = try String(contentsOf: mdURL, encoding: .utf8)
    let lines = rewritten.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #expect(lines.contains { $0.contains("New Requirement") && $0.contains("BR") })
    #expect(!rewritten.contains("BR2: New Requirement"))
    #expect(!rewritten.contains("## BR2:"))

    let store = IdsManager.loadStore(from: project.idsURL)
    #expect(store.bindings["BR2"] == "Deleted requirement kept for history")
    #expect(store.counters["BR"] ?? 0 >= 3)
    // The new requirement binding must use a number > 2
    let newBinding = store.bindings.first { $0.value == "New Requirement" }
    #expect(newBinding != nil)
    #expect(newBinding?.key != "BR2")
    if let key = newBinding?.key, let num = Int(key.dropFirst(2)) {
        #expect(num >= 3)
    }
}

@Test func counterTrustsHighStaleCounterOverGaps() throws {
    // counters.BR = 10 even if only BR1 is live → new IDs are > 10, never fill 2…9.
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-id-stale-counter-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-section.md")
    try """
# Overview
## BR1: Only Live
## Another requirement item
""".write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)
    try """
    {
      "version": 1,
      "counters": { "BR": 10 },
      "bindings": { "BR1": "Only Live" }
    }
    """.write(to: specticusDir.appendingPathComponent("ids.json"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    try IdsManager.assignIDs(project: project, dryRun: false)

    let rewritten = try String(contentsOf: mdURL, encoding: .utf8)
    let lines = rewritten.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #expect(lines.contains { $0.hasPrefix("## BR") && $0.contains("Another requirement item") })
    #expect(!rewritten.contains("## BR2:"))
    let itemNum = lines
        .first { $0.contains("Another requirement item") }
        .flatMap { line -> Int? in
            guard let r = line.range(of: #"BR(\d+)"#, options: .regularExpression) else { return nil }
            return Int(line[r].dropFirst(2))
        }
    #expect((itemNum ?? 0) >= 11)
}

@Test func counterPrefixesAreIndependent() throws {
    var store = IdsManager.IdStore()
    store.bindings["BR3"] = "b"
    store.bindings["TS1"] = "t"
    #expect(IdsManager.allocateNextID(prefix: "BR", store: &store) == "BR4")
    #expect(IdsManager.allocateNextID(prefix: "TS", store: &store) == "TS2")
    #expect(IdsManager.allocateNextID(prefix: "UC", store: &store) == "UC1")
}

// MARK: - Drift sensitivity & plain-text headings (#36)

@Test func driftSensitivityConfigParsesAliases() throws {
    let camel = try SpecticusConfig.parse(yaml: """
    ids:
      drift_sensitivity: contentStrictPlus
    """)
    #expect(camel.ids.driftSensitivity == .contentStrictPlus)

    let snake = try SpecticusConfig.parse(yaml: """
    ids:
      drift_sensitivity: content_strict
    """)
    #expect(snake.ids.driftSensitivity == .contentStrict)

    let strict = try SpecticusConfig.parse(yaml: """
    ids:
      drift_sensitivity: strict
    """)
    #expect(strict.ids.driftSensitivity == .strict)
}

@Test func driftStrictDetectsAnyCharacterChange() {
    #expect(IdsManager.contentsMatch("User Login", "User Login", sensitivity: .strict))
    #expect(!IdsManager.contentsMatch("User Login", "user login", sensitivity: .strict))
    #expect(!IdsManager.contentsMatch("User Login", "User  Login", sensitivity: .strict))
    #expect(!IdsManager.contentsMatch("User Login", "User Login!", sensitivity: .strict))
    #expect(IdsManager.isContentDrift(bound: "A", current: "A ", sensitivity: .strict))
}

@Test func driftContentStrictAllowsCaseAndWhitespaceGrowShrink() {
    // Case
    #expect(IdsManager.contentsMatch("User Login", "user login", sensitivity: .contentStrict))
    #expect(IdsManager.contentsMatch("USER LOGIN", "User Login", sensitivity: .contentStrict))
    // Whitespace grow/shrink (not disappear)
    #expect(IdsManager.contentsMatch("User Login", "User  Login", sensitivity: .contentStrict))
    #expect(IdsManager.contentsMatch("  User Login  ", "User Login", sensitivity: .contentStrict))
    // Whitespace disappearance (tokens merge) is still drift
    #expect(!IdsManager.contentsMatch("User Login", "UserLogin", sensitivity: .contentStrict))
    // Wording change is drift
    #expect(!IdsManager.contentsMatch("User Login", "User Logout", sensitivity: .contentStrict))
    // Punctuation still matters under contentStrict
    #expect(!IdsManager.contentsMatch("User Login", "User Login!", sensitivity: .contentStrict))
}

@Test func driftContentStrictPlusAllowsPunctuationChanges() {
    #expect(IdsManager.contentsMatch("User Login", "User Login!", sensitivity: .contentStrictPlus))
    #expect(IdsManager.contentsMatch("User Login", "User-Login", sensitivity: .contentStrictPlus))
    #expect(IdsManager.contentsMatch("User Login?", "user  login", sensitivity: .contentStrictPlus))
    // Semantic word change still drift
    #expect(!IdsManager.contentsMatch("User Login", "User Logout", sensitivity: .contentStrictPlus))
    #expect(!IdsManager.contentsMatch("User Login", "UserLogin", sensitivity: .contentStrictPlus))
}

@Test func headingMarkdownFormattingIsDetected() {
    #expect(IdsManager.headingContainsDisallowedMarkdown("**Bold Title**"))
    #expect(IdsManager.headingContainsDisallowedMarkdown("Use `code` here"))
    #expect(IdsManager.headingContainsDisallowedMarkdown("See [docs](https://example.com)"))
    #expect(IdsManager.headingContainsDisallowedMarkdown("Hello <em>world</em>"))
    #expect(IdsManager.headingContainsDisallowedMarkdown("~~old~~ new"))
    #expect(IdsManager.headingContainsDisallowedMarkdown("*italic title*"))
    #expect(!IdsManager.headingContainsDisallowedMarkdown("Plain User Login"))
    #expect(!IdsManager.headingContainsDisallowedMarkdown("BR1: User Login"))
    // Underscores in ordinary words should not false-positive as italic
    #expect(!IdsManager.headingContainsDisallowedMarkdown("snake_case_identifier"))
}

@Test func idsAssignDetectsDriftUnderStrictMode() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-drift-strict-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-section.md")
    try """
# Overview
## BR1: user login
""".write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try """
    version: 1
    ids:
      drift_sensitivity: strict
    """.write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)
    try """
    {
      "version": 1,
      "counters": { "BR": 1 },
      "bindings": { "BR1": "User Login" }
    }
    """.write(to: specticusDir.appendingPathComponent("ids.json"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let headings = try IdsManager.collectHeadings(project: project)
    let drifts = IdsManager.findContentDrifts(
        headings: headings,
        store: IdsManager.loadStore(from: project.idsURL),
        sensitivity: .strict
    )
    #expect(drifts.count == 1)
    #expect(drifts[0].id == "BR1")
    #expect(drifts[0].oldContent == "User Login")
    #expect(drifts[0].newContent == "user login")

    // Assign must not rewrite store when drift blocks
    try IdsManager.assignIDs(project: project, dryRun: false)
    let storeAfter = IdsManager.loadStore(from: project.idsURL)
    #expect(storeAfter.bindings["BR1"] == "User Login")
}

@Test func idsAssignContentStrictIgnoresCaseOnlyChange() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-drift-cs-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-section.md")
    try """
# Overview
## BR1: user login
""".write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try """
    version: 1
    ids:
      drift_sensitivity: contentStrict
    """.write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)
    try """
    {
      "version": 1,
      "counters": { "BR": 1 },
      "bindings": { "BR1": "User Login" }
    }
    """.write(to: specticusDir.appendingPathComponent("ids.json"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let drifts = IdsManager.findContentDrifts(
        headings: try IdsManager.collectHeadings(project: project),
        store: IdsManager.loadStore(from: project.idsURL),
        sensitivity: project.config.ids.driftSensitivity
    )
    #expect(drifts.isEmpty)

    try IdsManager.assignIDs(project: project, dryRun: false)
    let storeAfter = IdsManager.loadStore(from: project.idsURL)
    // Binding syncs to current exact heading text when not drifting
    #expect(storeAfter.bindings["BR1"] == "user login")
}

@Test func idsAssignBlocksMarkdownInHeadings() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-md-heading-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-section.md")
    try """
# Overview
## BR1: **User Login**
## New requirement item
""".write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)
    try """
    {
      "version": 1,
      "counters": { "BR": 1 },
      "bindings": { "BR1": "**User Login**" }
    }
    """.write(to: specticusDir.appendingPathComponent("ids.json"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let mdFindings = IdsManager.findMarkdownFormattedHeadings(
        in: try IdsManager.collectHeadings(project: project)
    )
    #expect(!mdFindings.isEmpty)

    try IdsManager.assignIDs(project: project, dryRun: false)
    // Must not assign new IDs while markdown problems exist
    let rewritten = try String(contentsOf: mdURL, encoding: .utf8)
    #expect(rewritten.contains("## New requirement item"))
    #expect(!rewritten.contains("## BR2:"))
}

// MARK: - ids accept-drift (#66)

/// Shared fixture for accept-drift tests: one headed ID with a drifted binding under strict mode.
private func makeAcceptDriftFixture(
    markdownBody: String = """
    # Overview
    ## BR1: User authentication
    """,
    bindingsJSON: String = """
    {
      "version": 1,
      "counters": { "BR": 1 },
      "bindings": { "BR1": "User Login" }
    }
    """,
    configYAML: String = """
    version: 1
    ids:
      drift_sensitivity: strict
    """
) throws -> (tmp: URL, mdURL: URL, project: SpecticusProject) {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-accept-drift-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)

    let mdURL = tmp.appendingPathComponent("007-business-requirements.md")
    try markdownBody.write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try configYAML.write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)
    try bindingsJSON.write(to: specticusDir.appendingPathComponent("ids.json"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    return (tmp, mdURL, project)
}

@Test func acceptDriftHappyPathUpdatesBindingAndAuditLog() throws {
    let fm = FileManager.default
    let (tmp, mdURL, project) = try makeAcceptDriftFixture()
    defer { try? fm.removeItem(at: tmp) }

    let mdBefore = try String(contentsOf: mdURL, encoding: .utf8)
    let fixedNow = Date(timeIntervalSince1970: 1_700_000_000) // fixed for stable timestamp

    let result = try IdsManager.acceptDrift(
        project: project,
        id: "BR1",
        note: "editorial rename under CR-42",
        actor: "tester",
        now: fixedNow
    )

    #expect(result.id == "BR1")
    #expect(result.oldContent == "User Login")
    #expect(result.newContent == "User authentication")
    #expect(result.source.contains("007-business-requirements.md"))
    #expect(result.actor == "tester")
    #expect(result.note == "editorial rename under CR-42")

    // Binding updated; other store fields preserved
    let storeAfter = IdsManager.loadStore(from: project.idsURL)
    #expect(storeAfter.bindings["BR1"] == "User authentication")
    #expect(storeAfter.counters["BR"] == 1)

    // Markdown ID token never rewritten
    let mdAfter = try String(contentsOf: mdURL, encoding: .utf8)
    #expect(mdAfter == mdBefore)
    #expect(mdAfter.contains("## BR1: User authentication"))

    // Durable audit log with required fields
    let events = try IdsManager.loadAuditEvents(from: project.idsAuditURL)
    #expect(events.count == 1)
    #expect(events[0].event == "accept-drift")
    #expect(events[0].id == "BR1")
    #expect(events[0].oldContent == "User Login")
    #expect(events[0].newContent == "User authentication")
    #expect(events[0].actor == "tester")
    #expect(events[0].note == "editorial rename under CR-42")
    #expect(events[0].source.contains("007-business-requirements.md"))
    #expect(events[0].timestamp.hasSuffix("Z") || events[0].timestamp.contains("+00:00"))

    // No longer drifting after accept
    let drifts = IdsManager.findContentDrifts(
        headings: try IdsManager.collectHeadings(project: project),
        store: storeAfter,
        sensitivity: .strict
    )
    #expect(drifts.isEmpty)

    // Assign may proceed without drift abort
    try IdsManager.assignIDs(project: project, dryRun: false)
    let storeAfterAssign = IdsManager.loadStore(from: project.idsURL)
    #expect(storeAfterAssign.bindings["BR1"] == "User authentication")
}

@Test func acceptDriftNoOpWhenNoDrift() throws {
    let fm = FileManager.default
    let (tmp, _, project) = try makeAcceptDriftFixture(
        markdownBody: """
        # Overview
        ## BR1: User Login
        """,
        bindingsJSON: """
        {
          "version": 1,
          "counters": { "BR": 1 },
          "bindings": { "BR1": "User Login" }
        }
        """
    )
    defer { try? fm.removeItem(at: tmp) }

    var threw = false
    do {
        _ = try IdsManager.acceptDrift(project: project, id: "BR1", actor: "tester")
    } catch let error as IdsManager.AcceptDriftError {
        threw = true
        guard case .noDrift(let id, let content) = error else {
            Issue.record("Expected noDrift, got \(error)")
            return
        }
        #expect(id == "BR1")
        #expect(content == "User Login")
    }
    #expect(threw)

    let storeAfter = IdsManager.loadStore(from: project.idsURL)
    #expect(storeAfter.bindings["BR1"] == "User Login")
    #expect(!fm.fileExists(atPath: project.idsAuditURL.path))
}

@Test func acceptDriftMissingIDInStore() throws {
    let fm = FileManager.default
    let (tmp, _, project) = try makeAcceptDriftFixture(
        bindingsJSON: """
        {
          "version": 1,
          "counters": {},
          "bindings": {}
        }
        """
    )
    defer { try? fm.removeItem(at: tmp) }

    var threw = false
    do {
        _ = try IdsManager.acceptDrift(project: project, id: "BR1")
    } catch let error as IdsManager.AcceptDriftError {
        threw = true
        guard case .notInStore(let id) = error else {
            Issue.record("Expected notInStore, got \(error)")
            return
        }
        #expect(id == "BR1")
    }
    #expect(threw)
    #expect(!fm.fileExists(atPath: project.idsAuditURL.path))
}

@Test func acceptDriftMissingIDInMarkdown() throws {
    let fm = FileManager.default
    let (tmp, _, project) = try makeAcceptDriftFixture(
        markdownBody: """
        # Overview
        ## Unrelated heading
        """,
        bindingsJSON: """
        {
          "version": 1,
          "counters": { "BR": 1 },
          "bindings": { "BR1": "User Login" }
        }
        """
    )
    defer { try? fm.removeItem(at: tmp) }

    var threw = false
    do {
        _ = try IdsManager.acceptDrift(project: project, id: "BR1")
    } catch let error as IdsManager.AcceptDriftError {
        threw = true
        guard case .notInMarkdown(let id) = error else {
            Issue.record("Expected notInMarkdown, got \(error)")
            return
        }
        #expect(id == "BR1")
    }
    #expect(threw)

    let storeAfter = IdsManager.loadStore(from: project.idsURL)
    #expect(storeAfter.bindings["BR1"] == "User Login")
    #expect(!fm.fileExists(atPath: project.idsAuditURL.path))
}

@Test func acceptDriftRejectsDuplicateClaims() throws {
    let fm = FileManager.default
    let (tmp, _, project) = try makeAcceptDriftFixture(
        markdownBody: """
        # Overview
        ## BR1: User authentication
        ## BR1: Other claim
        """,
        bindingsJSON: """
        {
          "version": 1,
          "counters": { "BR": 1 },
          "bindings": { "BR1": "User Login" }
        }
        """
    )
    defer { try? fm.removeItem(at: tmp) }

    var threw = false
    do {
        _ = try IdsManager.acceptDrift(project: project, id: "BR1")
    } catch let error as IdsManager.AcceptDriftError {
        threw = true
        guard case .duplicateClaims(let id, let locations) = error else {
            Issue.record("Expected duplicateClaims, got \(error)")
            return
        }
        #expect(id == "BR1")
        #expect(locations.count == 2)
    }
    #expect(threw)

    let storeAfter = IdsManager.loadStore(from: project.idsURL)
    #expect(storeAfter.bindings["BR1"] == "User Login")
    #expect(!fm.fileExists(atPath: project.idsAuditURL.path))
}

@Test func acceptDriftAuditWriteFailureDoesNotUpdateBinding() throws {
    let fm = FileManager.default
    let (tmp, mdURL, project) = try makeAcceptDriftFixture()
    defer { try? fm.removeItem(at: tmp) }

    // Occupy the audit path with a directory so append must fail (fail closed).
    try fm.createDirectory(at: project.idsAuditURL, withIntermediateDirectories: true)

    let mdBefore = try String(contentsOf: mdURL, encoding: .utf8)
    let storeBefore = IdsManager.loadStore(from: project.idsURL)

    var threw = false
    do {
        _ = try IdsManager.acceptDrift(project: project, id: "BR1", actor: "tester")
    } catch let error as IdsManager.AcceptDriftError {
        threw = true
        guard case .auditWriteFailed = error else {
            Issue.record("Expected auditWriteFailed, got \(error)")
            return
        }
    }
    #expect(threw)

    let storeAfter = IdsManager.loadStore(from: project.idsURL)
    #expect(storeAfter == storeBefore)
    #expect(storeAfter.bindings["BR1"] == "User Login")

    let mdAfter = try String(contentsOf: mdURL, encoding: .utf8)
    #expect(mdAfter == mdBefore)
}

@Test func acceptDriftDoesNotTouchOtherBindings() throws {
    let fm = FileManager.default
    let (tmp, _, project) = try makeAcceptDriftFixture(
        markdownBody: """
        # Overview
        ## BR1: User authentication
        ## BR2: Session timeout
        """,
        bindingsJSON: """
        {
          "version": 1,
          "counters": { "BR": 2 },
          "bindings": {
            "BR1": "User Login",
            "BR2": "Session timeout"
          }
        }
        """
    )
    defer { try? fm.removeItem(at: tmp) }

    _ = try IdsManager.acceptDrift(project: project, id: "BR1", actor: "tester")

    let storeAfter = IdsManager.loadStore(from: project.idsURL)
    #expect(storeAfter.bindings["BR1"] == "User authentication")
    #expect(storeAfter.bindings["BR2"] == "Session timeout")
    #expect(storeAfter.counters["BR"] == 2)

    let events = try IdsManager.loadAuditEvents(from: project.idsAuditURL)
    #expect(events.count == 1)
    #expect(events[0].id == "BR1")
}

@Test func acceptDriftAppendsAuditLogOnRepeatedAccepts() throws {
    let fm = FileManager.default
    // First accept
    let (tmp, mdURL, project) = try makeAcceptDriftFixture()
    defer { try? fm.removeItem(at: tmp) }

    _ = try IdsManager.acceptDrift(project: project, id: "BR1", note: "first", actor: "tester")

    // Create a second drift and accept again
    try """
    # Overview
    ## BR1: User authn
    """.write(to: mdURL, atomically: true, encoding: .utf8)

    _ = try IdsManager.acceptDrift(project: project, id: "BR1", note: "second", actor: "tester")

    let events = try IdsManager.loadAuditEvents(from: project.idsAuditURL)
    #expect(events.count == 2)
    #expect(events[0].oldContent == "User Login")
    #expect(events[0].newContent == "User authentication")
    #expect(events[0].note == "first")
    #expect(events[1].oldContent == "User authentication")
    #expect(events[1].newContent == "User authn")
    #expect(events[1].note == "second")

    let storeAfter = IdsManager.loadStore(from: project.idsURL)
    #expect(storeAfter.bindings["BR1"] == "User authn")
}
