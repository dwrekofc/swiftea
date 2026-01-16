// MailDatabase - libSQL mirror database for Apple Mail data

import Foundation
import Libsql

/// Errors that can occur during mail database operations
public enum MailDatabaseError: Error, LocalizedError {
    case connectionFailed(underlying: Error)
    case migrationFailed(underlying: Error)
    case queryFailed(underlying: Error)
    case notInitialized

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let error):
            return "Failed to connect to mail database: \(error.localizedDescription)"
        case .migrationFailed(let error):
            return "Failed to run database migration: \(error.localizedDescription)"
        case .queryFailed(let error):
            return "Database query failed: \(error.localizedDescription)"
        case .notInitialized:
            return "Mail database not initialized"
        }
    }
}

/// Sort options for thread listing
public enum ThreadSortOrder: String, CaseIterable, Sendable {
    case date = "date"
    case subject = "subject"
    case messageCount = "message_count"

    /// SQL ORDER BY clause for this sort option
    var sqlOrderBy: String {
        switch self {
        case .date:
            return "last_date DESC"
        case .subject:
            return "subject ASC NULLS LAST"
        case .messageCount:
            return "message_count DESC"
        }
    }
}

/// Manages the libSQL mirror database for Apple Mail data
public final class MailDatabase: @unchecked Sendable {
    private var database: Database?
    private var connection: Connection?
    private let databasePath: String

    public init(databasePath: String) {
        self.databasePath = databasePath
    }

    /// Initialize the database connection and run migrations
    public func initialize() throws {
        do {
            database = try Database(databasePath)
            connection = try database?.connect()

            // Enable WAL mode for concurrent access (allows readers while writing)
            // This prevents "database is locked" errors when daemon and manual sync run concurrently
            if let conn = connection {
                _ = try conn.query("PRAGMA journal_mode=WAL")
                // Set busy timeout to 5 seconds to wait for locks instead of failing immediately
                _ = try conn.query("PRAGMA busy_timeout=5000")
            }

            try runMigrations()
        } catch {
            throw MailDatabaseError.connectionFailed(underlying: error)
        }
    }

    /// Close the database connection
    public func close() {
        connection = nil
        database = nil
    }

    // MARK: - Schema Definition

    /// Run all pending migrations to bring schema up to date
    private func runMigrations() throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        // Create schema version tracking table
        _ = try conn.execute("""
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER PRIMARY KEY,
                applied_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
            """)

        // Get current version
        let result = try conn.query("SELECT MAX(version) as v FROM schema_version")
        var currentVersion = 0
        for row in result {
            if let v = try? row.getInt(0) {
                currentVersion = v
            }
        }

