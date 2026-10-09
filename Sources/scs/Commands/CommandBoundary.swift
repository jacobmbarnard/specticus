import ArgumentParser
import Foundation

// MARK: - Command boundary (#17)

/// Turns `SpecticusError` into ArgumentParser `ValidationError` at `run()`.
/// Library types must not throw `ValidationError` themselves.
enum CommandBoundary {
    static func call<T>(_ work: () throws -> T) throws -> T {
        do {
            return try work()
        } catch let error as SpecticusError {
            throw ValidationError(error.description)
        }
    }
}
