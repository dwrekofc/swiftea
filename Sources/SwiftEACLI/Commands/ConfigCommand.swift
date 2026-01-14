import ArgumentParser
import SwiftEAKit

public struct Config: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage swiftea configuration",
        discussion: """
            Get or set configuration values for the current vault.

            AVAILABLE KEYS:
              mail.dataPath              - Custom path to Apple Mail data directory
              mail.export.format         - Default export format (markdown/json)
              mail.export.outputDir      - Default export output directory
              mail.export.includeAttachments - Include attachments by default (true/false)
              mail.watch.syncInterval    - Watch sync interval in seconds (min: 60)
              mail.watch.enabled         - Enable watch daemon (true/false)

            EXAMPLES:
              swiftea config                           # Show all settings
              swiftea config mail.export.format        # Get a specific setting
              swiftea config mail.export.format json   # Set a setting
              swiftea config --list                    # List available keys
            """
    )

    @Argument(help: "Config key to get or set")
    var key: String?

    @Argument(help: "Value to set")
    var value: String?

    @Flag(name: .long, help: "List all available config keys")
    var list: Bool = false

    public init() {}

    public func run() throws {
        // Handle --list flag
        if list {
            print("Available configuration keys:\n")
            for (key, description) in MailSettings.keys.sorted(by: { $0.key < $1.key }) {
                print("  \(key)")
                print("    \(description)")
                print("")
            }
            return
        }

        let vault = try VaultContext.require()
        let vaultManager = VaultManager()
        var config = try vaultManager.readConfig(from: vault.rootPath)

        if let key = key, let value = value {
            // Set a value
            if let error = config.mail.setValue(value, for: key) {
                print("Error: \(error)")
                throw ExitCode.failure
            }

            // Save updated config
            try vaultManager.writeConfig(config, to: vault.rootPath)
            print("Set \(key) = \(value)")

        } else if let key = key {
            // Get a specific value
            if let value = config.mail.getValue(for: key) {
                print(value)
            } else {
                print("Unknown config key: \(key)")
                print("Use 'swiftea config --list' to see available keys.")
                throw ExitCode.failure
            }

        } else {
            // Show all mail configuration
            print("Mail Configuration:")
            print("===================")
            for key in MailSettings.keys.keys.sorted() {
                let value = config.mail.getValue(for: key) ?? "(not set)"
                let displayValue = value.isEmpty ? "(not set)" : value
                print("  \(key): \(displayValue)")
            }
        }
    }
}