        // Apply migrations
        if currentVersion < 1 {
            try applyMigrationV1(conn)
        }
        if currentVersion < 2 {
            try applyMigrationV2(conn)
        }
        if currentVersion < 3 {
            try applyMigrationV3(conn)
        }
        if currentVersion < 4 {
            try applyMigrationV4(conn)
        }
        if currentVersion < 5 {
            try applyMigrationV5(conn)
        }
        if currentVersion < 6 {
            try applyMigrationV6(conn)
        }
        if currentVersion < 7 {
            try applyMigrationV7(conn)
        }
    }

    /// Migration v1: Initial schema with all mail tables
    private func applyMigrationV1(_ conn: Connection) throws {
        do {
            // Messages table - core email metadata
            _ = try conn.execute("""
                CREATE TABLE IF NOT EXISTS messages (
                    id TEXT PRIMARY KEY,
                    apple_rowid INTEGER,
                    message_id TEXT,
                    mailbox_id INTEGER,
                    mailbox_name TEXT,
                    account_id TEXT,
                    subject TEXT,
                    sender_name TEXT,
                    sender_email TEXT,
                    date_sent INTEGER,
                    date_received INTEGER,
                    is_read INTEGER DEFAULT 0,
                    is_flagged INTEGER DEFAULT 0,
                    is_deleted INTEGER DEFAULT 0,
                    has_attachments INTEGER DEFAULT 0,
                    emlx_path TEXT,
                    body_text TEXT,
                    body_html TEXT,
                    export_path TEXT,
                    synced_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                )
                """)

            // Recipients table - to/cc/bcc addresses
            _ = try conn.execute("""
                CREATE TABLE IF NOT EXISTS recipients (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    message_id TEXT NOT NULL,
                    type TEXT NOT NULL,
                    name TEXT,
                    email TEXT NOT NULL,
                    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
                )
                """)

            // Attachments table - attachment metadata
            _ = try conn.execute("""
                CREATE TABLE IF NOT EXISTS attachments (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    message_id TEXT NOT NULL,
                    filename TEXT NOT NULL,
                    mime_type TEXT,
                    size INTEGER,
                    content_id TEXT,
                    is_inline INTEGER DEFAULT 0,
                    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
                )
                """)

            // Mailboxes table - folder hierarchy
            _ = try conn.execute("""
                CREATE TABLE IF NOT EXISTS mailboxes (
                    id INTEGER PRIMARY KEY,
                    account_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    full_path TEXT NOT NULL,
                    parent_id INTEGER,
                    message_count INTEGER DEFAULT 0,
                    unread_count INTEGER DEFAULT 0,
                    synced_at INTEGER NOT NULL
                )
                """)

            // Sync status table - track sync progress
            _ = try conn.execute("""
                CREATE TABLE IF NOT EXISTS sync_status (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL,
                    updated_at INTEGER NOT NULL
                )
                """)

            // Create indexes for common lookups
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_apple_rowid ON messages(apple_rowid)")
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_message_id ON messages(message_id)")
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_mailbox_id ON messages(mailbox_id)")
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_account_id ON messages(account_id)")
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_date_received ON messages(date_received)")
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_is_read ON messages(is_read)")
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_is_flagged ON messages(is_flagged)")
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_recipients_message_id ON recipients(message_id)")
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_attachments_message_id ON attachments(message_id)")
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_mailboxes_account_id ON mailboxes(account_id)")

            // Create FTS5 virtual table for full-text search
            // Note: Using external content table (content='messages') means FTS reads from messages table
            _ = try conn.execute("""
                CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
                    subject,
                    sender_name,
                    sender_email,
                    body_text,
                    content='messages',
                    content_rowid='rowid',
                    tokenize='porter unicode61'
                )
                """)

            // Create triggers to keep FTS index in sync
            _ = try conn.execute("""
                CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
                    INSERT INTO messages_fts(rowid, subject, sender_name, sender_email, body_text)
                    VALUES (NEW.rowid, NEW.subject, NEW.sender_name, NEW.sender_email, NEW.body_text);
                END
                """)

            _ = try conn.execute("""
                CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
                    INSERT INTO messages_fts(messages_fts, rowid, subject, sender_name, sender_email, body_text)
                    VALUES ('delete', OLD.rowid, OLD.subject, OLD.sender_name, OLD.sender_email, OLD.body_text);
                END
                """)

            _ = try conn.execute("""
                CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
                    INSERT INTO messages_fts(messages_fts, rowid, subject, sender_name, sender_email, body_text)
                    VALUES ('delete', OLD.rowid, OLD.subject, OLD.sender_name, OLD.sender_email, OLD.body_text);
                    INSERT INTO messages_fts(rowid, subject, sender_name, sender_email, body_text)
                    VALUES (NEW.rowid, NEW.subject, NEW.sender_name, NEW.sender_email, NEW.body_text);
                END
                """)

            // Record migration version
            _ = try conn.execute("INSERT INTO schema_version (version) VALUES (1)")

        } catch {
            throw MailDatabaseError.migrationFailed(underlying: error)
        }
    }

    /// Migration v2: Add mailbox status tracking columns for bidirectional sync
    private func applyMigrationV2(_ conn: Connection) throws {
        do {
            // Add mailbox_status column with default 'inbox' for existing messages
            _ = try conn.execute("ALTER TABLE messages ADD COLUMN mailbox_status TEXT DEFAULT 'inbox'")

            // Add pending_sync_action column (nullable - only set when action is pending)
            _ = try conn.execute("ALTER TABLE messages ADD COLUMN pending_sync_action TEXT")

            // Add last_known_mailbox_id column (nullable - tracks original mailbox for move detection)
            _ = try conn.execute("ALTER TABLE messages ADD COLUMN last_known_mailbox_id INTEGER")

            // Create index for querying messages by mailbox status
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_mailbox_status ON messages(mailbox_status)")

            // Create index for finding messages with pending sync actions
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_pending_sync_action ON messages(pending_sync_action)")

            // Record migration version
            _ = try conn.execute("INSERT INTO schema_version (version) VALUES (2)")

        } catch {
            throw MailDatabaseError.migrationFailed(underlying: error)
        }
    }

    /// Migration v3: Add threading header columns (in_reply_to, references)
    private func applyMigrationV3(_ conn: Connection) throws {
        do {
            // Add in_reply_to column (nullable - stores the In-Reply-To header value)
            _ = try conn.execute("ALTER TABLE messages ADD COLUMN in_reply_to TEXT")

            // Add references column (nullable - stores JSON array of message IDs from References header)
            _ = try conn.execute("ALTER TABLE messages ADD COLUMN threading_references TEXT")

            // Create index for looking up messages by in_reply_to (for thread detection)
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_in_reply_to ON messages(in_reply_to)")

            // Record migration version
            _ = try conn.execute("INSERT INTO schema_version (version) VALUES (3)")

        } catch {
            throw MailDatabaseError.migrationFailed(underlying: error)
        }
    }

    /// Migration v4: Create threads table for conversation-level metadata
    private func applyMigrationV4(_ conn: Connection) throws {
        do {
            // Create threads table for conversation-level metadata
            // Thread IDs are 32-character hex strings generated by ThreadIDGenerator
            _ = try conn.execute("""
                CREATE TABLE IF NOT EXISTS threads (
                    id TEXT PRIMARY KEY,
                    subject TEXT,
                    participant_count INTEGER DEFAULT 0,
                    message_count INTEGER DEFAULT 0,
                    first_date INTEGER,
                    last_date INTEGER,
                    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
                    updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
                )
                """)

            // Add thread_id column to messages table (foreign key reference to threads)
            _ = try conn.execute("ALTER TABLE messages ADD COLUMN thread_id TEXT REFERENCES threads(id)")

            // Create index for efficient thread lookups
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_threads_last_date ON threads(last_date DESC)")

            // Create index for efficient message lookup by thread_id
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_thread_id ON messages(thread_id)")

            // Record migration version
            _ = try conn.execute("INSERT INTO schema_version (version) VALUES (4)")

        } catch {
            throw MailDatabaseError.migrationFailed(underlying: error)
        }
    }

    /// Migration v5: Create thread_messages junction table for many-to-many relationships
    private func applyMigrationV5(_ conn: Connection) throws {
        do {
            // Create thread_messages junction table
            // This allows many-to-many relationships between threads and messages
            // A message can belong to multiple threads (e.g., cross-posted, forwarded chains)
            // A thread can contain multiple messages
            _ = try conn.execute("""
                CREATE TABLE IF NOT EXISTS thread_messages (
                    thread_id TEXT NOT NULL,
                    message_id TEXT NOT NULL,
                    added_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
                    PRIMARY KEY (thread_id, message_id),
                    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
                    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
                )
                """)

            // Create index for efficient lookup by thread_id (get all messages in a thread)
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_thread_messages_thread_id ON thread_messages(thread_id)")

            // Create index for efficient lookup by message_id (get all threads a message belongs to)
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_thread_messages_message_id ON thread_messages(message_id)")

            // Record migration version
            _ = try conn.execute("INSERT INTO schema_version (version) VALUES (5)")

        } catch {
            throw MailDatabaseError.migrationFailed(underlying: error)
        }
    }

    /// Migration v6: Add thread_position and thread_total columns to messages table
    private func applyMigrationV6(_ conn: Connection) throws {
        do {
            // Add thread_position column (nullable - position of message within its thread)
            _ = try conn.execute("ALTER TABLE messages ADD COLUMN thread_position INTEGER")

            // Add thread_total column (nullable - total messages in the thread)
            _ = try conn.execute("ALTER TABLE messages ADD COLUMN thread_total INTEGER")

            // Record migration version
            _ = try conn.execute("INSERT INTO schema_version (version) VALUES (6)")

        } catch {
            throw MailDatabaseError.migrationFailed(underlying: error)
        }
    }

    /// Migration v7: Add indexes for large inbox query optimization (>100k emails)
    /// This migration optimizes thread listing and filtering for large inboxes
    private func applyMigrationV7(_ conn: Connection) throws {
        do {
            // Index on threads(subject) for sorting by subject
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_threads_subject ON threads(subject)")

            // Index on threads(message_count) for sorting by message count
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_threads_message_count ON threads(message_count DESC)")

            // Index on messages(sender_email) for participant filtering
            // Uses LOWER() to support case-insensitive queries
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_sender_email ON messages(sender_email)")

            // Index on recipients(email) for participant filtering
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_recipients_email ON recipients(email)")

            // Composite index for efficient thread position batch updates
            _ = try conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_thread_position ON messages(thread_id, thread_position)")

            // Record migration version
            _ = try conn.execute("INSERT INTO schema_version (version) VALUES (7)")

        } catch {
            throw MailDatabaseError.migrationFailed(underlying: error)
        }
    }

    // MARK: - Schema Version API

    /// The current schema version number (latest migration version)
    public static let currentSchemaVersion = 7

    /// Description of each schema migration
    public static let migrationDescriptions: [Int: String] = [
        1: "Initial schema with messages, recipients, attachments, mailboxes, sync_status tables and FTS5",
        2: "Bidirectional sync columns (mailbox_status, pending_sync_action, last_known_mailbox_id)",
        3: "Threading headers (in_reply_to, threading_references)",
        4: "Threads table and thread_id column on messages",
        5: "Thread-messages junction table for many-to-many relationships",
        6: "Thread position metadata (thread_position, thread_total)",
        7: "Large inbox query optimization indexes"
    ]

    /// Get the current schema version from the database
    /// Returns 0 if database has no schema_version table (empty/new database)
    public func getSchemaVersion() throws -> Int {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        // Check if schema_version table exists
        let tableCheck = try conn.query("""
            SELECT name FROM sqlite_master
            WHERE type='table' AND name='schema_version'
            """)

        var tableExists = false
        for _ in tableCheck {
            tableExists = true
            break
        }

        if !tableExists {
            return 0
        }

        // Get current version
        let result = try conn.query("SELECT MAX(version) as v FROM schema_version")
        for row in result {
            if let v = try? row.getInt(0) {
                return v
            }
        }
        return 0
    }

    /// Get the migration history with timestamps
    public func getMigrationHistory() throws -> [(version: Int, appliedAt: String)] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        // Check if schema_version table exists
        let tableCheck = try conn.query("""
            SELECT name FROM sqlite_master
            WHERE type='table' AND name='schema_version'
            """)

        var tableExists = false
        for _ in tableCheck {
            tableExists = true
            break
        }

        if !tableExists {
            return []
        }

        var history: [(version: Int, appliedAt: String)] = []
        let result = try conn.query("SELECT version, applied_at FROM schema_version ORDER BY version ASC")
        for row in result {
            if let version = try? row.getInt(0),
               let appliedAt = try? row.getString(1) {
                history.append((version: version, appliedAt: appliedAt))
            }
        }
        return history
    }

    /// Check if a specific table exists in the database
    public func tableExists(_ tableName: String) throws -> Bool {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("""
            SELECT name FROM sqlite_master
            WHERE type='table' AND name='\(escapeSql(tableName))'
            """)

        for _ in result {
            return true
        }
        return false
    }

    /// Get the columns for a specific table
    public func getTableColumns(_ tableName: String) throws -> [String] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        var columns: [String] = []
        let result = try conn.query("PRAGMA table_info('\(escapeSql(tableName))')")
        for row in result {
            if let name = try? row.getString(1) {
                columns.append(name)
            }
        }
        return columns
    }

    // MARK: - Message Operations

    /// Insert or update a message in the mirror database
    public func upsertMessage(_ message: MailMessage) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)

        // Serialize references array to JSON for storage
        let referencesJson = serializeReferences(message.references)

        _ = try conn.execute("""
            INSERT INTO messages (
                id, apple_rowid, message_id, mailbox_id, mailbox_name, account_id,
                subject, sender_name, sender_email, date_sent, date_received,
                is_read, is_flagged, is_deleted, has_attachments, emlx_path,
                body_text, body_html, synced_at, updated_at,
                mailbox_status, pending_sync_action, last_known_mailbox_id,
                in_reply_to, threading_references, thread_id,
                thread_position, thread_total
            ) VALUES (
                '\(message.id)', \(message.appleRowId ?? 0), \(message.messageId.map { "'\($0)'" } ?? "NULL"),
                \(message.mailboxId ?? 0), \(message.mailboxName.map { "'\($0)'" } ?? "NULL"),
                \(message.accountId.map { "'\($0)'" } ?? "NULL"),
                '\(escapeSql(message.subject))', \(message.senderName.map { "'\(escapeSql($0))'" } ?? "NULL"),
                \(message.senderEmail.map { "'\(escapeSql($0))'" } ?? "NULL"),
                \(message.dateSent.map { Int($0.timeIntervalSince1970) } ?? 0),
                \(message.dateReceived.map { Int($0.timeIntervalSince1970) } ?? 0),
                \(message.isRead ? 1 : 0), \(message.isFlagged ? 1 : 0), \(message.isDeleted ? 1 : 0),
                \(message.hasAttachments ? 1 : 0), \(message.emlxPath.map { "'\(escapeSql($0))'" } ?? "NULL"),
                \(message.bodyText.map { "'\(escapeSql($0))'" } ?? "NULL"),
                \(message.bodyHtml.map { "'\(escapeSql($0))'" } ?? "NULL"),
                \(now), \(now),
                '\(message.mailboxStatus.rawValue)',
                \(message.pendingSyncAction.map { "'\($0.rawValue)'" } ?? "NULL"),
                \(message.lastKnownMailboxId.map { String($0) } ?? "NULL"),
                \(message.inReplyTo.map { "'\(escapeSql($0))'" } ?? "NULL"),
                \(referencesJson.map { "'\(escapeSql($0))'" } ?? "NULL"),
                \(message.threadId.map { "'\(escapeSql($0))'" } ?? "NULL"),
                \(message.threadPosition.map { String($0) } ?? "NULL"),
                \(message.threadTotal.map { String($0) } ?? "NULL")
            )
            ON CONFLICT(id) DO UPDATE SET
                apple_rowid = excluded.apple_rowid,
                message_id = excluded.message_id,
                mailbox_id = excluded.mailbox_id,
                mailbox_name = excluded.mailbox_name,
                account_id = excluded.account_id,
                subject = excluded.subject,
                sender_name = excluded.sender_name,
                sender_email = excluded.sender_email,
                date_sent = excluded.date_sent,
                date_received = excluded.date_received,
                is_read = excluded.is_read,
                is_flagged = excluded.is_flagged,
                is_deleted = excluded.is_deleted,
                has_attachments = excluded.has_attachments,
                emlx_path = excluded.emlx_path,
                body_text = excluded.body_text,
                body_html = excluded.body_html,
                updated_at = \(now),
                mailbox_status = excluded.mailbox_status,
                pending_sync_action = excluded.pending_sync_action,
                last_known_mailbox_id = excluded.last_known_mailbox_id,
                in_reply_to = excluded.in_reply_to,
                threading_references = excluded.threading_references,
                thread_id = excluded.thread_id,
                thread_position = excluded.thread_position,
                thread_total = excluded.thread_total
            """)
    }

    /// Get a message by its stable ID
    public func getMessage(id: String) throws -> MailMessage? {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("SELECT * FROM messages WHERE id = '\(escapeSql(id))'")

        for row in result {
            return try rowToMessage(row)
        }
        return nil
    }

    /// Get a message by Apple Mail rowid
    public func getMessage(appleRowId: Int) throws -> MailMessage? {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("SELECT * FROM messages WHERE apple_rowid = \(appleRowId)")

        for row in result {
            return try rowToMessage(row)
        }
        return nil
    }

    /// Search messages using FTS
    public func searchMessages(query: String, limit: Int = 50, offset: Int = 0) throws -> [MailMessage] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("""
            SELECT m.* FROM messages m
            JOIN messages_fts fts ON m.rowid = fts.rowid
            WHERE messages_fts MATCH '\(escapeSql(query))'
            ORDER BY bm25(messages_fts)
            LIMIT \(limit) OFFSET \(offset)
            """)

        var messages: [MailMessage] = []
        for row in result {
            if let message = try? rowToMessage(row) {
                messages.append(message)
            }
        }
        return messages
    }

    // MARK: - Structured Query Search

    /// Parsed filter from a structured query
    public struct SearchFilter {
        public var from: String?
        public var to: String?
        public var subject: String?
        public var mailbox: String?
        public var isRead: Bool?
        public var isFlagged: Bool?
        public var dateAfter: Date?
        public var dateBefore: Date?
        public var hasAttachments: Bool?
        public var freeText: String?
        public var mailboxStatus: MailboxStatus?

        public init() {}

        /// Check if any filters are set
        public var hasFilters: Bool {
            from != nil || to != nil || subject != nil || mailbox != nil ||
            isRead != nil || isFlagged != nil || dateAfter != nil ||
            dateBefore != nil || hasAttachments != nil || mailboxStatus != nil
        }

        /// Check if there's free text for FTS
        public var hasFreeText: Bool {
            freeText != nil && !freeText!.isEmpty
        }
    }

    /// Parse a structured query string into filters
    /// Supports: from:, to:, subject:, mailbox:, is:read, is:unread, is:flagged, is:unflagged,
    /// after:, before:, date:, has:attachments
    public func parseQuery(_ query: String) -> SearchFilter {
        var filter = SearchFilter()

        // Regex patterns for structured filters
        let filterPatterns: [(pattern: String, handler: (String, inout SearchFilter) -> Void)] = [
            // from: filter (email or name)
            ("from:\"([^\"]+)\"", { value, f in f.from = value }),
            ("from:(\\S+)", { value, f in f.from = value }),

            // to: filter
            ("to:\"([^\"]+)\"", { value, f in f.to = value }),
            ("to:(\\S+)", { value, f in f.to = value }),

            // subject: filter
            ("subject:\"([^\"]+)\"", { value, f in f.subject = value }),
            ("subject:(\\S+)", { value, f in f.subject = value }),

            // mailbox: filter
            ("mailbox:\"([^\"]+)\"", { value, f in f.mailbox = value }),
            ("mailbox:(\\S+)", { value, f in f.mailbox = value }),

            // is: status filters
            ("is:read", { _, f in f.isRead = true }),
            ("is:unread", { _, f in f.isRead = false }),
            ("is:flagged", { _, f in f.isFlagged = true }),
            ("is:unflagged", { _, f in f.isFlagged = false }),

            // has: filters
            ("has:attachments?", { _, f in f.hasAttachments = true }),

            // Date filters (YYYY-MM-DD format)
            ("after:(\\d{4}-\\d{2}-\\d{2})", { value, f in f.dateAfter = parseDate(value) }),
            ("before:(\\d{4}-\\d{2}-\\d{2})", { value, f in f.dateBefore = parseDate(value) }),
            ("date:(\\d{4}-\\d{2}-\\d{2})", { value, f in
                // date: sets both after and before to cover the whole day
                if let date = parseDate(value) {
                    f.dateAfter = date
                    // Set before to end of day
                    if let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: date) {
                        f.dateBefore = endOfDay
                    }
                }
            })
        ]

        var remainingQuery = query

        // Process each filter pattern
        for (pattern, handler) in filterPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(remainingQuery.startIndex..., in: remainingQuery)
                let matches = regex.matches(in: remainingQuery, options: [], range: range)

                // Process matches in reverse to preserve indices
                for match in matches.reversed() {
                    // Extract captured group if present, otherwise use the whole match
                    let valueRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                    if let swiftRange = Range(valueRange, in: remainingQuery) {
                        let value = String(remainingQuery[swiftRange])
                        handler(value, &filter)
                    } else {
                        handler("", &filter)
                    }

                    // Remove matched text from query
                    if let swiftRange = Range(match.range, in: remainingQuery) {
                        remainingQuery.removeSubrange(swiftRange)
                    }
                }
            }
        }

        // Clean up remaining query (free text for FTS)
        let cleanedFreeText = remainingQuery
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if !cleanedFreeText.isEmpty {
            filter.freeText = cleanedFreeText
        }

        return filter
    }

    /// Search messages using structured filters and optional FTS
    public func searchMessagesWithFilters(_ filter: SearchFilter, limit: Int = 50, offset: Int = 0) throws -> [MailMessage] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        var whereClauses: [String] = []

        // Build WHERE clauses from filters

        // from: filter (matches sender_name or sender_email)
        if let from = filter.from {
            let escaped = escapeSql(from)
            whereClauses.append("(m.sender_email LIKE '%\(escaped)%' OR m.sender_name LIKE '%\(escaped)%')")
        }

        // to: filter (requires join with recipients table)
        // For simplicity, we'll use a subquery
        if let to = filter.to {
            let escaped = escapeSql(to)
            whereClauses.append("""
                EXISTS (SELECT 1 FROM recipients r WHERE r.message_id = m.id
                        AND (r.email LIKE '%\(escaped)%' OR r.name LIKE '%\(escaped)%'))
                """)
        }

        // subject: filter
        if let subject = filter.subject {
            let escaped = escapeSql(subject)
            whereClauses.append("m.subject LIKE '%\(escaped)%'")
        }

        // mailbox: filter
        if let mailbox = filter.mailbox {
            let escaped = escapeSql(mailbox)
            whereClauses.append("m.mailbox_name LIKE '%\(escaped)%'")
        }

        // is:read / is:unread filter
        if let isRead = filter.isRead {
            whereClauses.append("m.is_read = \(isRead ? 1 : 0)")
        }

        // is:flagged / is:unflagged filter
        if let isFlagged = filter.isFlagged {
            whereClauses.append("m.is_flagged = \(isFlagged ? 1 : 0)")
        }

        // has:attachments filter
        if let hasAttachments = filter.hasAttachments, hasAttachments {
            whereClauses.append("m.has_attachments = 1")
        }

        // Date filters
        if let dateAfter = filter.dateAfter {
            let timestamp = Int(dateAfter.timeIntervalSince1970)
            whereClauses.append("m.date_received >= \(timestamp)")
        }

        if let dateBefore = filter.dateBefore {
            let timestamp = Int(dateBefore.timeIntervalSince1970)
            whereClauses.append("m.date_received < \(timestamp)")
        }

        // Mailbox status filter (inbox, archived, deleted)
        if let mailboxStatus = filter.mailboxStatus {
            whereClauses.append("m.mailbox_status = '\(mailboxStatus.rawValue)'")
        }

        // Always exclude deleted messages
        whereClauses.append("m.is_deleted = 0")

        // Build the query
        var sql: String

        if filter.hasFreeText, let freeText = filter.freeText {
            // Use FTS with additional filters
            let whereClause = whereClauses.isEmpty ? "" : "AND " + whereClauses.joined(separator: " AND ")
            sql = """
                SELECT m.* FROM messages m
                JOIN messages_fts fts ON m.rowid = fts.rowid
                WHERE messages_fts MATCH '\(escapeSql(freeText))'
                \(whereClause)
                ORDER BY bm25(messages_fts)
                LIMIT \(limit) OFFSET \(offset)
                """
        } else if !whereClauses.isEmpty {
            // Filters only, no FTS
            let whereClause = whereClauses.joined(separator: " AND ")
            sql = """
                SELECT m.* FROM messages m
                WHERE \(whereClause)
                ORDER BY m.date_received DESC
                LIMIT \(limit) OFFSET \(offset)
                """
        } else {
            // No filters, return recent messages
            sql = """
                SELECT * FROM messages m
                WHERE m.is_deleted = 0
                ORDER BY m.date_received DESC
                LIMIT \(limit) OFFSET \(offset)
                """
        }

        let result = try conn.query(sql)

        var messages: [MailMessage] = []
        for row in result {
            if let message = try? rowToMessage(row) {
                messages.append(message)
            }
        }
        return messages
    }

    /// Get all non-deleted messages (for export without search query)
    /// - Parameters:
    ///   - limit: Maximum number of messages to return
    ///   - offset: Number of messages to skip for pagination
    /// - Returns: Array of messages ordered by date received (newest first)
    public func getAllMessages(limit: Int = 100, offset: Int = 0) throws -> [MailMessage] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let query = """
            SELECT * FROM messages
            WHERE is_deleted = 0
            ORDER BY date_received DESC
            LIMIT \(limit) OFFSET \(offset)
            """

        let result = try conn.query(query)
        var messages: [MailMessage] = []
        for row in result {
            if let message = try? rowToMessage(row) {
                messages.append(message)
            }
        }
        return messages
    }

    /// Get messages that haven't been exported yet (export_path IS NULL)
    /// Used for incremental auto-export after sync
    /// - Parameter limit: Maximum number of messages to return (default: unlimited via 0)
    /// - Returns: Array of messages that need to be exported
    public func getMessagesNeedingExport(limit: Int = 0) throws -> [MailMessage] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        var query = """
            SELECT * FROM messages
            WHERE is_deleted = 0 AND export_path IS NULL
            ORDER BY date_received DESC
            """

        if limit > 0 {
            query += " LIMIT \(limit)"
        }

        let result = try conn.query(query)
        var messages: [MailMessage] = []
        for row in result {
            if let message = try? rowToMessage(row) {
                messages.append(message)
            }
        }
        return messages
    }

    /// Update the export path for a message
    public func updateExportPath(id: String, path: String) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)
        _ = try conn.execute("""
            UPDATE messages SET export_path = '\(escapeSql(path))', updated_at = \(now)
            WHERE id = '\(escapeSql(id))'
            """)
    }

    /// Update the body content for a message (on-demand fetching)
    /// - Parameters:
    ///   - id: The message ID
    ///   - bodyText: Plain text body content (optional)
    ///   - bodyHtml: HTML body content (optional)
    public func updateMessageBody(id: String, bodyText: String?, bodyHtml: String?) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)
        _ = try conn.execute("""
            UPDATE messages SET
                body_text = \(bodyText.map { "'\(escapeSql($0))'" } ?? "NULL"),
                body_html = \(bodyHtml.map { "'\(escapeSql($0))'" } ?? "NULL"),
                updated_at = \(now)
            WHERE id = '\(escapeSql(id))'
            """)
    }

    // MARK: - Sync Status Operations

    /// Sync status key constants
    public enum SyncStatusKey {
        public static let state = "sync_state"
        public static let lastSyncTime = "last_sync_time"
        public static let lastSyncStartTime = "last_sync_start_time"
        public static let lastSyncEndTime = "last_sync_end_time"
        public static let lastSyncError = "last_sync_error"
        public static let lastSyncMessagesAdded = "last_sync_messages_added"
        public static let lastSyncMessagesUpdated = "last_sync_messages_updated"
        public static let lastSyncMessagesDeleted = "last_sync_messages_deleted"
        public static let lastSyncDuration = "last_sync_duration"
        public static let lastSyncIsIncremental = "last_sync_is_incremental"
    }

    /// Sync state values
    public enum SyncState: String {
        case idle = "idle"
        case running = "running"
        case success = "success"
        case failed = "failed"
    }

    /// Summary of sync status for reporting
    public struct SyncStatusSummary {
        public let state: SyncState
        public let lastSyncTime: Date?
        public let lastSyncStartTime: Date?
        public let lastSyncEndTime: Date?
        public let lastSyncError: String?
        public let messagesAdded: Int
        public let messagesUpdated: Int
        public let messagesDeleted: Int
        public let duration: TimeInterval?
        public let isIncremental: Bool?

        public init(
            state: SyncState,
            lastSyncTime: Date? = nil,
            lastSyncStartTime: Date? = nil,
            lastSyncEndTime: Date? = nil,
            lastSyncError: String? = nil,
            messagesAdded: Int = 0,
            messagesUpdated: Int = 0,
            messagesDeleted: Int = 0,
            duration: TimeInterval? = nil,
            isIncremental: Bool? = nil
        ) {
            self.state = state
            self.lastSyncTime = lastSyncTime
            self.lastSyncStartTime = lastSyncStartTime
            self.lastSyncEndTime = lastSyncEndTime
            self.lastSyncError = lastSyncError
            self.messagesAdded = messagesAdded
            self.messagesUpdated = messagesUpdated
            self.messagesDeleted = messagesDeleted
            self.duration = duration
            self.isIncremental = isIncremental
        }
    }

    /// Get a sync status value
    public func getSyncStatus(key: String) throws -> String? {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("SELECT value FROM sync_status WHERE key = '\(escapeSql(key))'")

        for row in result {
            return try row.getString(0)
        }
        return nil
    }

    /// Set a sync status value
    public func setSyncStatus(key: String, value: String) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)
        _ = try conn.execute("""
            INSERT INTO sync_status (key, value, updated_at)
            VALUES ('\(escapeSql(key))', '\(escapeSql(value))', \(now))
            ON CONFLICT(key) DO UPDATE SET
                value = excluded.value,
                updated_at = excluded.updated_at
            """)
    }

    /// Get the last sync timestamp
    public func getLastSyncTime() throws -> Date? {
        if let value = try getSyncStatus(key: "last_sync_time"),
           let timestamp = Double(value) {
            return Date(timeIntervalSince1970: timestamp)
        }
        return nil
    }

    /// Set the last sync timestamp
    public func setLastSyncTime(_ date: Date) throws {
        try setSyncStatus(key: SyncStatusKey.lastSyncTime, value: String(date.timeIntervalSince1970))
    }

    /// Record that a sync operation has started
    public func recordSyncStart(isIncremental: Bool) throws {
        let now = Date()
        try setSyncStatus(key: SyncStatusKey.state, value: SyncState.running.rawValue)
        try setSyncStatus(key: SyncStatusKey.lastSyncStartTime, value: String(now.timeIntervalSince1970))
        try setSyncStatus(key: SyncStatusKey.lastSyncIsIncremental, value: isIncremental ? "1" : "0")
        // Clear previous error
        try setSyncStatus(key: SyncStatusKey.lastSyncError, value: "")
    }

    /// Record successful sync completion
    public func recordSyncSuccess(result: SyncResult) throws {
        let now = Date()
        try setSyncStatus(key: SyncStatusKey.state, value: SyncState.success.rawValue)
        try setSyncStatus(key: SyncStatusKey.lastSyncEndTime, value: String(now.timeIntervalSince1970))
        try setSyncStatus(key: SyncStatusKey.lastSyncTime, value: String(now.timeIntervalSince1970))
        try setSyncStatus(key: SyncStatusKey.lastSyncMessagesAdded, value: String(result.messagesAdded))
        try setSyncStatus(key: SyncStatusKey.lastSyncMessagesUpdated, value: String(result.messagesUpdated))
        try setSyncStatus(key: SyncStatusKey.lastSyncMessagesDeleted, value: String(result.messagesDeleted))
        try setSyncStatus(key: SyncStatusKey.lastSyncDuration, value: String(result.duration))
        try setSyncStatus(key: SyncStatusKey.lastSyncError, value: "")
    }

    /// Record sync failure
    public func recordSyncFailure(error: Error) throws {
        let now = Date()
        try setSyncStatus(key: SyncStatusKey.state, value: SyncState.failed.rawValue)
        try setSyncStatus(key: SyncStatusKey.lastSyncEndTime, value: String(now.timeIntervalSince1970))
        try setSyncStatus(key: SyncStatusKey.lastSyncError, value: error.localizedDescription)
    }

    /// Get a summary of the current sync status
    public func getSyncStatusSummary() throws -> SyncStatusSummary {
        let stateStr = try getSyncStatus(key: SyncStatusKey.state)
        let state = stateStr.flatMap { SyncState(rawValue: $0) } ?? .idle

        let lastSyncTime = try getSyncStatus(key: SyncStatusKey.lastSyncTime)
            .flatMap { Double($0) }
            .map { Date(timeIntervalSince1970: $0) }

        let lastSyncStartTime = try getSyncStatus(key: SyncStatusKey.lastSyncStartTime)
            .flatMap { Double($0) }
            .map { Date(timeIntervalSince1970: $0) }

        let lastSyncEndTime = try getSyncStatus(key: SyncStatusKey.lastSyncEndTime)
            .flatMap { Double($0) }
            .map { Date(timeIntervalSince1970: $0) }

        let lastSyncError = try getSyncStatus(key: SyncStatusKey.lastSyncError)
            .flatMap { $0.isEmpty ? nil : $0 }

        let messagesAdded = try getSyncStatus(key: SyncStatusKey.lastSyncMessagesAdded)
            .flatMap { Int($0) } ?? 0

        let messagesUpdated = try getSyncStatus(key: SyncStatusKey.lastSyncMessagesUpdated)
            .flatMap { Int($0) } ?? 0

        let messagesDeleted = try getSyncStatus(key: SyncStatusKey.lastSyncMessagesDeleted)
            .flatMap { Int($0) } ?? 0

        let duration = try getSyncStatus(key: SyncStatusKey.lastSyncDuration)
            .flatMap { Double($0) }

        let isIncremental = try getSyncStatus(key: SyncStatusKey.lastSyncIsIncremental)
            .map { $0 == "1" }

        return SyncStatusSummary(
            state: state,
            lastSyncTime: lastSyncTime,
            lastSyncStartTime: lastSyncStartTime,
            lastSyncEndTime: lastSyncEndTime,
            lastSyncError: lastSyncError,
            messagesAdded: messagesAdded,
            messagesUpdated: messagesUpdated,
            messagesDeleted: messagesDeleted,
            duration: duration,
            isIncremental: isIncremental
        )
    }

    // MARK: - Mailbox Operations

    /// Upsert a mailbox
    public func upsertMailbox(_ mailbox: Mailbox) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)
        _ = try conn.execute("""
            INSERT INTO mailboxes (id, account_id, name, full_path, parent_id, message_count, unread_count, synced_at)
            VALUES (\(mailbox.id), '\(escapeSql(mailbox.accountId))', '\(escapeSql(mailbox.name))',
                    '\(escapeSql(mailbox.fullPath))', \(mailbox.parentId ?? 0), \(mailbox.messageCount),
                    \(mailbox.unreadCount), \(now))
            ON CONFLICT(id) DO UPDATE SET
                account_id = excluded.account_id,
                name = excluded.name,
                full_path = excluded.full_path,
                parent_id = excluded.parent_id,
                message_count = excluded.message_count,
                unread_count = excluded.unread_count,
                synced_at = excluded.synced_at
            """)
    }

    /// Get all mailboxes
    public func getMailboxes() throws -> [Mailbox] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("SELECT * FROM mailboxes ORDER BY full_path")

        var mailboxes: [Mailbox] = []
        for row in result {
            if let mailbox = try? rowToMailbox(row) {
                mailboxes.append(mailbox)
            }
        }
        return mailboxes
    }

    // MARK: - FTS5 Trigger Management

    /// Disable FTS5 triggers to prevent per-row FTS updates during bulk operations.
    /// Call `rebuildFTSIndex()` after bulk operations complete to sync the FTS index.
    public func disableFTSTriggers() throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        _ = try conn.execute("DROP TRIGGER IF EXISTS messages_ai")
        _ = try conn.execute("DROP TRIGGER IF EXISTS messages_ad")
        _ = try conn.execute("DROP TRIGGER IF EXISTS messages_au")
    }

    /// Re-enable FTS5 triggers for incremental updates after bulk operations.
    public func enableFTSTriggers() throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        // Recreate the triggers (same as in migration)
        _ = try conn.execute("""
            CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
                INSERT INTO messages_fts(rowid, subject, sender_name, sender_email, body_text)
                VALUES (NEW.rowid, NEW.subject, NEW.sender_name, NEW.sender_email, NEW.body_text);
            END
            """)

        _ = try conn.execute("""
            CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
                INSERT INTO messages_fts(messages_fts, rowid, subject, sender_name, sender_email, body_text)
                VALUES ('delete', OLD.rowid, OLD.subject, OLD.sender_name, OLD.sender_email, OLD.body_text);
            END
            """)

        _ = try conn.execute("""
            CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
                INSERT INTO messages_fts(messages_fts, rowid, subject, sender_name, sender_email, body_text)
                VALUES ('delete', OLD.rowid, OLD.subject, OLD.sender_name, OLD.sender_email, OLD.body_text);
                INSERT INTO messages_fts(rowid, subject, sender_name, sender_email, body_text)
                VALUES (NEW.rowid, NEW.subject, NEW.sender_name, NEW.sender_email, NEW.body_text);
            END
            """)
    }

    /// Rebuild the FTS5 index from scratch using the messages table content.
    /// This is much faster than per-row trigger updates for bulk operations.
    /// Should be called after `disableFTSTriggers()` + bulk operations.
    public func rebuildFTSIndex() throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        // Delete all FTS content and rebuild from the messages table
        // The 'rebuild' command is a special FTS5 command that repopulates from the content table
        _ = try conn.execute("INSERT INTO messages_fts(messages_fts) VALUES('rebuild')")
    }

    // MARK: - Batch Insert Operations

    /// Configuration for batch insert operations
    public struct BatchInsertConfig: Sendable {
        /// Number of messages to insert per transaction batch
        public let batchSize: Int

        /// Whether to disable FTS triggers during bulk operations (recommended for large syncs)
        public let disableFTSTriggersForBulk: Bool

        /// Default configuration with batch size of 1000 and FTS trigger optimization enabled
        public static let `default` = BatchInsertConfig(batchSize: 1000, disableFTSTriggersForBulk: true)

        public init(batchSize: Int = 1000, disableFTSTriggersForBulk: Bool = true) {
            self.batchSize = max(1, batchSize)  // Ensure at least 1
            self.disableFTSTriggersForBulk = disableFTSTriggersForBulk
        }
    }

    /// Result of a batch insert operation
    public struct BatchInsertResult: Sendable {
        public let inserted: Int
        public let updated: Int
        public let failed: Int
        public let errors: [String]
        public let duration: TimeInterval

        public init(inserted: Int, updated: Int, failed: Int, errors: [String], duration: TimeInterval) {
            self.inserted = inserted
            self.updated = updated
            self.failed = failed
            self.errors = errors
            self.duration = duration
        }
    }

    /// Insert or update multiple messages in batched transactions for improved performance.
    /// Each batch is wrapped in a transaction for atomicity - if any insert in a batch fails,
    /// the entire batch is rolled back.
    ///
    /// When `config.disableFTSTriggersForBulk` is true (default), FTS5 triggers are disabled
    /// during the bulk operation and the FTS index is rebuilt once at the end. This prevents
    /// the O(n^2) slowdown caused by per-row FTS trigger updates.
    ///
    /// - Parameters:
    ///   - messages: Array of messages to insert/update
    ///   - config: Batch configuration (default batch size: 1000)
    /// - Returns: Result with counts and any errors
    public func batchUpsertMessages(_ messages: [MailMessage], config: BatchInsertConfig = .default) throws -> BatchInsertResult {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let startTime = Date()
        var totalInserted = 0
        var totalUpdated = 0
        var totalFailed = 0
        var errors: [String] = []

        let now = Int(Date().timeIntervalSince1970)

        // Disable FTS triggers for bulk operations to prevent per-row FTS updates
        // This is critical for performance: without this, second sync takes 5+ minutes
        // because each UPDATE fires 2 FTS operations (delete old + insert new)
        if config.disableFTSTriggersForBulk {
            try disableFTSTriggers()
        }

        defer {
            // Always re-enable triggers and rebuild FTS index
            if config.disableFTSTriggersForBulk {
                do {
                    try rebuildFTSIndex()
                    try enableFTSTriggers()
                } catch {
                    errors.append("FTS rebuild failed: \(error.localizedDescription)")
                }
            }
        }

        // Process in batches
        let batches = stride(from: 0, to: messages.count, by: config.batchSize).map { startIndex in
            let endIndex = min(startIndex + config.batchSize, messages.count)
            return Array(messages[startIndex..<endIndex])
        }

        for (batchIndex, batch) in batches.enumerated() {
            do {
                let (inserted, updated) = try executeBatchTransaction(batch, connection: conn, timestamp: now)
                totalInserted += inserted
                totalUpdated += updated
            } catch {
                // Batch failed - record error and count all messages in batch as failed
                totalFailed += batch.count
                errors.append("Batch \(batchIndex + 1) failed: \(error.localizedDescription)")
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        return BatchInsertResult(
            inserted: totalInserted,
            updated: totalUpdated,
            failed: totalFailed,
            errors: errors,
            duration: duration
        )
    }

    /// Execute a single batch of inserts within a transaction
    private func executeBatchTransaction(_ messages: [MailMessage], connection conn: Connection, timestamp: Int) throws -> (inserted: Int, updated: Int) {
        var inserted = 0
        var updated = 0

        // Begin transaction
        _ = try conn.execute("BEGIN TRANSACTION")

        do {
            for message in messages {
                // Check if message exists (for tracking insert vs update)
                let existsResult = try conn.query("SELECT 1 FROM messages WHERE id = '\(escapeSql(message.id))' LIMIT 1")
                var exists = false
                for _ in existsResult {
                    exists = true
                    break
                }

                // Serialize references to JSON for storage
                let referencesJson = serializeReferences(message.references)

                // Execute upsert
                _ = try conn.execute("""
                    INSERT INTO messages (
                        id, apple_rowid, message_id, mailbox_id, mailbox_name, account_id,
                        subject, sender_name, sender_email, date_sent, date_received,
                        is_read, is_flagged, is_deleted, has_attachments, emlx_path,
                        body_text, body_html, synced_at, updated_at,
                        mailbox_status, pending_sync_action, last_known_mailbox_id,
                        in_reply_to, threading_references, thread_id,
                        thread_position, thread_total
                    ) VALUES (
                        '\(escapeSql(message.id))', \(message.appleRowId ?? 0), \(message.messageId.map { "'\(escapeSql($0))'" } ?? "NULL"),
                        \(message.mailboxId ?? 0), \(message.mailboxName.map { "'\(escapeSql($0))'" } ?? "NULL"),
                        \(message.accountId.map { "'\(escapeSql($0))'" } ?? "NULL"),
                        '\(escapeSql(message.subject))', \(message.senderName.map { "'\(escapeSql($0))'" } ?? "NULL"),
                        \(message.senderEmail.map { "'\(escapeSql($0))'" } ?? "NULL"),
                        \(message.dateSent.map { Int($0.timeIntervalSince1970) } ?? 0),
                        \(message.dateReceived.map { Int($0.timeIntervalSince1970) } ?? 0),
                        \(message.isRead ? 1 : 0), \(message.isFlagged ? 1 : 0), \(message.isDeleted ? 1 : 0),
                        \(message.hasAttachments ? 1 : 0), \(message.emlxPath.map { "'\(escapeSql($0))'" } ?? "NULL"),
                        \(message.bodyText.map { "'\(escapeSql($0))'" } ?? "NULL"),
                        \(message.bodyHtml.map { "'\(escapeSql($0))'" } ?? "NULL"),
                        \(timestamp), \(timestamp),
                        '\(message.mailboxStatus.rawValue)',
                        \(message.pendingSyncAction.map { "'\($0.rawValue)'" } ?? "NULL"),
                        \(message.lastKnownMailboxId.map { String($0) } ?? "NULL"),
                        \(message.inReplyTo.map { "'\(escapeSql($0))'" } ?? "NULL"),
                        \(referencesJson.map { "'\(escapeSql($0))'" } ?? "NULL"),
                        \(message.threadId.map { "'\(escapeSql($0))'" } ?? "NULL"),
                        \(message.threadPosition.map { String($0) } ?? "NULL"),
                        \(message.threadTotal.map { String($0) } ?? "NULL")
                    )
                    ON CONFLICT(id) DO UPDATE SET
                        apple_rowid = excluded.apple_rowid,
                        message_id = excluded.message_id,
                        mailbox_id = excluded.mailbox_id,
                        mailbox_name = excluded.mailbox_name,
                        account_id = excluded.account_id,
                        subject = excluded.subject,
                        sender_name = excluded.sender_name,
                        sender_email = excluded.sender_email,
                        date_sent = excluded.date_sent,
                        date_received = excluded.date_received,
                        is_read = excluded.is_read,
                        is_flagged = excluded.is_flagged,
                        is_deleted = excluded.is_deleted,
                        has_attachments = excluded.has_attachments,
                        emlx_path = excluded.emlx_path,
                        body_text = excluded.body_text,
                        body_html = excluded.body_html,
                        updated_at = \(timestamp),
                        mailbox_status = excluded.mailbox_status,
                        pending_sync_action = excluded.pending_sync_action,
                        last_known_mailbox_id = excluded.last_known_mailbox_id,
                        in_reply_to = excluded.in_reply_to,
                        threading_references = excluded.threading_references,
                        thread_id = excluded.thread_id,
                        thread_position = excluded.thread_position,
                        thread_total = excluded.thread_total
                    """)

                if exists {
                    updated += 1
                } else {
                    inserted += 1
                }
            }

            // Commit transaction
            _ = try conn.execute("COMMIT")

            return (inserted, updated)
        } catch {
            // Rollback on any error
            _ = try? conn.execute("ROLLBACK")
            throw error
        }
    }

    /// Insert or update multiple mailboxes in a single transaction for improved performance.
    ///
    /// - Parameter mailboxes: Array of mailboxes to insert/update
    public func batchUpsertMailboxes(_ mailboxes: [Mailbox]) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)

        // Begin transaction
        _ = try conn.execute("BEGIN TRANSACTION")

        do {
            for mailbox in mailboxes {
                _ = try conn.execute("""
                    INSERT INTO mailboxes (id, account_id, name, full_path, parent_id, message_count, unread_count, synced_at)
                    VALUES (\(mailbox.id), '\(escapeSql(mailbox.accountId))', '\(escapeSql(mailbox.name))',
                            '\(escapeSql(mailbox.fullPath))', \(mailbox.parentId ?? 0), \(mailbox.messageCount),
                            \(mailbox.unreadCount), \(now))
                    ON CONFLICT(id) DO UPDATE SET
                        account_id = excluded.account_id,
                        name = excluded.name,
                        full_path = excluded.full_path,
                        parent_id = excluded.parent_id,
                        message_count = excluded.message_count,
                        unread_count = excluded.unread_count,
                        synced_at = excluded.synced_at
                    """)
            }

            // Commit transaction
            _ = try conn.execute("COMMIT")
        } catch {
            // Rollback on any error
            _ = try? conn.execute("ROLLBACK")
            throw error
        }
    }

    // MARK: - Incremental Sync Support

    /// Represents minimal message status info for change detection
    public struct MessageStatus {
        public let id: String
        public let appleRowId: Int
        public let isRead: Bool
        public let isFlagged: Bool
    }

    /// Get all message statuses for change detection
    public func getAllMessageStatuses() throws -> [MessageStatus] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("""
            SELECT id, apple_rowid, is_read, is_flagged
            FROM messages
            WHERE is_deleted = 0 AND apple_rowid IS NOT NULL
            """)

        var statuses: [MessageStatus] = []
        for row in result {
            guard let id = getStringValue(row, 0),
                  let appleRowId = getIntValue(row, 1) else {
                continue
            }
            let isRead = (getIntValue(row, 2) ?? 0) == 1
            let isFlagged = (getIntValue(row, 3) ?? 0) == 1
            statuses.append(MessageStatus(id: id, appleRowId: appleRowId, isRead: isRead, isFlagged: isFlagged))
        }
        return statuses
    }

    /// Update the read/flagged status of a message
    public func updateMessageStatus(id: String, isRead: Bool, isFlagged: Bool) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)
        _ = try conn.execute("""
            UPDATE messages
            SET is_read = \(isRead ? 1 : 0), is_flagged = \(isFlagged ? 1 : 0), updated_at = \(now)
            WHERE id = '\(escapeSql(id))'
            """)
    }

    /// Get all Apple rowids from the mirror for deletion detection
    public func getAllAppleRowIds() throws -> [Int] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("""
            SELECT apple_rowid FROM messages
            WHERE is_deleted = 0 AND apple_rowid IS NOT NULL
            """)

        var rowIds: [Int] = []
        for row in result {
            if let rowId = getIntValue(row, 0) {
                rowIds.append(rowId)
            }
        }
        return rowIds
    }

    /// Mark a message as deleted (soft delete)
    public func markMessageDeleted(appleRowId: Int) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)
        _ = try conn.execute("""
            UPDATE messages SET is_deleted = 1, updated_at = \(now)
            WHERE apple_rowid = \(appleRowId)
            """)
    }

    // MARK: - Mailbox Status Operations (Bidirectional Sync)

    /// Update the mailbox status of a message
    /// - Parameters:
    ///   - id: The message ID
    ///   - status: The new mailbox status (inbox, archived, deleted)
    public func updateMailboxStatus(id: String, status: MailboxStatus) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)
        _ = try conn.execute("""
            UPDATE messages SET mailbox_status = '\(status.rawValue)', updated_at = \(now)
            WHERE id = '\(escapeSql(id))'
            """)
    }

    /// Set a pending sync action for a message
    /// - Parameters:
    ///   - id: The message ID
    ///   - action: The sync action to queue (archive or delete)
    public func setPendingSyncAction(id: String, action: SyncAction) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)
        _ = try conn.execute("""
            UPDATE messages SET pending_sync_action = '\(action.rawValue)', updated_at = \(now)
            WHERE id = '\(escapeSql(id))'
            """)
    }

    /// Clear the pending sync action for a message (after successful sync)
    /// - Parameter id: The message ID
    public func clearPendingSyncAction(id: String) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)
        _ = try conn.execute("""
            UPDATE messages SET pending_sync_action = NULL, updated_at = \(now)
            WHERE id = '\(escapeSql(id))'
            """)
    }

    /// Get all messages with pending sync actions
    /// - Returns: Array of messages that have pending actions to sync to Apple Mail
    public func getMessagesWithPendingActions() throws -> [MailMessage] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("""
            SELECT * FROM messages
            WHERE pending_sync_action IS NOT NULL AND is_deleted = 0
            ORDER BY updated_at ASC
            """)

        var messages: [MailMessage] = []
        for row in result {
            if let message = try? rowToMessage(row) {
                messages.append(message)
            }
        }
        return messages
    }

    /// Get messages filtered by mailbox status
    /// - Parameters:
    ///   - status: The mailbox status to filter by
    ///   - limit: Maximum number of messages to return (default: 100)
    ///   - offset: Number of messages to skip for pagination (default: 0)
    /// - Returns: Array of messages with the specified status
    public func getMessagesByStatus(_ status: MailboxStatus, limit: Int = 100, offset: Int = 0) throws -> [MailMessage] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("""
            SELECT * FROM messages
            WHERE mailbox_status = '\(status.rawValue)' AND is_deleted = 0
            ORDER BY date_received DESC
            LIMIT \(limit) OFFSET \(offset)
            """)

        var messages: [MailMessage] = []
        for row in result {
            if let message = try? rowToMessage(row) {
                messages.append(message)
            }
        }
        return messages
    }

    /// Get message counts grouped by mailbox status
    /// - Returns: Dictionary with status as key and count as value
    public func getMessageCountByStatus() throws -> [MailboxStatus: Int] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("""
            SELECT mailbox_status, COUNT(*) as count FROM messages
            WHERE is_deleted = 0
            GROUP BY mailbox_status
            """)

        var counts: [MailboxStatus: Int] = [
            .inbox: 0,
            .archived: 0,
            .deleted: 0
        ]

        for row in result {
            if let statusStr = getStringValue(row, 0),
               let status = MailboxStatus(rawValue: statusStr),
               let count = getIntValue(row, 1) {
                counts[status] = count
            }
        }
        return counts
    }

    /// Represents tracked message info for mailbox move detection
    public struct TrackedMessageInfo {
        public let id: String
        public let appleRowId: Int
        public let mailboxId: Int?
        public let mailboxStatus: MailboxStatus
    }

    /// Get all tracked messages with their mailbox IDs for move detection
    /// This includes all messages (inbox, archived, deleted status) so we can detect
    /// when messages move between mailboxes, including moves back to INBOX.
    /// - Returns: Array of tracked message info for all non-soft-deleted messages
    public func getTrackedInboxMessages() throws -> [TrackedMessageInfo] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("""
            SELECT id, apple_rowid, mailbox_id, mailbox_status
            FROM messages
            WHERE is_deleted = 0
              AND apple_rowid IS NOT NULL
            """)

        var messages: [TrackedMessageInfo] = []
        for row in result {
            guard let id = getStringValue(row, 0),
                  let appleRowId = getIntValue(row, 1) else {
                continue
            }
            let mailboxId = getIntValue(row, 2)
            let statusStr = getStringValue(row, 3)
            let status = statusStr.flatMap { MailboxStatus(rawValue: $0) } ?? .inbox

            messages.append(TrackedMessageInfo(
                id: id,
                appleRowId: appleRowId,
                mailboxId: mailboxId,
                mailboxStatus: status
            ))
        }
        return messages
    }

    // MARK: - Thread Operations

    /// Insert or update a thread in the database
    public func upsertThread(_ thread: Thread) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)

        _ = try conn.execute("""
            INSERT INTO threads (
                id, subject, participant_count, message_count, first_date, last_date,
                created_at, updated_at
            ) VALUES (
                '\(escapeSql(thread.id))',
                \(thread.subject.map { "'\(escapeSql($0))'" } ?? "NULL"),
                \(thread.participantCount),
                \(thread.messageCount),
                \(thread.firstDate.map { String(Int($0.timeIntervalSince1970)) } ?? "NULL"),
                \(thread.lastDate.map { String(Int($0.timeIntervalSince1970)) } ?? "NULL"),
                \(now), \(now)
            )
            ON CONFLICT(id) DO UPDATE SET
                subject = COALESCE(excluded.subject, threads.subject),
                participant_count = excluded.participant_count,
                message_count = excluded.message_count,
                first_date = MIN(COALESCE(threads.first_date, excluded.first_date), COALESCE(excluded.first_date, threads.first_date)),
                last_date = MAX(COALESCE(threads.last_date, excluded.last_date), COALESCE(excluded.last_date, threads.last_date)),
                updated_at = \(now)
            """)
    }

    /// Get a thread by its ID
    public func getThread(id: String) throws -> Thread? {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("SELECT * FROM threads WHERE id = '\(escapeSql(id))'")

        for row in result {
            return try rowToThread(row)
        }
        return nil
    }

    /// Get all threads, ordered by last date descending
    public func getThreads(limit: Int = 100, offset: Int = 0) throws -> [Thread] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("""
            SELECT * FROM threads
            ORDER BY last_date DESC
            LIMIT \(limit) OFFSET \(offset)
            """)

        var threads: [Thread] = []
        for row in result {
            if let thread = try? rowToThread(row) {
                threads.append(thread)
            }
        }
        return threads
    }

    /// Get threads with filtering and sorting options
    /// - Parameters:
    ///   - limit: Maximum number of threads to return
    ///   - offset: Number of threads to skip (for pagination)
    ///   - sortBy: Sort order for results
    ///   - participant: Filter by participant email (matches sender or recipient)
    /// - Returns: Array of threads matching the criteria
    public func getThreads(
        limit: Int = 100,
        offset: Int = 0,
        sortBy: ThreadSortOrder = .date,
        participant: String? = nil
    ) throws -> [Thread] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        var sql: String
        if let participant = participant {
            // Filter threads by participant (sender or recipient in any message)
            // Uses EXISTS subqueries for better query plan optimization vs JOINs
            // Note: LIKE with leading % cannot use indexes, but EXISTS limits the scan
            // to messages within each thread rather than a full cross-join
            let escaped = escapeSql(participant.lowercased())
            sql = """
                SELECT t.* FROM threads t
                WHERE EXISTS (
                    SELECT 1 FROM thread_messages tm
                    JOIN messages m ON tm.message_id = m.id
                    WHERE tm.thread_id = t.id
                    AND LOWER(m.sender_email) LIKE '%\(escaped)%'
                )
                OR EXISTS (
                    SELECT 1 FROM thread_messages tm
                    JOIN messages m ON tm.message_id = m.id
                    JOIN recipients r ON m.id = r.message_id
                    WHERE tm.thread_id = t.id
                    AND LOWER(r.email) LIKE '%\(escaped)%'
                )
                ORDER BY t.\(sortBy.sqlOrderBy)
                LIMIT \(limit) OFFSET \(offset)
                """
        } else {
            sql = """
                SELECT * FROM threads
                ORDER BY \(sortBy.sqlOrderBy)
                LIMIT \(limit) OFFSET \(offset)
                """
        }

        let result = try conn.query(sql)

        var threads: [Thread] = []
        for row in result {
            if let thread = try? rowToThread(row) {
                threads.append(thread)
            }
        }
        return threads
    }

    /// Get count of threads matching filter criteria
    /// - Parameter participant: Filter by participant email (matches sender or recipient)
    /// - Returns: Count of matching threads
    public func getThreadCount(participant: String? = nil) throws -> Int {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        var sql: String
        if let participant = participant {
            // Use EXISTS subqueries for efficient counting with participant filter
            let escaped = escapeSql(participant.lowercased())
            sql = """
                SELECT COUNT(*) FROM threads t
                WHERE EXISTS (
                    SELECT 1 FROM thread_messages tm
                    JOIN messages m ON tm.message_id = m.id
                    WHERE tm.thread_id = t.id
                    AND LOWER(m.sender_email) LIKE '%\(escaped)%'
                )
                OR EXISTS (
                    SELECT 1 FROM thread_messages tm
                    JOIN messages m ON tm.message_id = m.id
                    JOIN recipients r ON m.id = r.message_id
                    WHERE tm.thread_id = t.id
                    AND LOWER(r.email) LIKE '%\(escaped)%'
                )
                """
        } else {
            sql = "SELECT COUNT(*) FROM threads"
        }

        let result = try conn.query(sql)
        for row in result {
            return getIntValue(row, 0) ?? 0
        }
        return 0
    }

    /// Get all messages in a thread
    public func getMessagesInThread(threadId: String, limit: Int = 100, offset: Int = 0) throws -> [MailMessage] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("""
            SELECT * FROM messages
            WHERE thread_id = '\(escapeSql(threadId))' AND is_deleted = 0
            ORDER BY date_received ASC
            LIMIT \(limit) OFFSET \(offset)
            """)

        var messages: [MailMessage] = []
        for row in result {
            if let message = try? rowToMessage(row) {
                messages.append(message)
            }
        }
        return messages
    }

    /// Update the thread_id for a message
    public func updateMessageThreadId(messageId: String, threadId: String) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)
        _ = try conn.execute("""
            UPDATE messages SET thread_id = '\(escapeSql(threadId))', updated_at = \(now)
            WHERE id = '\(escapeSql(messageId))'
            """)
    }

    /// Update the thread position metadata for a message
    /// - Parameters:
    ///   - messageId: The message ID to update
    ///   - threadPosition: Position of the message within its thread (1-based)
    ///   - threadTotal: Total number of messages in the thread
    public func updateMessageThreadPosition(messageId: String, threadPosition: Int, threadTotal: Int) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)
        _ = try conn.execute("""
            UPDATE messages SET thread_position = \(threadPosition), thread_total = \(threadTotal), updated_at = \(now)
            WHERE id = '\(escapeSql(messageId))'
            """)
    }

    /// Update thread position metadata for all messages in a thread
    /// Uses batch update for efficiency with large threads
    /// - Parameter threadId: The thread ID whose messages should be updated
    public func updateThreadPositions(threadId: String) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        // Get all messages in the thread ordered by date
        let messages = try getMessagesInThreadViaJunction(threadId: threadId, limit: 10000, offset: 0)
        let total = messages.count

        if total == 0 {
            return
        }

        // For small threads, use individual updates (simpler, avoids query size limits)
        if total <= 10 {
            for (index, message) in messages.enumerated() {
                try updateMessageThreadPosition(messageId: message.id, threadPosition: index + 1, threadTotal: total)
            }
            return
        }

        // For larger threads, use batch update with CASE statement for efficiency
        // This reduces N database round trips to just 1
        let now = Int(Date().timeIntervalSince1970)

        // Build CASE statement for positions
        var caseClauses: [String] = []
        var idList: [String] = []
        for (index, message) in messages.enumerated() {
            let escapedId = escapeSql(message.id)
            caseClauses.append("WHEN '\(escapedId)' THEN \(index + 1)")
            idList.append("'\(escapedId)'")
        }

        let sql = """
            UPDATE messages SET
                thread_position = CASE id
                    \(caseClauses.joined(separator: "\n                "))
                    ELSE thread_position
                END,
                thread_total = \(total),
                updated_at = \(now)
            WHERE id IN (\(idList.joined(separator: ", ")))
            """

        _ = try conn.execute(sql)
    }

    /// Get the count of threads
    public func getThreadCount() throws -> Int {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("SELECT COUNT(*) FROM threads")
        for row in result {
            return getIntValue(row, 0) ?? 0
        }
        return 0
    }

    // MARK: - Thread-Message Junction Operations

    /// Add a message to a thread (creates the junction table entry)
    /// - Parameters:
    ///   - messageId: The message ID to add
    ///   - threadId: The thread ID to add the message to
    public func addMessageToThread(messageId: String, threadId: String) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        _ = try conn.execute("""
            INSERT OR IGNORE INTO thread_messages (thread_id, message_id)
            VALUES ('\(escapeSql(threadId))', '\(escapeSql(messageId))')
            """)
    }

    /// Remove a message from a thread (deletes the junction table entry)
    /// - Parameters:
    ///   - messageId: The message ID to remove
    ///   - threadId: The thread ID to remove the message from
    public func removeMessageFromThread(messageId: String, threadId: String) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        _ = try conn.execute("""
            DELETE FROM thread_messages
            WHERE thread_id = '\(escapeSql(threadId))' AND message_id = '\(escapeSql(messageId))'
            """)
    }

    /// Get all message IDs in a thread via the junction table
    /// - Parameter threadId: The thread ID to query
    /// - Returns: Array of message IDs in the thread
    public func getMessageIdsInThread(threadId: String) throws -> [String] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("""
            SELECT message_id FROM thread_messages
            WHERE thread_id = '\(escapeSql(threadId))'
            ORDER BY added_at ASC
            """)

        var messageIds: [String] = []
        for row in result {
            if let messageId = getStringValue(row, 0) {
                messageIds.append(messageId)
            }
        }
        return messageIds
    }

    /// Get all thread IDs that a message belongs to via the junction table
    /// - Parameter messageId: The message ID to query
    /// - Returns: Array of thread IDs the message belongs to
    public func getThreadIdsForMessage(messageId: String) throws -> [String] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("""
            SELECT thread_id FROM thread_messages
            WHERE message_id = '\(escapeSql(messageId))'
            ORDER BY added_at ASC
            """)

        var threadIds: [String] = []
        for row in result {
            if let threadId = getStringValue(row, 0) {
                threadIds.append(threadId)
            }
        }
        return threadIds
    }

    /// Get full messages in a thread via the junction table
    /// - Parameters:
    ///   - threadId: The thread ID to query
    ///   - limit: Maximum number of messages to return
    ///   - offset: Number of messages to skip for pagination
    /// - Returns: Array of MailMessage objects in the thread
    public func getMessagesInThreadViaJunction(threadId: String, limit: Int = 100, offset: Int = 0) throws -> [MailMessage] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("""
            SELECT m.* FROM messages m
            JOIN thread_messages tm ON m.id = tm.message_id
            WHERE tm.thread_id = '\(escapeSql(threadId))' AND m.is_deleted = 0
            ORDER BY m.date_received ASC
            LIMIT \(limit) OFFSET \(offset)
            """)

        var messages: [MailMessage] = []
        for row in result {
            if let message = try? rowToMessage(row) {
                messages.append(message)
            }
        }
        return messages
    }

    /// Get full threads that a message belongs to via the junction table
    /// - Parameter messageId: The message ID to query
    /// - Returns: Array of Thread objects the message belongs to
    public func getThreadsForMessage(messageId: String) throws -> [Thread] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("""
            SELECT t.* FROM threads t
            JOIN thread_messages tm ON t.id = tm.thread_id
            WHERE tm.message_id = '\(escapeSql(messageId))'
            ORDER BY t.last_date DESC
            """)

        var threads: [Thread] = []
        for row in result {
            if let thread = try? rowToThread(row) {
                threads.append(thread)
            }
        }
        return threads
    }

    /// Get the count of messages in a thread via the junction table
    /// - Parameter threadId: The thread ID to query
    /// - Returns: Number of messages in the thread
    public func getMessageCountInThread(threadId: String) throws -> Int {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("""
            SELECT COUNT(*) FROM thread_messages
            WHERE thread_id = '\(escapeSql(threadId))'
            """)

        for row in result {
            return getIntValue(row, 0) ?? 0
        }
        return 0
    }

    /// Check if a message is in a thread
    /// - Parameters:
    ///   - messageId: The message ID to check
    ///   - threadId: The thread ID to check
    /// - Returns: True if the message is in the thread
    public func isMessageInThread(messageId: String, threadId: String) throws -> Bool {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("""
            SELECT 1 FROM thread_messages
            WHERE thread_id = '\(escapeSql(threadId))' AND message_id = '\(escapeSql(messageId))'
            LIMIT 1
            """)

        for _ in result {
            return true
        }
        return false
    }

    // MARK: - Helpers

    private func escapeSql(_ string: String) -> String {
        string.replacingOccurrences(of: "'", with: "''")
    }

    /// Serialize a references array to JSON string for database storage
    private func serializeReferences(_ references: [String]) -> String? {
        guard !references.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(references),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    /// Deserialize a JSON string to references array
    private func deserializeReferences(_ json: String?) -> [String] {
        guard let json = json,
              let data = json.data(using: .utf8),
              let references = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return references
    }
}

