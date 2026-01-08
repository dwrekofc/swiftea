// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftEA",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "swiftea",
            targets: ["SwiftEA"]
        ),
        .library(
            name: "SwiftEAKit",
            targets: ["SwiftEAKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "SwiftEA",
            dependencies: [
                "SwiftEACLI",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "SwiftEACLI",
            dependencies: [
                "SwiftEAKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "SwiftEAKit",
            dependencies: []
        ),
        .testTarget(
            name: "SwiftEAKitTests",
            dependencies: ["SwiftEAKit"]
        )
    ]
)
