import ArgumentParser
import Foundation
import SwiftEAKit

public struct Vault: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "vault",
        abstract: "Manage swea vaults",
        subcommands: [Init.self, VaultStatus.self, VaultAssign.self, VaultUnassign.self, VaultBind.self, VaultUnbind.self]
    )

    public init() {}
}

/// Top-level init command (also available as `vault init` for backwards compatibility)
public struct Init: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize a new vault in the current directory"
    )

    @Option(name: .long, help: "Path where the vault will be created (defaults to current directory)")
    var path: String?

    @Flag(name: .long, help: "Reinitialize even if vault already exists")
    var force: Bool = false

    public init() {}

    public func run() throws {
        let vaultPath = path ?? FileManager.default.currentDirectoryPath
        let manager = VaultManager()

        do {
            let config = try manager.initializeVault(at: vaultPath, force: force)
            let absolutePath = (vaultPath as NSString).expandingTildeInPath

            print("Initialized vault at: \(absolutePath)")
            print("")
            print("Created:")
            print("  \(VaultManager.vaultDirName)/")
            print("    \(VaultManager.configFileName)")
            print("  \(VaultManager.dataFolderName)/")
            for folder in VaultManager.canonicalFolders {
                print("    \(folder)/")
            }
            print("")
            print("Vault version: \(config.version)")
            print("")
            print("Next steps:")
            print("  1. Assign accounts with: swea vault assign")
            print("  2. Sync mail data: swea mail sync")
            print("     (or start automatic sync: swea mail sync --watch)")
            print("  3. Export to files: swea mail export")
            print("")
            print("Mail database is stored globally at:")
            print("  ~/Library/Application Support/swiftea/mail.db")
            print("")
            print("Vault view filter controls which accounts/mailboxes appear")
            print("when running mail commands from this vault.")
        } catch let error as VaultError {
            throw ValidationError(error.localizedDescription)
        }
    }
}

struct VaultStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show vault status"
    )

    @Option(name: .long, help: "Vault path (defaults to current directory)")
    var path: String?

    func run() throws {
        let vaultPath = path ?? FileManager.default.currentDirectoryPath
        let manager = VaultManager()

        guard manager.isVault(at: vaultPath) else {
            print("Not a vault: \(vaultPath)")
            print("Run 'swea init' to create a vault here.")
            throw ExitCode.failure
        }

        do {
            let config = try manager.readConfig(from: vaultPath)
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

            print("Vault: \(vaultPath)")
            print("Version: \(config.version)")
            print("Created: \(dateFormatter.string(from: config.createdAt))")
            print("")

            // Show view filter
            if let viewFilter = config.mail.viewFilter, !viewFilter.isUnfiltered {
                print("View Filter:")
                if !viewFilter.accounts.isEmpty {
                    print("  Accounts: \(viewFilter.accounts.joined(separator: ", "))")
                }
                if !viewFilter.includeAllMailboxes && !viewFilter.mailboxes.isEmpty {
                    print("  Mailboxes: \(viewFilter.mailboxes.joined(separator: ", "))")
                } else {
                    print("  Mailboxes: all")
                }
            } else if !config.accounts.isEmpty {
                // Legacy v1 format
                print("Bound accounts (legacy, run 'swea vault assign' to migrate):")
                for account in config.accounts {
                    print("  [\(account.type.rawValue)] \(account.name) (\(account.id))")
                }
            } else {
                print("No view filter configured (showing all mail).")
                print("Run 'swea vault assign' to select accounts for this vault.")
            }

            print("")
            print("Global database: \(GlobalConfigManager.defaultDatabasePath)")
        } catch {
            throw ValidationError("Failed to read vault config: \(error.localizedDescription)")
        }
    }
}

// MARK: - Vault Assign (v2 - sets view filter)

