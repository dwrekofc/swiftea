import ArgumentParser
import SwiftEAKit

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
        let vault = try VaultContext.require()
        if status {
            print("Sync status - not yet implemented")
            print("Using vault: \(vault.rootPath)")
        } else {
            print("Syncing all modules")
            print("Using vault: \(vault.rootPath)")
            if watch {
                print("Watch mode requested")
            }
        }
    }
}
