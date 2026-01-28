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
    public var mail: MailSettings
    public var calendar: CalendarSettings
    public var ai: AISettings

    public init(
        version: String = "1.0",
        accounts: [BoundAccount] = [],
        mail: MailSettings = MailSettings(),
        calendar: CalendarSettings = CalendarSettings(),
        ai: AISettings = AISettings()
    ) {
        self.version = version
        self.createdAt = Date()
        self.accounts = accounts
        self.mail = mail
        self.calendar = calendar
        self.ai = ai
    }

    /// Handle decoding with optional settings for backward compatibility
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        accounts = try container.decodeIfPresent([BoundAccount].self, forKey: .accounts) ?? []
        mail = try container.decodeIfPresent(MailSettings.self, forKey: .mail) ?? MailSettings()
        calendar = try container.decodeIfPresent(CalendarSettings.self, forKey: .calendar) ?? CalendarSettings()
        ai = try container.decodeIfPresent(AISettings.self, forKey: .ai) ?? AISettings()
    }
}

/// Mail-specific configuration settings for a vault
public struct MailSettings: Codable {
    /// View filter: which accounts/mailboxes this vault displays from the global DB (v2)
    public var viewFilter: MailViewFilter?

    /// Custom path to Apple Mail data directory (nil = auto-detect)
    /// DEPRECATED: Moved to global config. Kept for backward compatibility on read.
    public var mailDataPath: String?

    /// Default export format ("markdown" or "json")
    public var exportFormat: String

    /// Default export output directory (relative to vault or absolute)
    public var exportOutputDir: String?

    /// Whether to include attachments by default in exports
    public var exportIncludeAttachments: Bool

    /// Watch daemon sync interval in seconds
    /// DEPRECATED: Moved to global config. Kept for backward compatibility on read.
    public var watchSyncInterval: Int

    /// Whether watch daemon is enabled
    /// DEPRECATED: Moved to global config. Kept for backward compatibility on read.
    public var watchEnabled: Bool

    /// Available config keys for vault mail settings
    public static let keys: [String: String] = [
        "mail.export.format": "Default export format: markdown or json",
        "mail.export.outputDir": "Default export output directory",
        "mail.export.includeAttachments": "Include attachments by default: true or false"
    ]

    /// Deprecated keys that have moved to global config
    public static let deprecatedKeys: [String: String] = [
        "mail.dataPath": "Moved to global config. Use: swea config --global mail.dataPath <value>",
        "mail.watch.syncInterval": "Moved to global config. Use: swea config --global mail.watch.syncInterval <value>",
        "mail.watch.enabled": "Moved to global config. Use: swea config --global mail.watch.enabled <value>"
    ]

    public init(
        viewFilter: MailViewFilter? = nil,
        mailDataPath: String? = nil,
        exportFormat: String = "markdown",
        exportOutputDir: String? = nil,
        exportIncludeAttachments: Bool = false,
        watchSyncInterval: Int = 300,
        watchEnabled: Bool = true
    ) {
        self.viewFilter = viewFilter
        self.mailDataPath = mailDataPath
        self.exportFormat = exportFormat
        self.exportOutputDir = exportOutputDir
        self.exportIncludeAttachments = exportIncludeAttachments
        self.watchSyncInterval = watchSyncInterval
        self.watchEnabled = watchEnabled
    }

