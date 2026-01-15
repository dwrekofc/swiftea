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
            name: "swea",
            targets: ["SwiftEA"]
        ),
        .library(
            name: "SwiftEAKit",
            targets: ["SwiftEAKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/tursodatabase/libsql-swift", from: "0.3.0"),
        // Calendar module dependencies
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/swift-calendar/icalendarkit.git", from: "1.0.0")
        // Note: RWMRecurrenceRule omitted - no valid SPM support. EventKit handles recurrence expansion.
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
            dependencies: [
                .product(name: "Libsql", package: "libsql-swift"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ICalendarKit", package: "icalendarkit")
            ]
        ),
        .testTarget(
            name: "SwiftEAKitTests",
            dependencies: ["SwiftEAKit"]
        ),
        .testTarget(
            name: "SwiftEACLITests",
            dependencies: [
                "SwiftEACLI",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
