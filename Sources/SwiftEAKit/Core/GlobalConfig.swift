// GlobalConfig - Global configuration manager for centralized swiftea settings

import Foundation

/// Global configuration for swiftea, stored at ~/.config/swiftea/global-config.json
public struct GlobalConfig: Codable {
    public var version: String
    public var database: DatabaseConfig
    public var mail: GlobalMailConfig

    public init(
        version: String = "1.0",
        database: DatabaseConfig = DatabaseConfig(),
        mail: GlobalMailConfig = GlobalMailConfig()
    ) {
        self.version = version
        self.database = database
        self.mail = mail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "1.0"
        database = try container.decodeIfPresent(DatabaseConfig.self, forKey: .database) ?? DatabaseConfig()
        mail = try container.decodeIfPresent(GlobalMailConfig.self, forKey: .mail) ?? GlobalMailConfig()
    }
}

/// Database configuration
public struct DatabaseConfig: Codable {
    /// Optional override for the database path (default: ~/Library/Application Support/swiftea/mail.db)
    public var path: String?

    public init(path: String? = nil) {
        self.path = path
    }
}

/// Global mail configuration (settings that apply to all accounts, not per-vault)
public struct GlobalMailConfig: Codable {
    /// Custom path to Apple Mail data directory (nil = auto-detect)
    public var mailDataPath: String?

    /// Watch daemon sync interval in seconds
    public var watchSyncInterval: Int

    /// Whether watch daemon is enabled
    public var watchEnabled: Bool

    /// Available config keys for global mail settings
    public static let keys: [String: String] = [
        "database.path": "Override path for the global mail database",
        "mail.dataPath": "Custom path to Apple Mail data directory (auto-detect if empty)",
        "mail.watch.syncInterval": "Watch sync interval in seconds (default: 300, min: 60)",
        "mail.watch.enabled": "Enable watch daemon: true or false"
    ]

    public init(
        mailDataPath: String? = nil,
        watchSyncInterval: Int = 300,
        watchEnabled: Bool = true
    ) {
        self.mailDataPath = mailDataPath
        self.watchSyncInterval = watchSyncInterval
        self.watchEnabled = watchEnabled
    }

    /// Get a setting value by key
    public func getValue(for key: String) -> String? {
        switch key {
        case "mail.dataPath":
            return mailDataPath
        case "mail.watch.syncInterval":
            return String(watchSyncInterval)
        case "mail.watch.enabled":
            return watchEnabled ? "true" : "false"
        default:
            return nil
        }
    }

    /// Set a setting value by key, returns error message if invalid
    public mutating func setValue(_ value: String, for key: String) -> String? {
        switch key {
        case "mail.dataPath":
            mailDataPath = value.isEmpty ? nil : value
            return nil
        case "mail.watch.syncInterval":
            if let interval = Int(value), interval >= 60 {
                watchSyncInterval = interval
                return nil
            }
            return "Invalid interval: \(value). Must be a number >= 60."
        case "mail.watch.enabled":
            if let bool = parseBool(value) {
                watchEnabled = bool
                return nil
            }
            return "Invalid value: \(value). Must be 'true' or 'false'."
        default:
            return "Unknown key: \(key)"
        }
    }

    private func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "1", "yes", "on":
            return true
        case "false", "0", "no", "off":
            return false
        default:
            return nil
        }
    }
}

/// Manages the global configuration at ~/.config/swiftea/global-config.json
public final class GlobalConfigManager {
    /// Default config path
    public static let defaultConfigPath: String = {
        let configDir = ("~/.config/swiftea" as NSString).expandingTildeInPath
        return (configDir as NSString).appendingPathComponent("global-config.json")
    }()

    /// Default database directory
    public static let defaultDatabaseDir: String = {
        let homeDir = NSHomeDirectory()
        return "\(homeDir)/Library/Application Support/swiftea"
    }()

    /// Default database path
    public static let defaultDatabasePath: String = {
        return (defaultDatabaseDir as NSString).appendingPathComponent("mail.db")
    }()

    /// Default log directory
    public static let defaultLogDir: String = {
        let homeDir = NSHomeDirectory()
        return "\(homeDir)/Library/Logs/swiftea"
    }()

    private let configPath: String
    private let fileManager: FileManager

    public init(configPath: String = GlobalConfigManager.defaultConfigPath, fileManager: FileManager = .default) {
        self.configPath = configPath
        self.fileManager = fileManager
    }

    /// Get the resolved database path from config or default
    public func resolvedDatabasePath() throws -> String {
        let config = try loadConfig()
        if let customPath = config.database.path, !customPath.isEmpty {
            return (customPath as NSString).expandingTildeInPath
        }
        return Self.defaultDatabasePath
    }

    /// Ensure all required directories exist
    public func ensureDirectories() throws {
        // Ensure config directory
        let configDir = (configPath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: configDir) {
            try fileManager.createDirectory(atPath: configDir, withIntermediateDirectories: true, attributes: nil)
        }

        // Ensure database directory
        let dbPath = try resolvedDatabasePath()
        let dbDir = (dbPath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: dbDir) {
            try fileManager.createDirectory(atPath: dbDir, withIntermediateDirectories: true, attributes: nil)
        }

        // Ensure log directory
        if !fileManager.fileExists(atPath: Self.defaultLogDir) {
            try fileManager.createDirectory(atPath: Self.defaultLogDir, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// Load the global config from disk, creating defaults if not found
    public func loadConfig() throws -> GlobalConfig {
        guard fileManager.fileExists(atPath: configPath) else {
            let defaultConfig = GlobalConfig()
            try saveConfig(defaultConfig)
            return defaultConfig
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let decoder = JSONDecoder()
        return try decoder.decode(GlobalConfig.self, from: data)
    }

    /// Save the global config to disk
    public func saveConfig(_ config: GlobalConfig) throws {
        // Ensure config directory exists
        let configDir = (configPath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: configDir) {
            try fileManager.createDirectory(atPath: configDir, withIntermediateDirectories: true, attributes: nil)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
    }

    /// Get a global config value by key
    public func getValue(for key: String) throws -> String? {
        let config = try loadConfig()
        switch key {
        case "database.path":
            return config.database.path ?? Self.defaultDatabasePath
        default:
            return config.mail.getValue(for: key)
        }
    }

    /// Set a global config value by key
    public func setValue(_ value: String, for key: String) throws -> String? {
        var config = try loadConfig()
        switch key {
        case "database.path":
            config.database.path = value.isEmpty ? nil : value
            try saveConfig(config)
            return nil
        default:
            if let error = config.mail.setValue(value, for: key) {
                return error
            }
            try saveConfig(config)
            return nil
        }
    }
}
