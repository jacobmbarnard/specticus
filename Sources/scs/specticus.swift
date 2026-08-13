import ArgumentParser
import Foundation

// MARK: - Entry

@main
enum ScsMain {
    static func main() {
        // Custom chrome for --version / --help (#135); then ArgumentParser.
        if Brand.isRootVersionInvocation(arguments: CommandLine.arguments) {
            Brand.printWordmarkIfTTY()
            print(Brand.version)
            return
        }
        if Brand.isHelpInvocation(arguments: CommandLine.arguments) {
            Brand.printWordmarkIfTTY()
        }
        Specticus.main()
    }
}

// MARK: - CLI Root

struct Specticus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scs",
        abstract: "A fast, beautiful documentation generator for specifications as code.",
        version: Brand.version,
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
