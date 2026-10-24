import Testing
import Foundation
@testable import scs

// MARK: - Lint rules (#22)

@Test func lintHealthyMinimalInitHasNoFailures() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-lint-ok-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: tmp) }

    var initCmd = Init()
    initCmd.directory = tmp.path
    initCmd.style = "minimal"
    try initCmd.run()

    let project = try SpecticusProject.load(from: tmp.path)
    let findings = LintRules.evaluate(LintContext.make(project: project, cwd: tmp.path))

    let failures = findings.filter { $0.severity == .failure }
    let warnings = findings.filter { $0.severity == .warning }
    #expect(failures.isEmpty)
    #expect(warnings.isEmpty)
    #expect(findings.contains { $0.severity == .pass && $0.message.contains("Detected specticus project") })
    #expect(findings.contains { $0.message.contains("Markdown sources assemble successfully") })
    #expect(findings.contains { $0.message.contains("No duplicate traceability IDs") })
    #expect(findings.contains { $0.message == "ADRs/ structure complete (all status folders)" })
}

@Test func lintDuplicateIDsProduceFailureFinding() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-lint-dups-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: tmp) }

    var initCmd = Init()
    initCmd.directory = tmp.path
    initCmd.style = "minimal"
    try initCmd.run()

    let req = tmp.appendingPathComponent("business-requirements/001-business-requirements.md")
    try """
    # Business Requirements

    ## BR1: First claim

    Text.

    ## BR1: Second claim

    More.
    """.write(to: req, atomically: true, encoding: .utf8)

    let project = try SpecticusProject.load(from: tmp.path)
    let findings = LintRules.evaluate(LintContext.make(project: project, cwd: tmp.path))

    let dup = findings.first {
        $0.severity == .failure && $0.message.contains("Duplicate traceability IDs")
    }
    #expect(dup != nil)
    #expect(dup?.message.contains("BR1") == true)
    #expect(dup?.details.contains { $0.contains("BR1") } == true)
}

@Test func lintMissingTitleIsFailure() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-lint-notitle-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: tmp) }

    var initCmd = Init()
    initCmd.directory = tmp.path
    initCmd.style = "minimal"
    try initCmd.run()
    try fm.removeItem(at: tmp.appendingPathComponent("title.yml"))

    let project = try SpecticusProject.load(from: tmp.path)
    let findings = LintRules.evaluate(LintContext.make(project: project, cwd: tmp.path))

    #expect(findings.contains {
        $0.severity == .failure && $0.message == "title.yml is missing"
    })
}

@Test func lintFindingHelpersSetSeverity() {
    #expect(LintFinding.pass("ok").severity == .pass)
    #expect(LintFinding.warn("w", suggestion: "s").suggestion == "s")
    #expect(LintFinding.fail("f", details: ["d"]).details == ["d"])
    #expect(LintTotals(passed: 2, warnings: 1, failures: 1).failures == 1)
}
