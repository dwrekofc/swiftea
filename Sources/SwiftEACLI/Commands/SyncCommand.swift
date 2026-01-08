import ArgumentParser

public struct Sync: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync all modules with Apple data sources"
    )

    @Flag(name: .long, help: "Watch for changes")
    var watch: Bool = false

    @Flag(name: .long, help: "Show sync status")
    var status: Bool = false

    public init() {}

    public func run() throws {
        if status {
            print("Sync status - not yet implemented")
        } else {
            print("Syncing all modules")
            if watch {
                print("Watch mode requested")
            }
        }
    }
}
