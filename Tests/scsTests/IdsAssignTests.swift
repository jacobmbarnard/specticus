import Testing
import Foundation
@testable import scs

// MARK: - ID assigner (internals #20 / assign)

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

@Test func assignDryRunDoesNotWriteMarkdownOrStore() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-assign-dry-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-business-requirements.md")
    try """
    # Overview
    ## User Login requirement
    """.write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let mdBefore = try String(contentsOf: mdURL, encoding: .utf8)

    try IdsManager.assignIDs(project: project, options: .dryRunOnly(showDiff: true))

    let mdAfter = try String(contentsOf: mdURL, encoding: .utf8)
    #expect(mdAfter == mdBefore)
    #expect(!fm.fileExists(atPath: project.idsURL.path))
}

@Test func assignNonInteractiveWithoutYesAbortsBeforeWrite() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-assign-noyes-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-business-requirements.md")
    try """
    # Overview
    ## User Login requirement
    """.write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let mdBefore = try String(contentsOf: mdURL, encoding: .utf8)

    var threw = false
    do {
        try IdsManager.assignIDs(
            project: project,
            options: IdsManager.AssignOptions(
                dryRun: false,
                assumeYes: false,
                showDiff: false,
                checkGit: false,
                isInteractive: false
            )
        )
    } catch let error as IdsManager.AssignAbort {
        threw = true
        guard case .nonInteractiveRequiresYes(let n) = error else {
            Issue.record("Expected nonInteractiveRequiresYes, got \(error)")
            return
        }
        #expect(n >= 1)
    }
    #expect(threw)

    let mdAfter = try String(contentsOf: mdURL, encoding: .utf8)
    #expect(mdAfter == mdBefore)
    #expect(!fm.fileExists(atPath: project.idsURL.path))
}

@Test func assignInteractiveDeclineDoesNotWrite() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-assign-decline-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-business-requirements.md")
    try """
    # Overview
    ## User Login requirement
    """.write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let mdBefore = try String(contentsOf: mdURL, encoding: .utf8)

    var threw = false
    do {
        try IdsManager.assignIDs(
            project: project,
            options: IdsManager.AssignOptions(
                dryRun: false,
                assumeYes: false,
                checkGit: false,
                isInteractive: true,
                confirmHandler: { _ in false }
            )
        )
    } catch let error as IdsManager.AssignAbort {
        threw = true
        #expect(error == .userDeclined)
    }
    #expect(threw)

    let mdAfter = try String(contentsOf: mdURL, encoding: .utf8)
    #expect(mdAfter == mdBefore)
    #expect(!fm.fileExists(atPath: project.idsURL.path))
}

@Test func assignInteractiveYesWritesSources() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-assign-yes-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-business-requirements.md")
    try """
    # Overview
    ## User Login requirement
    """.write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)

    try IdsManager.assignIDs(
        project: project,
        options: IdsManager.AssignOptions(
            dryRun: false,
            assumeYes: false,
            showDiff: true,
            checkGit: false,
            isInteractive: true,
            confirmHandler: { _ in true }
        )
    )

    let mdAfter = try String(contentsOf: mdURL, encoding: .utf8)
    #expect(mdAfter.contains("BR") && mdAfter.contains("User Login requirement"))
    #expect(fm.fileExists(atPath: project.idsURL.path))
    let store = IdsManager.loadStore(from: project.idsURL)
    #expect(!store.bindings.isEmpty)
}

@Test func assignAssumeYesStillWorksForProgrammaticCallers() throws {
    // Backward-compatible assignIDs(project:dryRun:) must still write without prompts.
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-assign-compat-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-business-requirements.md")
    try """
    # Overview
    ## Offline Mode requirement
    """.write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    try IdsManager.assignIDs(project: project, dryRun: false)

    let mdAfter = try String(contentsOf: mdURL, encoding: .utf8)
    #expect(mdAfter.contains("requirement"))
    #expect(mdAfter.contains("BR"))
}

// MARK: - Build-time auto_assign safety (#38)

@Test func buildAssignModeResolution() {
    // Default: no config, no flag → off
    #expect(IdsManager.resolveBuildAssignMode(autoAssign: false, assignIdsFlag: false) == .off)
    // auto_assign alone → report-only (never mutate)
    #expect(IdsManager.resolveBuildAssignMode(autoAssign: true, assignIdsFlag: false) == .reportOnly)
    // Explicit flag → mutate even without auto_assign
    #expect(IdsManager.resolveBuildAssignMode(autoAssign: false, assignIdsFlag: true) == .mutate)
    // Both → mutate (flag is the write gate)
    #expect(IdsManager.resolveBuildAssignMode(autoAssign: true, assignIdsFlag: true) == .mutate)
}

