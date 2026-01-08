import ArgumentParser

public struct Status: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show swiftea system status"
    )

    public init() {}

    public func run() throws {
        print("SwiftEA Status")
        print("Version: 0.1.0")
        print("Database: Not initialized")
        print("Modules: None active")
    }
}