    /// Handle decoding with optional viewFilter for backward compatibility
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        viewFilter = try container.decodeIfPresent(MailViewFilter.self, forKey: .viewFilter)
        mailDataPath = try container.decodeIfPresent(String.self, forKey: .mailDataPath)
        exportFormat = try container.decodeIfPresent(String.self, forKey: .exportFormat) ?? "markdown"
        exportOutputDir = try container.decodeIfPresent(String.self, forKey: .exportOutputDir)
        exportIncludeAttachments = try container.decodeIfPresent(Bool.self, forKey: .exportIncludeAttachments) ?? false
        watchSyncInterval = try container.decodeIfPresent(Int.self, forKey: .watchSyncInterval) ?? 300
        watchEnabled = try container.decodeIfPresent(Bool.self, forKey: .watchEnabled) ?? true
    }

    /// Get a setting value by key
    public func getValue(for key: String) -> String? {
        switch key {
        case "mail.dataPath":
            return mailDataPath
        case "mail.export.format":
            return exportFormat
        case "mail.export.outputDir":
            return exportOutputDir
        case "mail.export.includeAttachments":
            return exportIncludeAttachments ? "true" : "false"
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
        case "mail.export.format":
            if value != "markdown" && value != "json" {
                return "Invalid format: \(value). Must be 'markdown' or 'json'."
            }
            exportFormat = value
            return nil
        case "mail.export.outputDir":
            exportOutputDir = value.isEmpty ? nil : value
            return nil
        case "mail.export.includeAttachments":
            if let bool = parseBool(value) {
                exportIncludeAttachments = bool
                return nil
            }
            return "Invalid value: \(value). Must be 'true' or 'false'."
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

/// Calendar-specific configuration settings
public struct CalendarSettings: Codable {
    /// Default calendar for new events (nil = system default)
    public var defaultCalendar: String?

    /// Date range in days for sync (how far forward to sync)
    public var dateRangeDays: Int

    /// Sync interval in minutes for watch daemon
    public var syncIntervalMinutes: Int

    /// Whether to expand recurring events during sync
    public var expandRecurring: Bool

    /// Default export format ("markdown", "json", or "ics")
    public var exportFormat: String

    /// Default export output directory (relative to vault or absolute)
    public var exportOutputDir: String?

    /// Available config keys for calendar settings
    public static let keys: [String: String] = [
        "calendar.defaultCalendar": "Default calendar for new events (empty = system default)",
        "calendar.dateRangeDays": "Date range in days for sync (default: 365)",
        "calendar.syncIntervalMinutes": "Sync interval in minutes (default: 5, min: 1)",
        "calendar.expandRecurring": "Expand recurring events during sync: true or false",
        "calendar.export.format": "Default export format: markdown, json, or ics",
        "calendar.export.outputDir": "Default export output directory"
    ]

    public init(
        defaultCalendar: String? = nil,
        dateRangeDays: Int = 365,
        syncIntervalMinutes: Int = 5,
        expandRecurring: Bool = true,
        exportFormat: String = "markdown",
        exportOutputDir: String? = nil
    ) {
        self.defaultCalendar = defaultCalendar
        self.dateRangeDays = dateRangeDays
        self.syncIntervalMinutes = syncIntervalMinutes
        self.expandRecurring = expandRecurring
        self.exportFormat = exportFormat
        self.exportOutputDir = exportOutputDir
    }

    /// Get a setting value by key
    public func getValue(for key: String) -> String? {
        switch key {
        case "calendar.defaultCalendar":
            return defaultCalendar ?? ""
        case "calendar.dateRangeDays":
            return String(dateRangeDays)
        case "calendar.syncIntervalMinutes":
            return String(syncIntervalMinutes)
        case "calendar.expandRecurring":
            return expandRecurring ? "true" : "false"
        case "calendar.export.format":
            return exportFormat
        case "calendar.export.outputDir":
            return exportOutputDir ?? ""
        default:
            return nil
        }
    }

    /// Set a setting value by key, returns error message if invalid
    public mutating func setValue(_ value: String, for key: String) -> String? {
        switch key {
        case "calendar.defaultCalendar":
            defaultCalendar = value.isEmpty ? nil : value
            return nil
        case "calendar.dateRangeDays":
            if let days = Int(value), days >= 1 && days <= 3650 {
                dateRangeDays = days
                return nil
            }
            return "Invalid value: \(value). Must be a number between 1 and 3650."
        case "calendar.syncIntervalMinutes":
            if let minutes = Int(value), minutes >= 1 {
                syncIntervalMinutes = minutes
                return nil
            }
            return "Invalid value: \(value). Must be a number >= 1."
        case "calendar.expandRecurring":
            if let bool = parseBool(value) {
                expandRecurring = bool
                return nil
            }
            return "Invalid value: \(value). Must be 'true' or 'false'."
        case "calendar.export.format":
            let validFormats = ["markdown", "md", "json", "ics"]
            if validFormats.contains(value.lowercased()) {
                exportFormat = value.lowercased() == "md" ? "markdown" : value.lowercased()
                return nil
            }
            return "Invalid format: \(value). Must be 'markdown', 'json', or 'ics'."
        case "calendar.export.outputDir":
            exportOutputDir = value.isEmpty ? nil : value
            return nil
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

/// AI-specific configuration settings
public struct AISettings: Codable {
    /// OpenRouter model to use for screening
    public var model: String

    /// Whether to auto-screen new messages during sync
    public var autoScreenOnSync: Bool

    /// Available config keys for AI settings
    public static let keys: [String: String] = [
        "ai.model": "OpenRouter model ID for AI screening (default: openai/gpt-oss-120b)",
        "ai.autoScreenOnSync": "Auto-screen new emails during sync: true or false"
    ]

    public init(
        model: String = "openai/gpt-oss-120b",
        autoScreenOnSync: Bool = true
    ) {
        self.model = model
        self.autoScreenOnSync = autoScreenOnSync
    }

    /// Get a setting value by key
    public func getValue(for key: String) -> String? {
        switch key {
        case "ai.model":
            return model
        case "ai.autoScreenOnSync":
            return autoScreenOnSync ? "true" : "false"
        default:
            return nil
        }
    }

    /// Set a setting value by key, returns error message if invalid
    public mutating func setValue(_ value: String, for key: String) -> String? {
        switch key {
        case "ai.model":
            if value.isEmpty {
                return "Model cannot be empty."
            }
            model = value
            return nil
        case "ai.autoScreenOnSync":
            if let bool = parseBool(value) {
                autoScreenOnSync = bool
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