/// Parse a date string in YYYY-MM-DD format
private func parseDate(_ string: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone.current
    return formatter.date(from: string)
}

extension MailDatabase {

    private func getValue(_ row: Row, _ index: Int32) -> Value? {
        try? row.get(index)
    }

    private func getStringValue(_ row: Row, _ index: Int32) -> String? {
        guard let value = getValue(row, index) else { return nil }
        if case .text(let str) = value {
            return str
        }
        return nil
    }

    private func getIntValue(_ row: Row, _ index: Int32) -> Int? {
        guard let value = getValue(row, index) else { return nil }
        if case .integer(let num) = value {
            return Int(num)
        }
        return nil
    }

    private func rowToMessage(_ row: Row) throws -> MailMessage {
        // Parse mailbox_status (column 21) - default to .inbox if null or unknown
        let mailboxStatusStr = getStringValue(row, 21)
        let mailboxStatus = mailboxStatusStr.flatMap { MailboxStatus(rawValue: $0) } ?? .inbox

        // Parse pending_sync_action (column 22) - nullable
        let pendingSyncActionStr = getStringValue(row, 22)
        let pendingSyncAction = pendingSyncActionStr.flatMap { SyncAction(rawValue: $0) }

        // Parse threading headers (columns 24, 25) - added in migration V3
        let inReplyTo = getStringValue(row, 24)
        let referencesJson = getStringValue(row, 25)
        let references = deserializeReferences(referencesJson)

        // Parse thread_id (column 26) - added in migration V4
        let threadId = getStringValue(row, 26)

        // Parse thread_position (column 27) and thread_total (column 28) - added in migration V6
        let threadPosition = getIntValue(row, 27)
        let threadTotal = getIntValue(row, 28)

        return MailMessage(
            id: getStringValue(row, 0) ?? "",
            appleRowId: getIntValue(row, 1),
            messageId: getStringValue(row, 2),
            mailboxId: getIntValue(row, 3),
            mailboxName: getStringValue(row, 4),
            accountId: getStringValue(row, 5),
            subject: getStringValue(row, 6) ?? "",
            senderName: getStringValue(row, 7),
            senderEmail: getStringValue(row, 8),
            dateSent: getIntValue(row, 9).map { Date(timeIntervalSince1970: Double($0)) },
            dateReceived: getIntValue(row, 10).map { Date(timeIntervalSince1970: Double($0)) },
            isRead: (getIntValue(row, 11) ?? 0) == 1,
            isFlagged: (getIntValue(row, 12) ?? 0) == 1,
            isDeleted: (getIntValue(row, 13) ?? 0) == 1,
            hasAttachments: (getIntValue(row, 14) ?? 0) == 1,
            emlxPath: getStringValue(row, 15),
            bodyText: getStringValue(row, 16),
            bodyHtml: getStringValue(row, 17),
            exportPath: getStringValue(row, 18),
            mailboxStatus: mailboxStatus,
            pendingSyncAction: pendingSyncAction,
            lastKnownMailboxId: getIntValue(row, 23),
            inReplyTo: inReplyTo,
            references: references,
            threadId: threadId,
            threadPosition: threadPosition,
            threadTotal: threadTotal
        )
    }

