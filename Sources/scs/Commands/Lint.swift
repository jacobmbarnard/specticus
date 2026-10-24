import Foundation
import ArgumentParser

// MARK: - Lint Command (implements #10; config validation via #7; rules via #22)

struct Lint: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Validate the project structure, required files, and external tools.",
        discussion: "Checks for a valid specticus project layout (from `scs init`), key files, `.specticus/config.yml`, and build readiness. See issues #10 and #7."
    )

    func run() throws {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        let project = try CommandBoundary.call { try SpecticusProject.load(from: cwd) }

        print("🔍 Running scs lint...\n")

        let context = LintContext.make(project: project, cwd: cwd, fm: fm)
        let findings = LintRules.evaluate(context)
        let totals = LintReporter.printFindings(findings)
        LintReporter.printNotes(project: project)
        LintReporter.printSummary(totals)
    }
}