struct VaultAssign: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "assign",
        abstract: "Assign accounts to this vault's view filter",
        discussion: """
            Selects which mail accounts (and optionally mailboxes) this vault
            displays from the global database.

            The global database contains ALL accounts. The vault's view filter
            controls which subset appears in inbox, search, and thread commands
            when running from this vault.

            EXAMPLES:
              swea vault assign                    # Interactive selection
              swea vault assign --account iCloud   # Assign specific account
              swea vault assign --list             # List available accounts
            """
    )

    @Option(name: .long, help: "Vault path (defaults to current directory)")
    var path: String?

    @Option(name: .long, help: "Account ID to assign (skips interactive selection)")
    var account: String?

    @Flag(name: .long, help: "List available accounts without assigning")
    var list: Bool = false

    func run() throws {
        let vaultPath = path ?? FileManager.default.currentDirectoryPath
        let vaultManager = VaultManager()
        let discovery = AccountDiscovery()

        guard vaultManager.isVault(at: vaultPath) else {
            print("Not a vault: \(vaultPath)")
            print("Run 'swea init' to create a vault first.")
            throw ExitCode.failure
        }

        // Discover available accounts
        print("Discovering accounts...")
        let accounts = try discovery.discoverMailAccounts()

        if accounts.isEmpty {
            print("No Mail accounts found.")
            print("Configure accounts in System Settings > Internet Accounts.")
            throw ExitCode.failure
        }

        var config = try vaultManager.readConfig(from: vaultPath)
        let currentFilter = config.mail.viewFilter ?? MailViewFilter()
        let currentAccounts = Set(currentFilter.accounts)

        // If --list flag, show accounts and current filter
        if list {
            print("\nAvailable mail accounts:")
            for (index, acct) in accounts.enumerated() {
                let emailStr = acct.email.map { " <\($0)>" } ?? ""
                let assigned = currentAccounts.contains(acct.id) ? " [assigned]" : ""
                print("  \(index + 1). \(acct.name)\(emailStr) (id: \(acct.id))\(assigned)")
            }
            return
        }

        // If --account specified, add just that account
        if let accountId = account {
            guard accounts.contains(where: { $0.id == accountId }) else {
                print("Account not found: \(accountId)")
                print("\nAvailable accounts:")
                for acct in accounts {
                    print("  \(acct.id) - \(acct.name)")
                }
                throw ExitCode.failure
            }

            var newAccounts = currentFilter.accounts
            if !newAccounts.contains(accountId) {
                newAccounts.append(accountId)
            }
            config.mail.viewFilter = MailViewFilter(
                accounts: newAccounts,
                mailboxes: currentFilter.mailboxes,
                includeAllMailboxes: currentFilter.includeAllMailboxes
            )
            try vaultManager.writeConfig(config, to: vaultPath)
            print("Assigned account '\(accountId)' to vault view filter.")
            return
        }

        // Interactive selection
        print("\nAvailable mail accounts (enter numbers to select, comma-separated):")
        for (index, acct) in accounts.enumerated() {
            let emailStr = acct.email.map { " <\($0)>" } ?? ""
            let assigned = currentAccounts.contains(acct.id) ? " [assigned]" : ""
            print("  \(index + 1). \(acct.name)\(emailStr) (id: \(acct.id))\(assigned)")
        }

        print("\nEnter selection (e.g., 1,2,3) or 'all' for all accounts: ", terminator: "")

        guard let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty else {
            print("No selection made.")
            return
        }

        let selectedAccounts: [DiscoveredAccount]
        if input.lowercased() == "all" {
            selectedAccounts = accounts
        } else {
            let indices = input.split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .map { $0 - 1 }
                .filter { $0 >= 0 && $0 < accounts.count }
            selectedAccounts = indices.map { accounts[$0] }
        }

        if selectedAccounts.isEmpty {
            print("No valid accounts selected.")
            return
        }

        let selectedIds = selectedAccounts.map { $0.id }
        config.mail.viewFilter = MailViewFilter(
            accounts: selectedIds,
            mailboxes: [],
            includeAllMailboxes: true
        )
        try vaultManager.writeConfig(config, to: vaultPath)

        print("\nView filter updated with \(selectedIds.count) account(s):")
        for acct in selectedAccounts {
            let emailStr = acct.email.map { " <\($0)>" } ?? ""
            print("  \(acct.name)\(emailStr)")
        }
    }
}

