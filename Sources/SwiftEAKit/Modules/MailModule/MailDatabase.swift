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

    // MARK: - Message Operations

    /// Insert or update a message in the mirror database
    public func upsertMessage(_ message: MailMessage) throws {
        guard let conn = connection else {
            throw MailDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)

        _ = try conn.execute("""
            INSERT INTO messages (
                id, apple_rowid, message_id, mailbox_id, mailbox_name, account_id,
                subject, sender_name, sender_email, date_sent, date_received,
                is_read, is_flagged, is_deleted, has_attachments, emlx_path,
                body_text, body_html, synced_at, updated_at
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
                \(now), \(now)
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
                updated_at = \(now)
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

    // MARK: - Sync Status Operations

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
        try setSyncStatus(key: "last_sync_time", value: String(date.timeIntervalSince1970))
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

    // MARK: - Helpers

    private func escapeSql(_ string: String) -> String {
        string.replacingOccurrences(of: "'", with: "''")
    }

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
        MailMessage(
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
            exportPath: getStringValue(row, 18)
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
}

// MARK: - Data Models

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
        exportPath: String? = nil
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
