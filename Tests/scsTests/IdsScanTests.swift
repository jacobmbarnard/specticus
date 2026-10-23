import Testing
import Foundation
@testable import scs

// MARK: - ID scanner (internals #20 / scan)

// MARK: - ID scanner strips outline numbering (#34)

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

@Test func markdownSourcesAssembleAndCollectHeadingsShareDiscovery() throws {
    // assemble + collectHeadings must see the same content file set (#35).
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-shared-discovery-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    try """
    # Overview
    ## Login requirement
    """.write(to: tmp.appendingPathComponent("007-business-requirements.md"), atomically: true, encoding: .utf8)
    try "SKIP-ME".write(to: tmp.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    try "LEGACY".write(to: tmp.appendingPathComponent("welcome-template.md"), atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let assembled = try DocumentGenerator.assembleSources(input: nil, baseDirectory: tmp.path)
    #expect(assembled.contains("Login requirement"))
    #expect(!assembled.contains("SKIP-ME"))
    #expect(!assembled.contains("LEGACY"))

    let project = try SpecticusProject.load(from: tmp.path)
    let headings = try IdsManager.collectHeadings(project: project)
    let discovered = try MarkdownSources.discoverContentFiles(in: tmp)
    #expect(Set(headings.map { $0.file.lastPathComponent }) == Set(discovered.map(\.lastPathComponent)))
    #expect(headings.contains { $0.content.contains("Login") || $0.title.contains("Login") })
}

// MARK: - Assign skip feedback (#43)

@Test func diagnoseUnrecognizedIDFormDetectsNearMisses() {
    #expect(IdsManager.diagnoseUnrecognizedIDForm(in: "BR-001: Legacy") != nil)
    #expect(IdsManager.diagnoseUnrecognizedIDForm(in: "BR-001: Legacy")!.contains("legacy")
        || IdsManager.diagnoseUnrecognizedIDForm(in: "BR-001: Legacy")!.contains("dash"))
    #expect(IdsManager.diagnoseUnrecognizedIDForm(in: "br1: Lowercase") != nil)
    #expect(IdsManager.diagnoseUnrecognizedIDForm(in: "[BR1]: Brackets") != nil)
    #expect(IdsManager.diagnoseUnrecognizedIDForm(in: "BR01: Padded") != nil)
    #expect(IdsManager.diagnoseUnrecognizedIDForm(in: "FOO1: Unknown") != nil)
    #expect(IdsManager.diagnoseUnrecognizedIDForm(in: "BR1") != nil)
    // Valid owning form is not a near-miss
    #expect(IdsManager.diagnoseUnrecognizedIDForm(in: "BR1: User Login") == nil)
    // Plain language is not a near-miss
    #expect(IdsManager.diagnoseUnrecognizedIDForm(in: "Document Metadata") == nil)
}

@Test func scanHeadingsReportsDeeperLevelsAndCodeFences() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-scan-43-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    try """
    # Overview
    ## BR1: Eligible
    ### BR2: Too Deep
    ```
    ## BR9: Inside Fence
    ```
    > ## BR8: Quoted Example
    ## Plain structural
    """.write(to: tmp.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let scan = try IdsManager.scanHeadings(project: project)

    // Eligible: H1 Overview, H2 BR1, H2 Plain structural (default max level 2)
    #expect(scan.eligible.count == 3)
    #expect(scan.eligible.contains { $0.id == "BR1" })
    #expect(scan.eligible.contains { $0.id == nil && $0.content == "Overview" })
    #expect(scan.eligible.contains { $0.id == nil && $0.content == "Plain structural" })

    let deeper = scan.excluded.filter {
        if case .deeperThanMaxLevel = $0.exclusion { return true }
        return false
    }
    #expect(deeper.contains { $0.title.contains("Too Deep") })

    let fences = scan.excluded.filter { $0.exclusion == .insideCodeFence }
    #expect(fences.contains { $0.title.contains("Inside Fence") })

    let quotes = scan.excluded.filter { $0.exclusion == .insideBlockquote }
    #expect(quotes.contains { $0.title.contains("Quoted Example") })

    // collectHeadings must match eligible subset (no fence/quote/deep owners)
    let collected = try IdsManager.collectHeadings(project: project)
    #expect(collected.count == scan.eligible.count)
    #expect(Set(collected.compactMap(\.id)) == Set(scan.eligible.compactMap(\.id)))
}

// MARK: - Skip structural section titles on ids assign

@Test func structuralSectionTitleDetection() {
    let brFile = URL(fileURLWithPath: "/proj/business-requirements/001-business-requirements.md")
    #expect(IdsManager.isStructuralSectionTitle("Business Requirements", file: brFile))
    #expect(IdsManager.isStructuralSectionTitle("1. Business Requirements", file: brFile))
    #expect(IdsManager.isStructuralSectionTitle("Technical Specifications", file: brFile))
    #expect(IdsManager.isStructuralSectionTitle("Use Cases", file: brFile))
    #expect(!IdsManager.isStructuralSectionTitle("User Login", file: brFile))
    #expect(!IdsManager.isStructuralSectionTitle("The system shall authenticate users", file: brFile))

    // Title that only restates the folder / file stem
    let custom = URL(fileURLWithPath: "/proj/my-feature-area/001-my-feature-area.md")
    #expect(IdsManager.isStructuralSectionTitle("My Feature Area", file: custom))
    #expect(!IdsManager.isStructuralSectionTitle("Login flow", file: custom))
}