@Test func buildAssignOptionsForReportOnlyAreDryRun() {
    let opts = IdsManager.AssignOptions.forBuild(mode: .reportOnly)
    #expect(opts.dryRun == true)
    #expect(opts.assumeYes == true)
    #expect(opts.autoAssignContext == true)
    #expect(opts.buildAssignMode == .reportOnly)
    #expect(opts.checkGit == false)
}

@Test func buildAssignOptionsForMutateAllowWrite() {
    let opts = IdsManager.AssignOptions.forBuild(mode: .mutate)
    #expect(opts.dryRun == false)
    #expect(opts.assumeYes == true)
    #expect(opts.autoAssignContext == true)
    #expect(opts.buildAssignMode == .mutate)
    #expect(opts.checkGit == true)
}

@Test func buildAutoAssignReportOnlyDoesNotRewriteMarkdown() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-auto-assign-report-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-business-requirements.md")
    try """
    # Overview
    ## User Login requirement
    """.write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try """
    version: 1
    ids:
      auto_assign: true
    """.write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    #expect(project.config.ids.autoAssign == true)

    let mode = IdsManager.resolveBuildAssignMode(
        autoAssign: project.config.ids.autoAssign,
        assignIdsFlag: false
    )
    #expect(mode == .reportOnly)

    let mdBefore = try String(contentsOf: mdURL, encoding: .utf8)
    try IdsManager.assignIDs(project: project, options: .forBuild(mode: mode))

    let mdAfter = try String(contentsOf: mdURL, encoding: .utf8)
    #expect(mdAfter == mdBefore)
    #expect(!fm.fileExists(atPath: project.idsURL.path))
    #expect(!mdAfter.contains("BR1:"))
}

@Test func buildAssignIdsFlagRewritesMarkdown() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-auto-assign-mutate-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-business-requirements.md")
    try """
    # Overview
    ## User Login requirement
    """.write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    // auto_assign false — --assign-ids is still an explicit one-shot mutate
    try """
    version: 1
    ids:
      auto_assign: false
    """.write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let mode = IdsManager.resolveBuildAssignMode(
        autoAssign: project.config.ids.autoAssign,
        assignIdsFlag: true
    )
    #expect(mode == .mutate)

    try IdsManager.assignIDs(project: project, options: .forBuild(mode: mode))

    let mdAfter = try String(contentsOf: mdURL, encoding: .utf8)
    #expect(mdAfter.contains("BR") && mdAfter.contains("User Login requirement"))
    #expect(fm.fileExists(atPath: project.idsURL.path))
}

@Test func configAutoAssignDefaultIsFalseAndDocumentedSafe() throws {
    // Missing key → false (safe default: build never reports/mutates IDs)
    let partial = try SpecticusConfig.parse(yaml: "version: 1\n")
    #expect(partial.ids.autoAssign == false)
    #expect(SpecticusConfig.default.ids.autoAssign == false)
}

// MARK: - Collaboration hazards (#39, ID hygiene / SCM-agnostic)

@Test func collaborationHazardsDetectDuplicateIDsFromConcurrentAssignFallout() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-collab-dupes-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    // Classic concurrent-assign fallout: two developers each assigned BR5 to different headings.
    try """
    # Requirements A
    ## BR5: Alpha Login
    """.write(to: tmp.appendingPathComponent("007-business-requirements.md"), atomically: true, encoding: .utf8)
    try """
    # Requirements B
    ## BR5: Beta Logout
    """.write(to: tmp.appendingPathComponent("008-more-requirements.md"), atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let hazards = try IdsManager.collectCollaborationHazards(project: project)
    #expect(hazards.hasDuplicateIDs)
    #expect(hazards.duplicateIDs == ["BR5"])
    #expect((hazards.duplicateLocations["BR5"] ?? []).count == 2)
    #expect(hazards.hasBlockingProblems)

    let mdABefore = try String(contentsOf: tmp.appendingPathComponent("007-business-requirements.md"), encoding: .utf8)
    try IdsManager.assignIDs(
        project: project,
        options: IdsManager.AssignOptions(dryRun: false, assumeYes: true, checkGit: false)
    )
    let mdAAfter = try String(contentsOf: tmp.appendingPathComponent("007-business-requirements.md"), encoding: .utf8)
    #expect(mdAAfter == mdABefore)
}

