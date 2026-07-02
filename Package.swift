// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "specticus",
    dependencies: [
        .package(url: "https://github.com/JohnSundell/Ink.git", from: "0.6.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "specticus",
            dependencies: [
                "Ink",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "specticusTests",
            dependencies: ["specticus"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