    private func rowToMailbox(_ row: Row) throws -> Mailbox {
        Mailbox(
            id: getIntValue(row, 0) ?? 0,
            accountId: getStringValue(row, 1) ?? "",
            name: getStringValue(row, 2) ?? "",
            fullPath: getStringValue(row, 3) ?? "",
            parentId: getIntValue(row, 4),
            messageCount: getIntValue(row, 5) ?? 0,
            unreadCount: getIntValue(row, 6) ?? 0
        )
    }

    private func rowToThread(_ row: Row) throws -> Thread {
        Thread(
            id: getStringValue(row, 0) ?? "",
            subject: getStringValue(row, 1),
            participantCount: getIntValue(row, 2) ?? 0,
            messageCount: getIntValue(row, 3) ?? 0,
            firstDate: getIntValue(row, 4).map { Date(timeIntervalSince1970: Double($0)) },
            lastDate: getIntValue(row, 5).map { Date(timeIntervalSince1970: Double($0)) },
            createdAt: getIntValue(row, 6).map { Date(timeIntervalSince1970: Double($0)) },
            updatedAt: getIntValue(row, 7).map { Date(timeIntervalSince1970: Double($0)) }
        )
    }

    // MARK: - Index Verification (for testing)

    /// Get list of indexes on a table
    /// - Parameter tableName: The table to query indexes for
    /// - Returns: Array of index names
    public func getIndexes(on tableName: String) throws -> [String] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("PRAGMA index_list('\(escapeSql(tableName))')")
        var indexes: [String] = []
        for row in result {
            if let name = getStringValue(row, 1) {
                indexes.append(name)
            }
        }
        return indexes
    }

    /// Run EXPLAIN QUERY PLAN and return the plan details
    /// - Parameter query: The SQL query to explain
    /// - Returns: Array of plan detail strings
    public func explainQueryPlan(_ query: String) throws -> [String] {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let result = try conn.query("EXPLAIN QUERY PLAN \(query)")
        var planDetails: [String] = []
        for row in result {
            if let detail = getStringValue(row, 3) {
                planDetails.append(detail)
            }
        }
        return planDetails
    }
}

