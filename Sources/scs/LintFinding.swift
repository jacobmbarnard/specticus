import Foundation

// MARK: - Lint findings (internals #22)

/// Severity for one lint check result. Counts feed the summary line.
enum LintSeverity: String, Sendable, Equatable {
    case pass
    case warning
    case failure
}

/// One result from a lint rule. The command prints and tallies these.
struct LintFinding: Sendable, Equatable {
    let severity: LintSeverity
    let message: String
    let suggestion: String?
    /// Extra lines under the finding (same indent as today's detail dumps).
    let details: [String]

    init(
        severity: LintSeverity,
        message: String,
        suggestion: String? = nil,
        details: [String] = []
    ) {
        self.severity = severity
        self.message = message
        self.suggestion = suggestion
        self.details = details
    }

    static func pass(_ message: String) -> LintFinding {
        LintFinding(severity: .pass, message: message)
    }

    static func warn(_ message: String, suggestion: String? = nil, details: [String] = []) -> LintFinding {
        LintFinding(severity: .warning, message: message, suggestion: suggestion, details: details)
    }

    static func fail(_ message: String, suggestion: String? = nil, details: [String] = []) -> LintFinding {
        LintFinding(severity: .failure, message: message, suggestion: suggestion, details: details)
    }
}

/// Tallies after printing findings.
struct LintTotals: Sendable, Equatable {
    var passed: Int = 0
    var warnings: Int = 0
    var failures: Int = 0
}

/// Prints findings and summary the way `scs lint` does today.
enum LintReporter {
    static func printFinding(_ finding: LintFinding) {
        switch finding.severity {
        case .pass:
            print("  ✅ \(finding.message)")
        case .warning:
            print("  ⚠️  \(finding.message)")
        case .failure:
            print("  ❌ \(finding.message)")
        }
        if let suggestion = finding.suggestion {
            print("      → \(suggestion)")
        }
        for line in finding.details {
            print("      \(line)")
        }
    }

    static func printFindings(_ findings: [LintFinding]) -> LintTotals {
        var totals = LintTotals()
        for finding in findings {
            printFinding(finding)
            switch finding.severity {
            case .pass: totals.passed += 1
            case .warning: totals.warnings += 1
            case .failure: totals.failures += 1
            }
        }
        return totals
    }

    /// Toolchain / config / last-build notes (not counted in the summary).
    static func printNotes(project: SpecticusProject) {
        print("\n  ℹ️  External tools:")
        print("      • Mermaid diagrams: rendered client-side in the output HTML (no CLI tool required).")
        print("      • For advanced Mermaid CLI rendering you can optionally install @mermaid-js/mermaid-cli.")
        print("  ℹ️  Config: .specticus/config.yml drives output path, CSS, asset copy, diagrams, build tracking (#8), and ID traceability settings (#6; #32 heading levels; #33 counters; #36 drift_sensitivity; #37 ids.json lifecycle; #38 auto_assign is report-only on build — mutation needs --assign-ids; #39 collaboration: duplicate live IDs / ID hygiene, SCM-agnostic). Lint enforces ID uniqueness, drift, plain-text headings, and reports orphans.")
        if project.hasSpecticusDirectory {
            if FileManager.default.fileExists(atPath: project.buildNumberURL.path) {
                if let record = try? BuildTracker.load(from: project.buildNumberURL) {
                    print("  ℹ️  Last recorded build: #\(record.number) at \(record.lastBuilt)")
                }
            }
        }
    }

    static func printSummary(_ totals: LintTotals) {
        print("\n📊 Lint summary:")
        print("   Passed: \(totals.passed)   Warnings: \(totals.warnings)   Failures: \(totals.failures)")

        if totals.failures > 0 {
            print("\nSome critical items need attention before a clean build.")
        } else if totals.warnings > 0 {
            print("\nProject is mostly ready — address warnings for best results.")
        } else {
            print("\n✅ Everything looks good! Try: scs build")
        }
    }
}
