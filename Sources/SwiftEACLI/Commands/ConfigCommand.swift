import ArgumentParser
import SwiftEAKit

public struct Config: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage swea configuration",
        discussion: """
            Get or set configuration values. Settings are split into:

            GLOBAL SETTINGS (use --global or auto-detected):
              database.path               - Override path for the global mail database
              mail.dataPath               - Custom path to Apple Mail data directory
              mail.watch.syncInterval     - Watch sync interval in seconds (min: 60)
              mail.watch.enabled          - Enable watch daemon (true/false)

            VAULT SETTINGS (requires vault context):
              mail.export.format          - Default export format (markdown/json)
              mail.export.outputDir       - Default export output directory
              mail.export.includeAttachments - Include attachments by default (true/false)

            EXAMPLES:
              swea config                           # Show all settings
              swea config --global                  # Show global settings
              swea config --global mail.dataPath    # Get a global setting
              swea config --global mail.watch.syncInterval 120  # Set global setting
              swea config mail.export.format        # Get a vault setting
              swea config mail.export.format json   # Set a vault setting
              swea config --list                    # List available keys
            """
    )

    @Argument(help: "Config key to get or set")
    var key: String?

    @Argument(help: "Value to set")
    var value: String?

    @Flag(name: .long, help: "List all available config keys")
    var list: Bool = false

    @Flag(name: .long, help: "Operate on global configuration (applies to all vaults)")
    var global: Bool = false

    public init() {}

    /// Check if a key is a global config key
    private func isGlobalKey(_ key: String) -> Bool {
        GlobalMailConfig.keys.keys.contains(key) || key == "database.path"
    }

    public func run() throws {
        // Handle --list flag
        if list {
            print("Global configuration keys:\n")
            for (key, description) in GlobalMailConfig.keys.sorted(by: { $0.key < $1.key }) {
                print("  \(key)")
                print("    \(description)")
                print("")
            }

            print("Vault configuration keys:\n")
            for (key, description) in MailSettings.keys.sorted(by: { $0.key < $1.key }) {
                print("  \(key)")
                print("    \(description)")
                print("")
            }
            return
        }

        // Auto-detect global vs vault based on key or flag
        let useGlobal = global || (key != nil && isGlobalKey(key!))

        if useGlobal {
            try runGlobal()
        } else {
            try runVault()
        }
    }

    private func runGlobal() throws {
        let configManager = GlobalConfigManager()

        if let key = key, let value = value {
            // Set a global value
            if let error = try configManager.setValue(value, for: key) {
                print("Error: \(error)")
                throw ExitCode.failure
            }
            print("Set \(key) = \(value) (global)")

        } else if let key = key {
            // Get a specific global value
            if let value = try configManager.getValue(for: key) {
                print(value)
            } else {
                print("Unknown global config key: \(key)")
                print("Use 'swea config --list' to see available keys.")
                throw ExitCode.failure
            }

        } else {
            // Show all global configuration
            let config = try configManager.loadConfig()
            print("Global Configuration:")
            print("=====================")
            print("  database.path: \(config.database.path ?? GlobalConfigManager.defaultDatabasePath)")
            for key in GlobalMailConfig.keys.keys.sorted() where key != "database.path" {
                let value = config.mail.getValue(for: key) ?? "(not set)"
                let displayValue = value.isEmpty ? "(not set)" : value
                print("  \(key): \(displayValue)")
            }
        }
    }

    private func runVault() throws {
        let vault = try VaultContext.require()
        let vaultManager = VaultManager()
        var config = try vaultManager.readConfig(from: vault.rootPath)

        if let key = key, let value = value {
            // Check if this is a deprecated key that moved to global
            if let deprecationMsg = MailSettings.deprecatedKeys[key] {
                print("Warning: \(deprecationMsg)")
                print("Setting in vault config for backward compatibility.")
            }

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
                print("Use 'swea config --list' to see available keys.")
                throw ExitCode.failure
            }

        } else {
            // Show all vault mail configuration
            print("Vault Configuration:")
            print("====================")
            for key in MailSettings.keys.keys.sorted() {
                let value = config.mail.getValue(for: key) ?? "(not set)"
                let displayValue = value.isEmpty ? "(not set)" : value
                print("  \(key): \(displayValue)")
            }

            // Show view filter if set
            if let viewFilter = config.mail.viewFilter {
                print("")
                print("View Filter:")
                if !viewFilter.accounts.isEmpty {
                    print("  Accounts: \(viewFilter.accounts.joined(separator: ", "))")
                }
                if !viewFilter.includeAllMailboxes && !viewFilter.mailboxes.isEmpty {
                    print("  Mailboxes: \(viewFilter.mailboxes.joined(separator: ", "))")
                }
                if viewFilter.includeAllMailboxes {
                    print("  Mailboxes: all")
                }
            }
        }
    }
}