// MARK: - Data Models

/// Tracks the mailbox status of a message for bidirectional sync
public enum MailboxStatus: String, Sendable {
    case inbox = "inbox"
    case archived = "archived"
    case deleted = "deleted"
}

/// Pending sync action to be pushed to Apple Mail
public enum SyncAction: String, Sendable {
    case archive = "archive"
    case delete = "delete"
}

/// Represents a mirrored email message
public struct MailMessage: Sendable {
    public let id: String
    public let appleRowId: Int?
    public let messageId: String?
    public let mailboxId: Int?
    public let mailboxName: String?
    public let accountId: String?
    public let subject: String
    public let senderName: String?
    public let senderEmail: String?
    public let dateSent: Date?
    public let dateReceived: Date?
    public let isRead: Bool
    public let isFlagged: Bool
    public let isDeleted: Bool
    public let hasAttachments: Bool
    public let emlxPath: String?
    public let bodyText: String?
    public let bodyHtml: String?
    public let exportPath: String?
    // Mailbox status tracking for bidirectional sync (added in migration V2)
    public let mailboxStatus: MailboxStatus
    public let pendingSyncAction: SyncAction?
    public let lastKnownMailboxId: Int?
    // Threading headers (added in migration V3)
    public let inReplyTo: String?
    public let references: [String]
    // Thread ID reference (added in migration V4)
    public let threadId: String?
    // Thread position metadata (added in migration V6)
    public let threadPosition: Int?
    public let threadTotal: Int?

