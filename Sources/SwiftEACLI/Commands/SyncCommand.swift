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
        let vault = VaultContext.optional()
        let dbPath = try GlobalConfigManager().resolvedDatabasePath()

        if status {
            print("Sync status - not yet implemented")
            print("Database: \(dbPath)")
            if let vault = vault {
                print("Vault: \(vault.rootPath)")
            }
        } else {
            print("Syncing all modules")
            print("Database: \(dbPath)")
            if let vault = vault {
                print("Vault: \(vault.rootPath)")
            }
            if watch {
                print("Watch mode requested")
            }
        }
    }
}
