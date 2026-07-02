import Testing
import Foundation
@testable import specticus

@Test func example() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    // Swift Testing Documentation
    // https://swiftpackageindex.com/swiftlang/swift-testing/documentation
}

@Test func multiFileAssemblyLexOrder() async throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-test-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    // Create files out of order + things that should be skipped
    try "CONTENT-003".write(to: tmp.appendingPathComponent("003-z.md"), atomically: true, encoding: .utf8)
    try "CONTENT-001".write(to: tmp.appendingPathComponent("001-a.md"), atomically: true, encoding: .utf8)
    try "CONTENT-002".write(to: tmp.appendingPathComponent("002-b.md"), atomically: true, encoding: .utf8)
    try "SHOULD-BE-SKIPPED".write(to: tmp.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    try "LEGACY".write(to: tmp.appendingPathComponent("welcome-template.md"), atomically: true, encoding: .utf8)

    let assembled = try DocumentGenerator.assembleSources(input: nil, baseDirectory: tmp.path)

    #expect(assembled.contains("CONTENT-001"))
    #expect(assembled.contains("CONTENT-002"))
    #expect(assembled.contains("CONTENT-003"))

    // Verify order
    let pos1 = assembled.range(of: "CONTENT-001")!.lowerBound
    let pos2 = assembled.range(of: "CONTENT-002")!.lowerBound
    let pos3 = assembled.range(of: "CONTENT-003")!.lowerBound

    #expect(pos1 < pos2)
    #expect(pos2 < pos3)

    #expect(!assembled.contains("SHOULD-BE-SKIPPED"))
    #expect(!assembled.contains("LEGACY"))
}

@Test func singleFileInputMode() async throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("specticus-test-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    try "ONLY-THIS".write(to: tmp.appendingPathComponent("specific.md"), atomically: true, encoding: .utf8)
    try "OTHER".write(to: tmp.appendingPathComponent("other.md"), atomically: true, encoding: .utf8)

    let assembled = try DocumentGenerator.assembleSources(input: "specific.md", baseDirectory: tmp.path)
    #expect(assembled.contains("ONLY-THIS"))
    #expect(!assembled.contains("OTHER"))
}
