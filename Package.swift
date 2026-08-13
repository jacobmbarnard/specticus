// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package: Package = Package(
    name: "scs",
    dependencies: [
        .package(url: "https://github.com/JohnSundell/Ink.git", from: "0.6.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .executableTarget(
            name: "scs",
            dependencies: [
                "Ink",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams")
            ],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "scsTests",
            dependencies: ["scs"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
