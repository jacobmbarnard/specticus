import ArgumentParser
import Foundation

/// Report ids.json vs Markdown lifecycle state without mutating files (#37).
struct IdsStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show ids.json lifecycle status (live IDs, orphans, drift, recovery hints).",
        discussion: """
            Inspect how Markdown claims relate to .specticus/ids.json without writing files.

            Reports:
            - Whether ids.json is present (missing store = empty; recover with ids assign)
            - Live IDs claimed by eligible headings
            - Orphan bindings (in store, not in Markdown) — intentional by default; reserve numbers
            - Unbound live IDs, content drift, and duplicates

            Orphans are not errors: deleted headings keep their numbers reserved (#33). \
            After review, remove bindings with `ids prune-orphans` (counters never decrease).

            Also reports collaboration hazards (#39): duplicate live ID claims from concurrent \
            `ids assign`. Detection is ID-hygiene only (SCM-agnostic by design).

            See GitHub issues #37 and #39.
            """
    )

    func run() throws {
        let project = try SpecticusProject.load()
        for warning in project.warnings {
            print("⚠️  \(warning)")
        }
        try IdsManager.printStatus(project: project)
    }
}