@Test func cleanProjectHasNoCollaborationHazards() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-collab-clean-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    try """
    # Overview
    ## BR1: User Login
    """.write(to: tmp.appendingPathComponent("007-business-requirements.md"), atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)
    try """
    {
      "version": 1,
      "bindings": { "BR1": "User Login" },
      "counters": { "BR": 1 }
    }
    """.write(to: specticusDir.appendingPathComponent("ids.json"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let hazards = try IdsManager.collectCollaborationHazards(project: project)
    #expect(!hazards.hasBlockingProblems)
    #expect(hazards.duplicateIDs.isEmpty)
}

@Test func idsAssignSkipsLegacyIDFormWithoutInjectingSecondID() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-legacy-skip-43-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let mdURL = tmp.appendingPathComponent("007-business-requirements.md")
    try """
    # Requirements
    ## BR-001: Legacy Style
    ## Shall authenticate users with SSO
    """.write(to: mdURL, atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    try IdsManager.assignIDs(project: project, dryRun: false)

    let rewritten = try String(contentsOf: mdURL, encoding: .utf8)
    let lines = rewritten.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    // Must not become `## BR1: BR-001: Legacy Style`
    #expect(lines.contains("## BR-001: Legacy Style"))
    #expect(!rewritten.contains("BR1: BR-001"))
    // Keyword heading still gets a real ID
    #expect(lines.contains { line in
        line.hasPrefix("## BR") && line.contains("Shall authenticate") && !line.contains("BR-001")
    })
}

@Test func idsAssignDryRunCompletesWithSkipFeedback() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-skip-feedback-43-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    try """
    # Overview
    ## BR1: Login
    ## Glossary Terms
    ### Nested detail without ID
    """.write(to: tmp.appendingPathComponent("001-overview.md"), atomically: true, encoding: .utf8)

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)
    try """
    {
      "version": 1,
      "bindings": { "BR1": "Login" },
      "counters": { "BR": 1 }
    }
    """.write(to: specticusDir.appendingPathComponent("ids.json"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    // Should not throw; prints scan summary including skipped structural headings (#43)
    try IdsManager.assignIDs(project: project, options: .dryRunOnly(showDiff: false, verbose: true))
    let scan = try IdsManager.scanHeadings(project: project)
    #expect(scan.maxLevel == 2)
    #expect(scan.excluded.contains {
        if case .deeperThanMaxLevel = $0.exclusion { return $0.title.contains("Nested") }
        return false
    })
}

@Test func idsAssignSkipsStructuralSectionTitles() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-skip-section-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let brDir = tmp.appendingPathComponent("business-requirements", isDirectory: true)
    let tsDir = tmp.appendingPathComponent("technical-specifications", isDirectory: true)
    try fm.createDirectory(at: brDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: tsDir, withIntermediateDirectories: true)

    try """
    # Business Requirements
    ## User Login
    The user shall log in.
    ## View Dashboard
    """.write(
        to: brDir.appendingPathComponent("001-business-requirements.md"),
        atomically: true,
        encoding: .utf8
    )
    try """
    # Technical Specifications
    ## Login Screen Appearance
    """.write(
        to: tsDir.appendingPathComponent("001-technical-specifications.md"),
        atomically: true,
        encoding: .utf8
    )

    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    try "version: 1\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    try IdsManager.assignIDs(
        project: project,
        options: .init(dryRun: false, assumeYes: true, checkGit: false)
    )

    let headings = try IdsManager.collectHeadings(project: project)
    func id(for content: String) -> String? {
        headings.first { $0.content == content }?.id
    }

    #expect(id(for: "Business Requirements") == nil)
    #expect(id(for: "Technical Specifications") == nil)
    #expect(id(for: "User Login")?.hasPrefix("BR") == true)
    #expect(id(for: "View Dashboard")?.hasPrefix("BR") == true)
    #expect(id(for: "Login Screen Appearance")?.hasPrefix("TS") == true)

    let brMD = try String(
        contentsOf: brDir.appendingPathComponent("001-business-requirements.md"),
        encoding: .utf8
    )
    #expect(brMD.hasPrefix("# Business Requirements\n"))
    #expect(!brMD.contains("# BR1: Business Requirements"))
    #expect(brMD.contains("## BR1: User Login"))
    #expect(brMD.contains("## BR2: View Dashboard"))
}