struct VaultUnassign: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unassign",
        abstract: "Clear or modify the vault's view filter",
        discussion: """
            Removes accounts from the vault's view filter.
            Use without arguments to clear the entire filter (show all mail).

            EXAMPLES:
              swea vault unassign                    # Clear entire filter
              swea vault unassign iCloud             # Remove specific account
            """
    )

    @Option(name: .long, help: "Vault path (defaults to current directory)")
    var path: String?

    @Argument(help: "Account ID to remove from filter (omit to clear all)")
    var accountId: String?

    func run() throws {
        let vaultPath = path ?? FileManager.default.currentDirectoryPath
        let vaultManager = VaultManager()

        guard vaultManager.isVault(at: vaultPath) else {
            print("Not a vault: \(vaultPath)")
            throw ExitCode.failure
        }

        var config = try vaultManager.readConfig(from: vaultPath)

        if let accountId = accountId {
            // Remove specific account
            var filter = config.mail.viewFilter ?? MailViewFilter()
            filter.accounts.removeAll { $0 == accountId }
            config.mail.viewFilter = filter
            try vaultManager.writeConfig(config, to: vaultPath)
            print("Removed account '\(accountId)' from view filter.")
        } else {
            // Clear entire filter
            config.mail.viewFilter = nil
            try vaultManager.writeConfig(config, to: vaultPath)
            print("View filter cleared. All mail will be shown.")
        }
    }
}

// MARK: - Legacy Bind/Unbind (deprecated, kept for backward compatibility)

struct VaultBind: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bind",
        abstract: "Bind accounts to this vault (deprecated, use 'vault assign')"
    )

    @Option(name: .long, help: "Vault path (defaults to current directory)")
    var path: String?

    @Option(name: .long, help: "Account ID to bind (skips interactive selection)")
    var account: String?

    @Flag(name: .long, help: "List available accounts without binding")
    var list: Bool = false

    func run() throws {
        let vaultPath = path ?? FileManager.default.currentDirectoryPath
        let vaultManager = VaultManager()
        let discovery = AccountDiscovery()
        let registry = BindingRegistry()

        // Verify vault exists
        guard vaultManager.isVault(at: vaultPath) else {
            print("Not a vault: \(vaultPath)")
            print("Run 'swea init' to create a vault first.")
            throw ExitCode.failure
        }

        let absoluteVaultPath = ((vaultPath as NSString).expandingTildeInPath as NSString).standardizingPath

        // Discover available accounts
        print("Discovering accounts...")
        let accounts = try discovery.discoverAllAccounts()

        if accounts.isEmpty {
            print("No Mail or Calendar accounts found.")
            print("Configure accounts in System Settings > Internet Accounts.")
            throw ExitCode.failure
        }

        // If --list flag, just show accounts and exit
        if list {
            print("\nAvailable accounts:")
            for (index, acct) in accounts.enumerated() {
                let emailStr = acct.email.map { " <\($0)>" } ?? ""
                let boundStatus = try checkBoundStatus(acct, registry: registry, currentVault: absoluteVaultPath)
                print("  \(index + 1). [\(acct.type.rawValue)] \(acct.name)\(emailStr)\(boundStatus)")
            }
            return
        }

        // If --account specified, bind just that account
        if let accountId = account {
            guard let acct = accounts.first(where: { $0.id == accountId }) else {
                print("Account not found: \(accountId)")
                print("\nAvailable accounts:")
                for acct in accounts {
                    print("  \(acct.id) - \(acct.name)")
                }
                throw ExitCode.failure
            }

            try bindAccount(acct, toVault: absoluteVaultPath, vaultManager: vaultManager, registry: registry)
            return
        }

        // Interactive selection
        print("\nAvailable accounts (enter numbers to select, comma-separated):")
        for (index, acct) in accounts.enumerated() {
            let emailStr = acct.email.map { " <\($0)>" } ?? ""
            let boundStatus = try checkBoundStatus(acct, registry: registry, currentVault: absoluteVaultPath)
            print("  \(index + 1). [\(acct.type.rawValue)] \(acct.name)\(emailStr)\(boundStatus)")
        }

        print("\nEnter selection (e.g., 1,2,3) or 'all' for all accounts: ", terminator: "")

        guard let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty else {
            print("No selection made.")
            return
        }

        let selectedAccounts: [DiscoveredAccount]
        if input.lowercased() == "all" {
            selectedAccounts = accounts
        } else {
            let indices = input.split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .map { $0 - 1 } // Convert to 0-based index
                .filter { $0 >= 0 && $0 < accounts.count }

            selectedAccounts = indices.map { accounts[$0] }
        }

        if selectedAccounts.isEmpty {
            print("No valid accounts selected.")
            return
        }

        // Bind selected accounts
        var boundCount = 0
        var skippedCount = 0

        for acct in selectedAccounts {
            do {
                try bindAccount(acct, toVault: absoluteVaultPath, vaultManager: vaultManager, registry: registry)
                boundCount += 1
            } catch let error as BindingRegistryError {
                print("  Skipped \(acct.name): \(error.localizedDescription)")
                skippedCount += 1
            }
        }

        print("\nBound \(boundCount) account(s) to vault.")
        if skippedCount > 0 {
            print("Skipped \(skippedCount) account(s) (already bound to other vaults).")
        }
    }

    private func checkBoundStatus(_ account: DiscoveredAccount, registry: BindingRegistry, currentVault: String) throws -> String {
        let (bound, vaultPath) = try registry.isAccountBound(account.id)
        if bound {
            if let path = vaultPath, (path as NSString).standardizingPath == currentVault {
                return " [bound to this vault]"
            } else {
                return " [bound to another vault]"
            }
        }
        return ""
    }

    private func bindAccount(_ account: DiscoveredAccount, toVault vaultPath: String, vaultManager: VaultManager, registry: BindingRegistry) throws {
        // Update global registry
        try registry.bindAccount(account, toVault: vaultPath)

        // Update vault config (legacy accounts array + v2 viewFilter)
        var config = try vaultManager.readConfig(from: vaultPath)
        if !config.accounts.contains(where: { $0.id == account.id }) {
            config.accounts.append(BoundAccount(id: account.id, type: account.type, name: account.name))
        }

        // Also update v2 viewFilter for mail accounts
        if account.type == .mail {
            var filter = config.mail.viewFilter ?? MailViewFilter()
            if !filter.accounts.contains(account.id) {
                filter.accounts.append(account.id)
                config.mail.viewFilter = filter
            }
        }

        try vaultManager.writeConfig(config, to: vaultPath)

        let emailStr = account.email.map { " <\($0)>" } ?? ""
        print("  Bound: [\(account.type.rawValue)] \(account.name)\(emailStr)")
    }
}

