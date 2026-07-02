// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "specticus",
    dependencies: [
        .package(url: "https://github.com/JohnSundell/Ink.git", from: "0.6.0")
    ],
    targets: [
        .executableTarget(
            name: "specticus",
            dependencies: ["Ink"]
        ),
        .testTarget(
            name: "specticusTests",
            dependencies: ["specticus"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
