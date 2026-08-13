import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Brand / CLI chrome

/// Product version and terminal wordmark for `scs` (#135, v0.2.0).
enum Brand {
    /// CLI / SemVer version string (`scs --version`, formula, tags).
    static let version = "0.2.0"

    /// Locked design from #135 (user-approved art; trailing spaces stripped).
    static let wordmark: String = [
        #"                      _   _"#,
        #"  ___ _ __   ___  ___| |_(_) ___ _   _ ___"#,
        #" / __| '_ \ / _ \/ __| __| |/ __| | | / __|"#,
        #" \__ \ |_) |  __/ (__| |_| | (__| |_| \__ \"#,
        #" |___/ .__/ \___|\___|\__|_|\___|\__,_|___/"#,
        #"     |_|"#,
    ].joined(separator: "\n")

    /// True when stdout is an interactive terminal.
    static var isSTDOUTTY: Bool {
        #if os(Windows)
        return true
        #else
        return isatty(STDOUT_FILENO) != 0
        #endif
    }

    /// Print the wordmark when stdout is a TTY (no-op for pipes/scripts).
    static func printWordmarkIfTTY() {
        guard isSTDOUTTY else { return }
        print(wordmark)
        print()
    }

    /// Root-level `--version` only (not `scs build --version` if ever added).
    static func isRootVersionInvocation(arguments: [String]) -> Bool {
        let args = Array(arguments.dropFirst())
        return args == ["--version"]
    }

    /// Any `-h` / `--help` / `help` so the mark leads help output.
    static func isHelpInvocation(arguments: [String]) -> Bool {
        let args = Array(arguments.dropFirst())
        if args.isEmpty { return false }
        if args.contains("--help") || args.contains("-h") { return true }
        if args.first == "help" { return true }
        return false
    }
}
