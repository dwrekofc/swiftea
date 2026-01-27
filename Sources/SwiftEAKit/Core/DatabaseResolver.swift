// DatabaseResolver - Central entry point for resolving the mail database and view filter

import Foundation

/// Resolves the mail database path and optional view filter for any command.
/// All commands use this instead of constructing their own MailDatabase.
public struct DatabaseResolver {

    /// Result of resolving the database path and filter
    public struct Resolved {
        public let database: MailDatabase
        public let viewFilter: MailViewFilter?
    }

    /// Resolve the global mail database and optional view filter.
    ///
    /// - Parameter vaultContext: Optional vault context. If provided and the vault has a view filter,
    ///   it will be included in the result. If nil, no filtering is applied.
    /// - Returns: A Resolved struct containing the database and optional filter.
    /// - Throws: If the database path cannot be determined or directories cannot be created.
    public static func resolve(vaultContext: VaultContext? = nil) throws -> Resolved {
        let configManager = GlobalConfigManager()
        try configManager.ensureDirectories()

        let dbPath = try configManager.resolvedDatabasePath()

        // Migrate data from vault DBs on first use
        try migrateIfNeeded(globalDbPath: dbPath, configManager: configManager)

        let database = MailDatabase(databasePath: dbPath)

        // Extract view filter from vault context if available
        let viewFilter = vaultContext?.mailViewFilter

        return Resolved(database: database, viewFilter: viewFilter)
    }

    // MARK: - Data Migration

    /// Migrate existing vault databases to the global database on first use.
    /// Only runs if the global database doesn't exist yet.
    private static func migrateIfNeeded(globalDbPath: String, configManager: GlobalConfigManager) throws {
        let fileManager = FileManager.default

        // If global DB already exists, no migration needed
        if fileManager.fileExists(atPath: globalDbPath) {
            return
        }

        // Try to find existing vault databases from the binding registry
        let registry = BindingRegistry()
        let bindings: [AccountBinding]
        do {
            bindings = try registry.allBindings()
        } catch {
            // No registry or can't read it - nothing to migrate
            return
        }

        // Collect unique vault paths
        let vaultPaths = Set(bindings.map { $0.vaultPath })

        // Find existing vault mail.db files
        var existingDbPaths: [(path: String, modDate: Date)] = []
        for vaultPath in vaultPaths {
            let dataFolder = (vaultPath as NSString).appendingPathComponent("Swiftea")
            let dbPath = (dataFolder as NSString).appendingPathComponent("mail.db")

            if fileManager.fileExists(atPath: dbPath) {
                let attrs = try? fileManager.attributesOfItem(atPath: dbPath)
                let modDate = attrs?[.modificationDate] as? Date ?? Date.distantPast
                existingDbPaths.append((path: dbPath, modDate: modDate))
            }
        }

        guard !existingDbPaths.isEmpty else { return }

        // Sort by most recently modified
        existingDbPaths.sort { $0.modDate > $1.modDate }

        // Copy the most recent vault DB to the global location
        let primaryDb = existingDbPaths[0].path
        try fileManager.copyItem(atPath: primaryDb, toPath: globalDbPath)

        // If multiple vault DBs exist, merge the rest via INSERT OR IGNORE
        if existingDbPaths.count > 1 {
            let globalDb = MailDatabase(databasePath: globalDbPath)
            try globalDb.initialize()

            for otherDb in existingDbPaths.dropFirst() {
                do {
                    try mergeDatabase(from: otherDb.path, into: globalDb)
                } catch {
                    // Log but don't fail - we already have the primary DB
                    fputs("Warning: Could not merge \(otherDb.path): \(error.localizedDescription)\n", stderr)
                }
            }

            globalDb.close()
        }
    }

    /// Merge data from a source database into the global database using INSERT OR IGNORE
    private static func mergeDatabase(from sourcePath: String, into targetDb: MailDatabase) throws {
        // Attach the source database
        guard let conn = targetDb.getConnection() else { return }

        let escapedPath = sourcePath.replacingOccurrences(of: "'", with: "''")
        _ = try conn.execute("ATTACH DATABASE '\(escapedPath)' AS source_db")

        defer {
            _ = try? conn.execute("DETACH DATABASE source_db")
        }

        // Merge messages (INSERT OR IGNORE keeps existing records)
        _ = try conn.execute("""
            INSERT OR IGNORE INTO messages
            SELECT * FROM source_db.messages
            """)

        // Merge threads
        _ = try conn.execute("""
            INSERT OR IGNORE INTO threads
            SELECT * FROM source_db.threads
            WHERE EXISTS (SELECT 1 FROM source_db.threads)
            """)

        // Merge thread_messages junction
        _ = try conn.execute("""
            INSERT OR IGNORE INTO thread_messages
            SELECT * FROM source_db.thread_messages
            WHERE EXISTS (SELECT 1 FROM source_db.thread_messages)
            """)

        // Merge mailboxes
        _ = try conn.execute("""
            INSERT OR IGNORE INTO mailboxes
            SELECT * FROM source_db.mailboxes
            """)
    }
}
