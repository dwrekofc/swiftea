// VaultContext - Centralized vault context detection and gating

import Foundation

/// Error thrown when a command requires a vault but none is found
public struct NoVaultContextError: Error, LocalizedError {
    public let currentDirectory: String

    public init(currentDirectory: String = FileManager.default.currentDirectoryPath) {
        self.currentDirectory = currentDirectory
    }

    public var errorDescription: String? {
        """
        No vault context found.

        This command requires a swea vault, but no vault was found in:
          \(currentDirectory)

        To fix this:
          1. Navigate to a vault root directory (containing .swiftea/), or
          2. Create a new vault with: swea init --path <vault>

        Note: swea requires the current directory to be the vault root.
        Running from a subdirectory within a vault is not supported.
        """
    }
}

/// Represents a resolved vault context
public struct VaultContext {
    /// The vault root path (directory containing .swiftea/)
    public let rootPath: String

    /// The vault configuration
    public let config: VaultConfig

    /// The VaultManager instance
    public let manager: VaultManager

    /// Path to the vault's database
    public var databasePath: String {
        manager.databasePath(for: rootPath)
    }

    /// Path to the vault's data folder (Swiftea/)
    public var dataFolderPath: String {
        manager.dataFolder(for: rootPath)
    }

    private init(rootPath: String, config: VaultConfig, manager: VaultManager) {
        self.rootPath = rootPath
        self.config = config
        self.manager = manager
    }

    /// Require a vault context from the current working directory.
    /// Throws NoVaultContextError if no vault is found.
    ///
    /// - Note: This only checks the exact CWD, not parent directories.
    public static func require() throws -> VaultContext {
        try require(at: FileManager.default.currentDirectoryPath)
    }

    /// Require a vault context at the specified path.
    /// Throws NoVaultContextError if no vault is found.
    ///
    /// - Parameter path: The path to check for a vault (must be the vault root)
    public static func require(at path: String) throws -> VaultContext {
        let manager = VaultManager()
        let expandedPath = (path as NSString).expandingTildeInPath
        let absolutePath = (expandedPath as NSString).standardizingPath

        guard manager.isVault(at: absolutePath) else {
            throw NoVaultContextError(currentDirectory: absolutePath)
        }

        let config = try manager.readConfig(from: absolutePath)
        return VaultContext(rootPath: absolutePath, config: config, manager: manager)
    }

    /// Check if a vault exists at the current working directory without throwing.
    public static func exists() -> Bool {
        exists(at: FileManager.default.currentDirectoryPath)
    }

    /// Check if a vault exists at the specified path without throwing.
    public static func exists(at path: String) -> Bool {
        let manager = VaultManager()
        return manager.isVault(at: path)
    }
}
