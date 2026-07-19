import ArgumentParser
import Foundation

/// Remove orphan bindings from ids.json after explicit review (#37).
///
/// Orphans reserve numbers under the #33 counter policy. Pruning drops the stored
/// descriptive text only; high-water counters are never lowered, so numbers stay reserved.
struct IdsPruneOrphans: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prune-orphans",
        abstract: "Remove orphan ID bindings from ids.json (numbers stay reserved).",
        discussion: """
            An orphan is an ID present in .specticus/ids.json but not claimed by any \
            eligible Markdown heading (e.g. after deleting or renaming a requirement).

            By default orphans are kept for audit history and to reserve their numbers \
            (counter policy #33: never reuse). After deliberate review, prune them:

                specticus ids prune-orphans
                specticus ids prune-orphans --dry-run
                specticus ids prune-orphans --id BR2 --note "retired under CR-99"

            Behavior:
            - Removes orphan bindings only (or a single --id if it is an orphan)
            - Never rewrites Markdown
            - Never lowers counters — pruned numbers are not reused
            - Appends prune-orphan audit events to .specticus/ids-audit.jsonl; \
              if the log cannot be written, bindings are not updated (fail closed)

            Do not use this to free numbers for new requirements — allocation is always \
            max+1. See GitHub issues #37 and #33.
            """
    )

    @Flag(name: .shortAndLong, help: "Preview orphans that would be pruned without writing.")
    var dryRun: Bool = false

    @Option(name: .long, help: "Prune only this ID (must be an orphan).")
    var id: String?

    @Option(name: .long, help: "Optional short reason recorded in the audit log.")
    var note: String?

    func run() throws {
        let project = try SpecticusProject.load()
        for warning in project.warnings {
            print("⚠️  \(warning)")
        }
        do {
            _ = try IdsManager.pruneOrphans(
                project: project,
                onlyID: id,
                dryRun: dryRun,
                note: note
            )
        } catch let error as IdsManager.PruneOrphansError {
            throw ValidationError(error.description)
        }
    }
}
