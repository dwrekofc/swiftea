// BindingRegistry - Global account-to-vault binding registry

import Foundation

/// Maps account IDs to vault paths globally
public struct AccountBinding: Codable {
    public let accountId: String
    public let accountType: AccountType
    public let accountName: String
    public let vaultPath: String
    public let boundAt: Date

    public init(accountId: String, accountType: AccountType, accountName: String, vaultPath: String) {
        self.accountId = accountId
        self.accountType = accountType
        self.accountName = accountName
        self.vaultPath = vaultPath
        self.boundAt = Date()
    }
}

/// Global registry file structure
public struct BindingRegistryData: Codable {
    public var version: String
    public var bindings: [AccountBinding]

    public init(version: String = "1.0", bindings: [AccountBinding] = []) {
        self.version = version
        self.bindings = bindings
    }
}

/// Errors that can occur during registry operations
public enum BindingRegistryError: Error, LocalizedError {
    case accountAlreadyBound(accountId: String, existingVault: String)
    case registryWriteFailed(underlying: Error)
    case registryReadFailed(underlying: Error)
    case atomicWriteFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .accountAlreadyBound(let accountId, let existingVault):
            return "Account '\(accountId)' is already bound to vault: \(existingVault)"
        case .registryWriteFailed(let underlying):
            return "Failed to write binding registry: \(underlying.localizedDescription)"
        case .registryReadFailed(let underlying):
            return "Failed to read binding registry: \(underlying.localizedDescription)"
        case .atomicWriteFailed(let underlying):
            return "Failed to atomically update binding registry: \(underlying.localizedDescription)"
        }
    }
}

/// Manages the global account binding registry at ~/.config/swiftea/account-bindings.json
public final class BindingRegistry {
    /// Default registry path
    public static let defaultPath: String = {
        let configDir = ("~/.config/swiftea" as NSString).expandingTildeInPath
        return (configDir as NSString).appendingPathComponent("account-bindings.json")
    }()

    private let registryPath: String
    private let fileManager: FileManager

    public init(registryPath: String = BindingRegistry.defaultPath, fileManager: FileManager = .default) {
        self.registryPath = registryPath
        self.fileManager = fileManager
    }

    /// Check if an account is already bound to a vault
    public func isAccountBound(_ accountId: String) throws -> (bound: Bool, vaultPath: String?) {
        let data = try loadRegistry()
        if let binding = data.bindings.first(where: { $0.accountId == accountId }) {
            return (true, binding.vaultPath)
        }
        return (false, nil)
    }

    /// Get the vault path for a bound account
    public func vaultPath(for accountId: String) throws -> String? {
        let result = try isAccountBound(accountId)
        return result.vaultPath
    }

    /// Bind an account to a vault (fails if already bound to another vault)
    public func bindAccount(_ account: DiscoveredAccount, toVault vaultPath: String) throws {
        var data = try loadRegistry()

        // Check if already bound
        if let existing = data.bindings.first(where: { $0.accountId == account.id }) {
            let existingPath = (existing.vaultPath as NSString).standardizingPath
            let newPath = (vaultPath as NSString).expandingTildeInPath
            let standardNewPath = (newPath as NSString).standardizingPath

            // Allow rebinding to the same vault
            if existingPath != standardNewPath {
                throw BindingRegistryError.accountAlreadyBound(
                    accountId: account.id,
                    existingVault: existing.vaultPath
                )
            }
            return // Already bound to this vault
        }

        // Add new binding
        let absolutePath = ((vaultPath as NSString).expandingTildeInPath as NSString).standardizingPath
        let binding = AccountBinding(
            accountId: account.id,
            accountType: account.type,
            accountName: account.name,
            vaultPath: absolutePath
        )
        data.bindings.append(binding)

        try saveRegistry(data)
    }

    /// Unbind an account from its vault
    public func unbindAccount(_ accountId: String) throws {
        var data = try loadRegistry()
        data.bindings.removeAll { $0.accountId == accountId }
        try saveRegistry(data)
    }

    /// Get all bindings for a specific vault
    public func bindings(forVault vaultPath: String) throws -> [AccountBinding] {
        let data = try loadRegistry()
        let normalizedPath = ((vaultPath as NSString).expandingTildeInPath as NSString).standardizingPath
        return data.bindings.filter {
            ($0.vaultPath as NSString).standardizingPath == normalizedPath
        }
    }

    /// Get all registered bindings
    public func allBindings() throws -> [AccountBinding] {
        let data = try loadRegistry()
        return data.bindings
    }

    /// Load the registry from disk
    private func loadRegistry() throws -> BindingRegistryData {
        // If registry doesn't exist, return empty data
        guard fileManager.fileExists(atPath: registryPath) else {
            return BindingRegistryData()
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: registryPath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(BindingRegistryData.self, from: data)
        } catch {
            throw BindingRegistryError.registryReadFailed(underlying: error)
        }
    }

    /// Save the registry to disk atomically
    private func saveRegistry(_ data: BindingRegistryData) throws {
        // Ensure config directory exists
        let configDir = (registryPath as NSString).deletingLastPathComponent
        do {
            try fileManager.createDirectory(atPath: configDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw BindingRegistryError.registryWriteFailed(underlying: error)
        }

        // Encode data
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData: Data
        do {
            jsonData = try encoder.encode(data)
        } catch {
            throw BindingRegistryError.registryWriteFailed(underlying: error)
        }

        // Write atomically using temp file + rename
        let tempPath = registryPath + ".tmp.\(ProcessInfo.processInfo.processIdentifier)"
        do {
            try jsonData.write(to: URL(fileURLWithPath: tempPath), options: .atomic)
            // Move temp to final location
            if fileManager.fileExists(atPath: registryPath) {
                try fileManager.removeItem(atPath: registryPath)
            }
            try fileManager.moveItem(atPath: tempPath, toPath: registryPath)
        } catch {
            // Clean up temp file if it exists
            try? fileManager.removeItem(atPath: tempPath)
            throw BindingRegistryError.atomicWriteFailed(underlying: error)
        }
    }
}
