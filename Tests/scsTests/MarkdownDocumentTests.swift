import Foundation
import Testing
@testable import scs

// Heading numbering, TOC extract, fence/ATX helpers, and ID-scan exclusion zones.
// Driven by MarkdownDocument (internals #18).

// MARK: - MarkdownDocument regions (#18)

@Test func markdownDocumentFlagsFenceBlockquoteCommentAndTable() {
    let md = """
    # Real
    ```
    # Fenced
    ```
    > ## Quoted
    <!--
    ## Commented
    -->
    | ## TableHeading |
    ## Also Real
    """
    let doc = MarkdownDocument.parse(md)

    let real = doc.lines.first { $0.heading?.text == "Real" }
    #expect(real != nil)
    #expect(real?.inFence == false)
    #expect(real?.inBlockquote == false)
    #expect(real?.inHTMLComment == false)
    #expect(real?.inTable == false)
    #expect(real?.recoveredHeading?.text == "Real")

    let fenced = doc.lines.first { $0.inFence && $0.recoveredHeading?.text == "Fenced" }
    #expect(fenced != nil)
    #expect(fenced?.heading?.text == "Fenced")

    let quoted = doc.lines.first { $0.inBlockquote }
    #expect(quoted?.recoveredHeading?.level == 2)
    #expect(quoted?.recoveredHeading?.text == "Quoted")
    #expect(quoted?.heading == nil)

    let commented = doc.lines.filter(\.inHTMLComment)
    #expect(commented.count >= 2)
    #expect(commented.allSatisfy { $0.recoveredHeading == nil })

    let table = doc.lines.first { $0.inTable && $0.recoveredHeading != nil }
    #expect(table?.recoveredHeading?.text == "TableHeading")
    #expect(table?.heading == nil)

    let also = doc.lines.first { $0.heading?.text == "Also Real" }
    #expect(also?.inFence == false)
    #expect(also?.inBlockquote == false)
    #expect(also?.inHTMLComment == false)
    #expect(also?.inTable == false)
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


@Test func markdownSourcesFenceAndATXHelpers() {
    #expect(MarkdownSources.isFenceDelimiter("```"))
    #expect(MarkdownSources.isFenceDelimiter("```swift"))
    #expect(MarkdownSources.isFenceDelimiter("~~~"))
    #expect(!MarkdownSources.isFenceDelimiter("# Heading"))

    let h = MarkdownSources.parseATXHeading("##  Hello World  ##")
    #expect(h?.level == 2)
    #expect(h?.title == "Hello World")
    #expect(MarkdownSources.parseATXHeading("not a heading") == nil)
}

