import ArgumentParser

// MARK: - CLI Root

@main
struct Specticus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "specticus",
        abstract: "A fast, beautiful documentation generator for specifications as code.",
        version: "0.1.0",
        subcommands: [
            Build.self,
            Init.self,
            Lint.self,
            Clean.self,
            Open.self,
            Ids.self
        ],
        defaultSubcommand: Build.self
    )
}
