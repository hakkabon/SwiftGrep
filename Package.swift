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
    ],
    targets: [
        .target(
            name: "SwiftGrep",
            dependencies: [
            ],
            path: "Sources/SwiftGrep",
        ),
        .testTarget(
            name: "SwiftGrepTests",
            dependencies: ["SwiftGrep"]
        ),
        .executableTarget(
            name: "sgrep",
            dependencies: [
                "SwiftGrep",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
