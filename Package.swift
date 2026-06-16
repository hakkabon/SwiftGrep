// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftGrep",
    platforms: [.macOS(.v12), .iOS(.v14)],
    products: [
        .library(name: "SwiftGrep", targets: ["SwiftGrep"]),
        .executable(name: "sgrep", targets: ["sgrep"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/hakkabon/GrammarTokenizer.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "SwiftGrep",
            dependencies: [
                .product(name: "Tokenizer", package: "GrammarTokenizer"),
            ],
            path: "Sources/SwiftGrep",
        ),
        .testTarget(
            name: "SwiftGrepTests",
            dependencies: [
                "SwiftGrep",
                .product(name: "Tokenizer", package: "GrammarTokenizer"),
            ]
        ),
        .executableTarget(
            name: "sgrep",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Tokenizer", package: "GrammarTokenizer"),
            ]
        ),
    ]
)
