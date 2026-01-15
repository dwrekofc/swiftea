import ArgumentParser
import Foundation
import SwiftEAKit

public struct Vault: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "vault",
        abstract: "Manage swea vaults",
        subcommands: [Init.self, VaultStatus.self, VaultBind.self, VaultUnbind.self]
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
            print("    \(VaultManager.databaseFileName)")
            print("  \(VaultManager.dataFolderName)/")
            for folder in VaultManager.canonicalFolders {
                print("    \(folder)/")
            }
            print("")
            print("Vault version: \(config.version)")
            print("")
            print("Next steps:")
            print("  1. Bind accounts with: swea vault bind")
            print("  2. Sync mail data: swea mail sync")
            print("     (or start automatic sync: swea mail sync --watch)")
            print("  3. Export to files: swea mail export")
            print("")
            print("Folder structure:")
            print("  Swiftea/Mail/      - For exported mail files (.md)")
            print("  exports/mail/      - Default export location")
            print("  .swiftea/mail.db   - Synced mail database")
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

            if config.accounts.isEmpty {
                print("No accounts bound.")
                print("Run 'swea vault bind' to bind accounts.")
            } else {
                print("Bound accounts (\(config.accounts.count)):")
                for account in config.accounts {
                    print("  [\(account.type.rawValue)] \(account.name) (\(account.id))")
                }
            }
        } catch {
            throw ValidationError("Failed to read vault config: \(error.localizedDescription)")
        }
    }
}

struct VaultBind: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bind",
        abstract: "Bind accounts to this vault"
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

        // Update vault config
        var config = try vaultManager.readConfig(from: vaultPath)
        if !config.accounts.contains(where: { $0.id == account.id }) {
            config.accounts.append(BoundAccount(id: account.id, type: account.type, name: account.name))
            try vaultManager.writeConfig(config, to: vaultPath)
        }

        let emailStr = account.email.map { " <\($0)>" } ?? ""
        print("  Bound: [\(account.type.rawValue)] \(account.name)\(emailStr)")
    }
}

struct VaultUnbind: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unbind",
        abstract: "Unbind accounts from this vault"
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
