import ArgumentParser
import Foundation

/// Explicitly rebind one traceability ID’s stored heading text after deliberate review (#66).
///
/// This is **same-identity rewording**, not reassignment: the Markdown ID token is unchanged;
/// only the binding in `.specticus/ids.json` updates, and a durable audit log entry is required.
struct IdsAcceptDrift: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "accept-drift",
        abstract: "Accept content drift for one ID (rebind heading text under the same ID).",
        discussion: """
            When a heading keeps the same traceability ID but its descriptive text changed, \
            Specticus blocks silent continuation (content drift). After review, rebind that \
            single ID to the current heading text:

                scs ids accept-drift BR1
                scs ids accept-drift BR1 --note "editorial rename under CR-42"

            Behavior:
            - Updates only the binding for <ID> in .specticus/ids.json
            - Never rewrites the ID token in Markdown
            - Never mints, renumbers, reuses, or bulk-accepts other IDs
            - Requires true drift under ids.drift_sensitivity (#36)
            - Appends an audit record to .specticus/ids-audit.jsonl; if the log cannot be \
              written, the binding is not updated (fail closed)

            Use for same-identity rewording (e.g. "User Login" → "User authentication"). \
            Do not use for a different requirement (introduce a new ID instead) or to resolve \
            duplicates. See GitHub issue #66.
            """
    )

    @Argument(help: "Traceability ID to rebind (e.g. BR1). One ID per invocation.")
    var id: String

    @Option(name: .long, help: "Optional short reason recorded in the audit log.")
    var note: String?

    func run() throws {
        let project = try SpecticusProject.load()
        for warning in project.warnings {
            print("⚠️  \(warning)")
        }
        do {
            _ = try IdsManager.acceptDrift(project: project, id: id, note: note)
        } catch let error as IdsManager.AcceptDriftError {
            throw ValidationError(error.description)
        }
    }
}