    public init(
        id: String,
        appleRowId: Int? = nil,
        messageId: String? = nil,
        mailboxId: Int? = nil,
        mailboxName: String? = nil,
        accountId: String? = nil,
        subject: String,
        senderName: String? = nil,
        senderEmail: String? = nil,
        dateSent: Date? = nil,
        dateReceived: Date? = nil,
        isRead: Bool = false,
        isFlagged: Bool = false,
        isDeleted: Bool = false,
        hasAttachments: Bool = false,
        emlxPath: String? = nil,
        bodyText: String? = nil,
        bodyHtml: String? = nil,
        exportPath: String? = nil,
        mailboxStatus: MailboxStatus = .inbox,
        pendingSyncAction: SyncAction? = nil,
        lastKnownMailboxId: Int? = nil,
        inReplyTo: String? = nil,
        references: [String] = [],
        threadId: String? = nil,
        threadPosition: Int? = nil,
        threadTotal: Int? = nil
    ) {
        self.id = id
        self.appleRowId = appleRowId
        self.messageId = messageId
        self.mailboxId = mailboxId
        self.mailboxName = mailboxName
        self.accountId = accountId
        self.subject = subject
        self.senderName = senderName
        self.senderEmail = senderEmail
        self.dateSent = dateSent
        self.dateReceived = dateReceived
        self.isRead = isRead
        self.isFlagged = isFlagged
        self.isDeleted = isDeleted
        self.hasAttachments = hasAttachments
        self.emlxPath = emlxPath
        self.bodyText = bodyText
        self.bodyHtml = bodyHtml
        self.exportPath = exportPath
        self.mailboxStatus = mailboxStatus
        self.pendingSyncAction = pendingSyncAction
        self.lastKnownMailboxId = lastKnownMailboxId
        self.inReplyTo = inReplyTo
        self.references = references
        self.threadId = threadId
        self.threadPosition = threadPosition
        self.threadTotal = threadTotal
    }
}

