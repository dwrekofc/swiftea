// VaultManager - Handles vault lifecycle operations

import Foundation

/// Errors that can occur during vault operations
public enum VaultError: Error, LocalizedError {
    case alreadyExists(path: String)
    case creationFailed(path: String, underlying: Error)
    case configWriteFailed(underlying: Error)
    case databaseCreationFailed(underlying: Error)
    case invalidPath(path: String)
    case notAVault(path: String)

    public var errorDescription: String? {
        switch self {
        case .alreadyExists(let path):
            return "Vault already exists at: \(path)"
        case .creationFailed(let path, let underlying):
            return "Failed to create vault at \(path): \(underlying.localizedDescription)"
        case .configWriteFailed(let underlying):
            return "Failed to write vault config: \(underlying.localizedDescription)"
        case .databaseCreationFailed(let underlying):
            return "Failed to create vault database: \(underlying.localizedDescription)"
        case .invalidPath(let path):
            return "Invalid vault path: \(path)"
        case .notAVault(let path):
            return "Not a valid vault: \(path) (missing .swiftea directory)"
        }
    }
}

/// Configuration for a SwiftEA vault
public struct VaultConfig: Codable {
    public let version: String
    public let createdAt: Date
    public var accounts: [BoundAccount]

    public init(version: String = "1.0", accounts: [BoundAccount] = []) {
        self.version = version
        self.createdAt = Date()
        self.accounts = accounts
    }
}

/// An account bound to a vault
public struct BoundAccount: Codable {
    public let id: String
    public let type: AccountType
    public let name: String

    public init(id: String, type: AccountType, name: String) {
        self.id = id
        self.type = type
        self.name = name
    }
}

/// Type of account (Mail or Calendar)
public enum AccountType: String, Codable {
    case mail
    case calendar
}

/// Manages vault initialization, detection, and configuration
public final class VaultManager {
    /// Hidden directory name within a vault
    public static let vaultDirName = ".swiftea"
    /// Config file name
    public static let configFileName = "config.json"
    /// Database file name
    public static let databaseFileName = "swiftea.db"
    /// Data folder name within vault root
    public static let dataFolderName = "Swiftea"

    /// Canonical subdirectories under the data folder
    public static let canonicalFolders = [
        "Mail",
        "Calendar",
        "Contacts",
        "Exports"
    ]

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Check if a path contains a valid vault
    public func isVault(at path: String) -> Bool {
        let vaultDir = (path as NSString).appendingPathComponent(Self.vaultDirName)
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: vaultDir, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Get the vault directory path (.swiftea)
    public func vaultDirectory(for basePath: String) -> String {
        (basePath as NSString).appendingPathComponent(Self.vaultDirName)
    }

    /// Get the config file path
    public func configPath(for basePath: String) -> String {
        (vaultDirectory(for: basePath) as NSString).appendingPathComponent(Self.configFileName)
    }

    /// Get the database file path
    public func databasePath(for basePath: String) -> String {
        (vaultDirectory(for: basePath) as NSString).appendingPathComponent(Self.databaseFileName)
    }

    /// Get the data folder path (Swiftea/)
    public func dataFolder(for basePath: String) -> String {
        (basePath as NSString).appendingPathComponent(Self.dataFolderName)
    }

    /// Initialize a new vault at the specified path
    /// - Parameter path: The path where the vault should be created
    /// - Parameter force: If true, reinitialize even if vault exists
    /// - Returns: The created VaultConfig
    @discardableResult
    public func initializeVault(at path: String, force: Bool = false) throws -> VaultConfig {
        let expandedPath = (path as NSString).expandingTildeInPath
        let absolutePath = (expandedPath as NSString).standardizingPath

        // Check if vault already exists
        if !force && isVault(at: absolutePath) {
            throw VaultError.alreadyExists(path: absolutePath)
        }

        // Create the vault directory structure
        let vaultDir = vaultDirectory(for: absolutePath)
        do {
            try fileManager.createDirectory(atPath: vaultDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw VaultError.creationFailed(path: vaultDir, underlying: error)
        }

        // Create config file
        let config = VaultConfig()
        try writeConfig(config, to: absolutePath)

        // Create empty database file
        try createDatabase(at: absolutePath)

        // Create canonical folder layout
        try createCanonicalFolders(at: absolutePath)

        return config
    }

    /// Write vault configuration to disk
    public func writeConfig(_ config: VaultConfig, to basePath: String) throws {
        let configFile = configPath(for: basePath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(config)
            try data.write(to: URL(fileURLWithPath: configFile))
        } catch {
            throw VaultError.configWriteFailed(underlying: error)
        }
    }

    /// Read vault configuration from disk
    public func readConfig(from basePath: String) throws -> VaultConfig {
        let configFile = configPath(for: basePath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try Data(contentsOf: URL(fileURLWithPath: configFile))
        return try decoder.decode(VaultConfig.self, from: data)
    }

    /// Create the vault database file
    private func createDatabase(at basePath: String) throws {
        let dbPath = databasePath(for: basePath)

        // Create empty database file (will be initialized with schema later)
        if !fileManager.createFile(atPath: dbPath, contents: nil, attributes: nil) {
            throw VaultError.databaseCreationFailed(
                underlying: NSError(domain: "VaultManager", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create database file"
                ])
            )
        }
    }

    /// Create the canonical folder structure
    private func createCanonicalFolders(at basePath: String) throws {
        let dataDir = dataFolder(for: basePath)

        for folder in Self.canonicalFolders {
            let folderPath = (dataDir as NSString).appendingPathComponent(folder)
            do {
                try fileManager.createDirectory(atPath: folderPath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                throw VaultError.creationFailed(path: folderPath, underlying: error)
            }
        }
    }

    /// Find the vault root by searching up from the given path
    public func findVaultRoot(from path: String) -> String? {
        var currentPath = (path as NSString).expandingTildeInPath
        currentPath = (currentPath as NSString).standardizingPath

        while currentPath != "/" {
            if isVault(at: currentPath) {
                return currentPath
            }
            currentPath = (currentPath as NSString).deletingLastPathComponent
        }

        return nil
    }
}
