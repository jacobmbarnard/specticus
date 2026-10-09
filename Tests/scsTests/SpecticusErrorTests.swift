import ArgumentParser
import Foundation
import Testing
@testable import scs

@Test func specticusErrorMessagesMatchPreviousValidationText() {
    #expect(
        SpecticusError.missingInput(path: "notes.md").description
            == "Input file not found: notes.md."
    )
    #expect(
        SpecticusError.noMarkdownSources.description
            == "No Markdown files found to assemble (looked for *.md / *.markdown). Specify --input or add content files."
    )
    #expect(
        SpecticusError.invalidConfig(path: ".specticus/config.yml", reason: "bad yaml").description
            == "Failed to parse .specticus/config.yml: bad yaml"
    )
    #expect(
        SpecticusError.unknownStylePack(id: "nope", known: "default, minimal").description
            == "Unknown documentation style 'nope'. Built-in styles: default, minimal."
    )
    #expect(
        SpecticusError.missingBundledResources(
            packID: "default",
            resourceParent: "Resources",
            resourceDirectory: "Skeleton"
        ).description
            == "Internal error: style pack 'default' resources not found (Resources/Skeleton)."
    )
}

@Test func commandBoundaryTurnsSpecticusErrorIntoValidationError() {
    let library = SpecticusError.missingInput(path: "missing.md")
    do {
        _ = try CommandBoundary.call { throw library }
        Issue.record("expected CommandBoundary to throw")
    } catch let error as ValidationError {
        // ArgumentParser prints CustomStringConvertible, not localizedDescription.
        #expect(error.description == library.description)
    } catch {
        Issue.record("expected ValidationError, got \(error)")
    }
}

@Test func commandBoundaryPassesOtherErrorsThrough() {
    struct Other: Error, Equatable {}
    do {
        _ = try CommandBoundary.call { throw Other() }
        Issue.record("expected throw")
    } catch is Other {
        // unchanged
    } catch {
        Issue.record("expected Other, got \(error)")
    }
}

@Test func projectLoadThrowsInvalidConfig() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-bad-config-\(UUID().uuidString)")
    let specticusDir = tmp.appendingPathComponent(".specticus")
    try fm.createDirectory(at: specticusDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }
    try "version: [\n".write(to: specticusDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

    do {
        _ = try SpecticusProject.load(from: tmp.path)
        Issue.record("expected invalid config")
    } catch let error as SpecticusError {
        guard case .invalidConfig(let path, let reason) = error else {
            Issue.record("expected invalidConfig, got \(error)")
            return
        }
        #expect(path == ".specticus/config.yml")
        #expect(error.description.hasPrefix("Failed to parse .specticus/config.yml:"))
        #expect(!reason.isEmpty)
    } catch {
        Issue.record("expected SpecticusError, got \(error)")
    }
}

@Test func assembleSourcesThrowsMissingInput() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-missing-input-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    do {
        _ = try DocumentGenerator.assembleSources(input: "nope.md", baseDirectory: tmp.path)
        Issue.record("expected missing input")
    } catch let error as SpecticusError {
        #expect(error == .missingInput(path: "nope.md"))
    } catch {
        Issue.record("expected SpecticusError, got \(error)")
    }
}

@Test func assembleSourcesThrowsWhenDirectoryIsEmpty() throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("specticus-empty-asm-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    do {
        _ = try DocumentGenerator.assembleSources(input: nil, baseDirectory: tmp.path, fallbackInput: nil)
        Issue.record("expected no sources")
    } catch let error as SpecticusError {
        #expect(error == .noMarkdownSources)
    } catch {
        Issue.record("expected SpecticusError, got \(error)")
    }
}

@Test func unknownStylePackThrowsSpecticusError() {
    do {
        _ = try StylePackRegistry.skeletonURL(forPackID: "not-a-pack")
        Issue.record("expected unknown style")
    } catch let error as SpecticusError {
        #expect(error.description.contains("Unknown documentation style 'not-a-pack'"))
        #expect(error.description.contains("default"))
    } catch {
        Issue.record("expected SpecticusError, got \(error)")
    }
}