/// Represents a mailbox/folder
public struct Mailbox: Sendable {
    public let id: Int
    public let accountId: String
    public let name: String
    public let fullPath: String
    public let parentId: Int?
    public let messageCount: Int
    public let unreadCount: Int

    public init(
        id: Int,
        accountId: String,
        name: String,
        fullPath: String,
        parentId: Int? = nil,
        messageCount: Int = 0,
        unreadCount: Int = 0
    ) {
        self.id = id
        self.accountId = accountId
        self.name = name
        self.fullPath = fullPath
        self.parentId = parentId
        self.messageCount = messageCount
        self.unreadCount = unreadCount
    }
}

/// Represents an email attachment
public struct MailAttachment: Sendable {
    public let id: Int
    public let messageId: String
    public let filename: String
    public let mimeType: String?
    public let size: Int?
    public let contentId: String?
    public let isInline: Bool

    public init(
        id: Int = 0,
        messageId: String,
        filename: String,
        mimeType: String? = nil,
        size: Int? = nil,
        contentId: String? = nil,
        isInline: Bool = false
    ) {
        self.id = id
        self.messageId = messageId
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.contentId = contentId
        self.isInline = isInline
    }
}

/// Represents a conversation thread grouping related messages
public struct Thread: Sendable {
    public let id: String
    public let subject: String?
    public let participantCount: Int
    public let messageCount: Int
    public let firstDate: Date?
    public let lastDate: Date?
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        subject: String? = nil,
        participantCount: Int = 0,
        messageCount: Int = 0,
        firstDate: Date? = nil,
        lastDate: Date? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.subject = subject
        self.participantCount = participantCount
        self.messageCount = messageCount
        self.firstDate = firstDate
        self.lastDate = lastDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Protocol for thread-like types to avoid ambiguity with Foundation.Thread in CLI
public protocol ThreadLike {
    var id: String { get }
    var subject: String? { get }
    var participantCount: Int { get }
    var messageCount: Int { get }
    var firstDate: Date? { get }
    var lastDate: Date? { get }
}

extension Thread: ThreadLike {}