struct VaultUnbind: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unbind",
        abstract: "Unbind accounts from this vault (deprecated, use 'vault unassign')"
    )

    @Option(name: .long, help: "Vault path (defaults to current directory)")
    var path: String?

    @Argument(help: "Account ID to unbind")
    var accountId: String

    func run() throws {
        let vaultPath = path ?? FileManager.default.currentDirectoryPath
        let vaultManager = VaultManager()
        let registry = BindingRegistry()

        // Verify vault exists
        guard vaultManager.isVault(at: vaultPath) else {
            print("Not a vault: \(vaultPath)")
            throw ExitCode.failure
        }

        let absoluteVaultPath = ((vaultPath as NSString).expandingTildeInPath as NSString).standardizingPath

        // Check if account is bound to this vault
        let (bound, existingVault) = try registry.isAccountBound(accountId)
        if !bound {
            print("Account '\(accountId)' is not bound to any vault.")
            throw ExitCode.failure
        }

        if let vault = existingVault, (vault as NSString).standardizingPath != absoluteVaultPath {
            print("Account '\(accountId)' is bound to a different vault: \(vault)")
            throw ExitCode.failure
        }

        // Unbind from registry
        try registry.unbindAccount(accountId)

        // Update vault config
        var config = try vaultManager.readConfig(from: vaultPath)
        config.accounts.removeAll { $0.id == accountId }
        try vaultManager.writeConfig(config, to: vaultPath)

        print("Unbound account: \(accountId)")
    }
}
