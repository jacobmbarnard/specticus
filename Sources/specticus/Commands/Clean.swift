import Foundation
import ArgumentParser

// MARK: - Clean Command (stub)

struct Clean: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove generated output files and directories."
    )

    func run() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: "output.html") {
            try fm.removeItem(atPath: "output.html")
            print("Removed output.html")
        }
        // Future: also clean output/ dir, copied resources, etc. (#9)
        print("Clean complete (basic implementation; full version in follow-up work).")
    }
}
