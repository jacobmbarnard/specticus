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
