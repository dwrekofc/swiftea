import ArgumentParser

public struct Config: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage swiftea configuration"
    )

    @Argument(help: "Config key to get or set")
    var key: String?

    @Argument(help: "Value to set")
    var value: String?

    public init() {}

    public func run() throws {
        if let key = key, let value = value {
            print("Setting \(key) = \(value)")
        } else if let key = key {
            print("Getting value for \(key)")
        } else {
            print("Showing all configuration")
        }
    }
}
