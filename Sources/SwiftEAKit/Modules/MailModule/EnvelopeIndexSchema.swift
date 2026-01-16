// EnvelopeIndexSchema - Schema mapping between Apple Mail's Envelope Index and vault database
//
// Apple Mail stores email metadata in a SQLite database called "Envelope Index"
// located at ~/Library/Mail/V[x]/MailData/Envelope Index
//
// This file documents the schema and provides constants for column names used
// in bulk copy operations between the Envelope Index and our vault database.

import Foundation

// MARK: - Envelope Index Table Schemas

/// Schema definition for Apple Mail's Envelope Index `messages` table.
///
/// The messages table stores core email metadata with foreign key references
/// to the subjects, addresses, and mailboxes tables.
///
/// ## Column Mapping to MailMessage:
/// | Envelope Index Column | Type    | MailMessage Field   | Notes                                    |
/// |-----------------------|---------|---------------------|------------------------------------------|
/// | ROWID                 | INTEGER | appleRowId          | SQLite implicit rowid, primary key       |
/// | subject               | INTEGER | (via subjects.ROWID)| FK to subjects table                     |
/// | sender                | INTEGER | senderName/Email    | FK to addresses table                    |
/// | date_received         | REAL    | dateReceived        | Unix timestamp (seconds since 1970)      |
/// | date_sent             | REAL    | dateSent            | Unix timestamp (seconds since 1970)      |
/// | message_id            | TEXT    | messageId           | RFC822 Message-ID header value           |
/// | mailbox               | INTEGER | mailboxId           | FK to mailboxes table                    |
/// | read                  | INTEGER | isRead              | 0 = unread, 1 = read                     |
/// | flagged               | INTEGER | isFlagged           | 0 = unflagged, 1 = flagged               |
///
public enum EnvelopeIndexMessages {
    /// Table name in the Envelope Index database
    public static let tableName = "messages"

    // MARK: Column Names

    /// SQLite implicit row identifier (INTEGER PRIMARY KEY)
    public static let rowId = "ROWID"

    /// Foreign key to subjects table (INTEGER)
    public static let subject = "subject"

    /// Foreign key to addresses table for sender (INTEGER)
    public static let sender = "sender"

    /// Date message was received (REAL - Unix timestamp)
    public static let dateReceived = "date_received"

    /// Date message was sent (REAL - Unix timestamp)
    public static let dateSent = "date_sent"

    /// RFC822 Message-ID header (TEXT, may be NULL)
    public static let messageId = "message_id"

    /// Foreign key to mailboxes table (INTEGER)
    public static let mailbox = "mailbox"

    /// Read status: 0 = unread, 1 = read (INTEGER)
    public static let read = "read"

    /// Flagged status: 0 = unflagged, 1 = flagged (INTEGER)
    public static let flagged = "flagged"

    // MARK: Query Templates

    /// Query to fetch messages with resolved subject and sender (joins with subjects and addresses tables)
    /// Use this for bulk sync operations to get human-readable data.
    ///
    /// Result columns: ROWID, subject, sender_email, sender_name, date_received, date_sent, message_id, mailbox, read, flagged
    public static let selectWithJoinsQuery = """
        SELECT m.ROWID, s.subject, a.address AS sender_email, a.comment AS sender_name,
               m.date_received, m.date_sent, m.message_id, m.mailbox, m.read, m.flagged
        FROM messages m
        LEFT JOIN subjects s ON m.subject = s.ROWID
        LEFT JOIN addresses a ON m.sender = a.ROWID
        """

    /// Query to fetch messages from INBOX folders only (filters by mailbox URL)
    public static let selectInboxOnlyQuery = """
        SELECT m.ROWID, s.subject, a.address AS sender_email, a.comment AS sender_name,
               m.date_received, m.date_sent, m.message_id, m.mailbox, m.read, m.flagged
        FROM messages m
        LEFT JOIN subjects s ON m.subject = s.ROWID
        LEFT JOIN addresses a ON m.sender = a.ROWID
        INNER JOIN mailboxes mb ON m.mailbox = mb.ROWID
        WHERE LOWER(mb.url) LIKE '%/inbox' OR LOWER(mb.url) LIKE '%/inbox/%'
        """

    /// Query to check if messages exist by ROWID (for deletion detection)
    public static func existsQuery(rowIds: [Int]) -> String {
        let idList = rowIds.map { String($0) }.joined(separator: ",")
        return "SELECT ROWID FROM messages WHERE ROWID IN (\(idList))"
    }

    /// Query to get read/flagged status for specific messages
    public static func statusQuery(rowIds: [Int]) -> String {
        let idList = rowIds.map { String($0) }.joined(separator: ",")
        return "SELECT ROWID, read, flagged FROM messages WHERE ROWID IN (\(idList))"
    }
}

/// Schema definition for Apple Mail's Envelope Index `subjects` table.
///
/// The subjects table stores unique email subject lines, referenced by the messages table.
///
/// ## Column Mapping:
/// | Envelope Index Column | Type    | Usage                                    |
/// |-----------------------|---------|------------------------------------------|
/// | ROWID                 | INTEGER | Primary key, referenced by messages.subject |
/// | subject               | TEXT    | The actual subject line text             |
///
public enum EnvelopeIndexSubjects {
    /// Table name in the Envelope Index database
    public static let tableName = "subjects"

    // MARK: Column Names

    /// SQLite implicit row identifier (INTEGER PRIMARY KEY)
    public static let rowId = "ROWID"

    /// The subject line text (TEXT)
    public static let subject = "subject"
}

/// Schema definition for Apple Mail's Envelope Index `addresses` table.
///
/// The addresses table stores unique email addresses with optional display names,
/// referenced by the messages table for sender information.
///
/// ## Column Mapping to MailMessage:
/// | Envelope Index Column | Type    | MailMessage Field | Notes                          |
/// |-----------------------|---------|-------------------|--------------------------------|
/// | ROWID                 | INTEGER | -                 | Primary key                    |
/// | address               | TEXT    | senderEmail       | Email address (e.g., user@example.com) |
/// | comment               | TEXT    | senderName        | Display name (may be NULL)     |
///
public enum EnvelopeIndexAddresses {
    /// Table name in the Envelope Index database
    public static let tableName = "addresses"

    // MARK: Column Names

    /// SQLite implicit row identifier (INTEGER PRIMARY KEY)
    public static let rowId = "ROWID"

    /// Email address (TEXT, e.g., "user@example.com")
    public static let address = "address"

    /// Display name / comment (TEXT, may be NULL)
    public static let comment = "comment"
}

/// Schema definition for Apple Mail's Envelope Index `mailboxes` table.
///
/// The mailboxes table stores mailbox/folder information including URLs
/// that identify the mailbox type and location.
///
/// ## Column Mapping to Mailbox:
/// | Envelope Index Column | Type    | Mailbox Field | Notes                                    |
/// |-----------------------|---------|---------------|------------------------------------------|
/// | ROWID                 | INTEGER | id            | Primary key                              |
/// | url                   | TEXT    | fullPath      | Mailbox URL (e.g., mailbox://account/INBOX) |
///
public enum EnvelopeIndexMailboxes {
    /// Table name in the Envelope Index database
    public static let tableName = "mailboxes"

    // MARK: Column Names

    /// SQLite implicit row identifier (INTEGER PRIMARY KEY)
    public static let rowId = "ROWID"

    /// Mailbox URL (TEXT, identifies mailbox type and location)
    /// Format: "mailbox://account/FOLDER" or file path
    public static let url = "url"

    // MARK: Query Templates

    /// Query to fetch all mailboxes with valid URLs
    public static let selectAllQuery = """
        SELECT ROWID, url
        FROM mailboxes
        WHERE url IS NOT NULL
        """

    /// Query to get mailbox URL by ID
    public static func selectByIdQuery(id: Int) -> String {
        return "SELECT url FROM mailboxes WHERE ROWID = \(id)"
    }

    /// Query to get message's current mailbox (for move detection)
    public static func selectMessageMailboxQuery(rowIds: [Int]) -> String {
        let idList = rowIds.map { String($0) }.joined(separator: ",")
        return """
            SELECT m.ROWID, m.mailbox, mb.url
            FROM messages m
            LEFT JOIN mailboxes mb ON m.mailbox = mb.ROWID
            WHERE m.ROWID IN (\(idList))
            """
    }
}

// MARK: - Vault Database Schema (Target)

/// Schema definition for our vault database `messages` table.
///
/// This is the target schema where Envelope Index data is copied to.
/// See MailDatabase.swift migration v1 for full DDL.
public enum VaultMessages {
    /// Table name in the vault database
    public static let tableName = "messages"

    // MARK: Column Names (matching MailMessage struct)

    public static let id = "id"                          // TEXT PRIMARY KEY (stable ID)
    public static let appleRowId = "apple_rowid"         // INTEGER (Envelope Index ROWID)
    public static let messageId = "message_id"           // TEXT (RFC822 Message-ID)
    public static let mailboxId = "mailbox_id"           // INTEGER (FK to mailboxes)
    public static let mailboxName = "mailbox_name"       // TEXT
    public static let accountId = "account_id"           // TEXT
    public static let subject = "subject"                // TEXT
    public static let senderName = "sender_name"         // TEXT
    public static let senderEmail = "sender_email"       // TEXT
    public static let dateSent = "date_sent"             // INTEGER (Unix timestamp)
    public static let dateReceived = "date_received"     // INTEGER (Unix timestamp)
    public static let isRead = "is_read"                 // INTEGER (0/1)
    public static let isFlagged = "is_flagged"           // INTEGER (0/1)
    public static let isDeleted = "is_deleted"           // INTEGER (0/1)
    public static let hasAttachments = "has_attachments" // INTEGER (0/1)
    public static let emlxPath = "emlx_path"             // TEXT
    public static let bodyText = "body_text"             // TEXT
    public static let bodyHtml = "body_html"             // TEXT
    public static let exportPath = "export_path"         // TEXT
    public static let syncedAt = "synced_at"             // INTEGER (Unix timestamp)
    public static let updatedAt = "updated_at"           // INTEGER (Unix timestamp)

    // Added in migration v2 (bidirectional sync)
    public static let mailboxStatus = "mailbox_status"          // TEXT (inbox/archived/deleted)
    public static let pendingSyncAction = "pending_sync_action" // TEXT (nullable)
    public static let lastKnownMailboxId = "last_known_mailbox_id" // INTEGER (nullable)

    // Added in migration v3 (threading)
    public static let inReplyTo = "in_reply_to"                 // TEXT (nullable)
    public static let threadingReferences = "threading_references" // TEXT (JSON array)

    // Added in migration v4 (threads)
    public static let threadId = "thread_id"                    // TEXT (FK to threads)

    // Added in migration v6 (thread position)
    public static let threadPosition = "thread_position"        // INTEGER (nullable)
    public static let threadTotal = "thread_total"              // INTEGER (nullable)
}

/// Schema definition for our vault database `mailboxes` table.
public enum VaultMailboxes {
    /// Table name in the vault database
    public static let tableName = "mailboxes"

    // MARK: Column Names (matching Mailbox struct)

    public static let id = "id"                   // INTEGER PRIMARY KEY
    public static let accountId = "account_id"   // TEXT NOT NULL
    public static let name = "name"              // TEXT NOT NULL
    public static let fullPath = "full_path"     // TEXT NOT NULL
    public static let parentId = "parent_id"     // INTEGER (nullable)
    public static let messageCount = "message_count" // INTEGER DEFAULT 0
    public static let unreadCount = "unread_count"   // INTEGER DEFAULT 0
    public static let syncedAt = "synced_at"     // INTEGER NOT NULL
}

/// Schema definition for our vault database `addresses` table.
///
/// This table stores unique email addresses copied from Envelope Index
/// for use in sender lookups and contact deduplication.
///
/// ## Column Mapping from Envelope Index:
/// | Envelope Index Column | Vault Column | Notes                                |
/// |-----------------------|--------------|--------------------------------------|
/// | ROWID                 | id           | Primary key (preserved from source)  |
/// | address               | email        | Email address                        |
/// | comment               | name         | Display name (may be NULL)           |
///
public enum VaultAddresses {
    /// Table name in the vault database
    public static let tableName = "addresses"

    // MARK: Column Names

    /// Primary key (matches Envelope Index ROWID for foreign key compatibility)
    public static let id = "id"

    /// Email address (TEXT, e.g., "user@example.com")
    public static let email = "email"

    /// Display name (TEXT, may be NULL)
    public static let name = "name"

    /// Timestamp when this address was synced (INTEGER - Unix timestamp)
    public static let syncedAt = "synced_at"
}

// MARK: - Schema Mapping Utilities

/// Utilities for mapping between Envelope Index and vault database schemas.
public enum EnvelopeIndexSchemaMapping {

    /// Convert Envelope Index date (Unix timestamp as REAL/Double) to vault format (INTEGER)
    /// - Parameter envelopeDate: The date value from Envelope Index (seconds since 1970)
    /// - Returns: Integer timestamp for vault storage
    public static func convertDate(_ envelopeDate: Double?) -> Int? {
        guard let date = envelopeDate else { return nil }
        return Int(date)
    }

    /// Convert Envelope Index boolean (0/1 INTEGER) to Swift Bool
    /// - Parameter value: The integer value from Envelope Index
    /// - Returns: true if value is 1, false otherwise
    public static func convertBool(_ value: Int64?) -> Bool {
        return (value ?? 0) == 1
    }

    /// Convert Envelope Index boolean (0/1 INTEGER) to vault format (0/1 INTEGER)
    /// - Parameter value: The boolean value
    /// - Returns: 1 if true, 0 if false
    public static func convertBoolToInt(_ value: Bool) -> Int {
        return value ? 1 : 0
    }

    /// Extract mailbox name from URL
    /// - Parameter url: The mailbox URL from Envelope Index (e.g., "mailbox://account/INBOX")
    /// - Returns: The extracted mailbox name (e.g., "INBOX")
    public static func extractMailboxName(from url: String?) -> String? {
        guard let url = url else { return nil }
        return url.components(separatedBy: "/").last
    }

    /// Reconstruct sender string from email and name components
    /// - Parameters:
    ///   - email: The email address
    ///   - name: The display name (optional)
    /// - Returns: Formatted sender string like "Name" <email@example.com>
    public static func formatSender(email: String?, name: String?) -> String? {
        guard let email = email else { return nil }
        if let name = name, !name.isEmpty {
            return "\"\(name)\" <\(email)>"
        }
        return email
    }

    /// Parse a formatted sender string into email and name components
    /// - Parameter sender: Formatted sender string
    /// - Returns: Tuple of (name, email)
    public static func parseSender(_ sender: String?) -> (name: String?, email: String?) {
        guard let sender = sender else { return (nil, nil) }
        let trimmed = sender.trimmingCharacters(in: .whitespaces)

        if let startAngle = trimmed.lastIndex(of: "<"),
           let endAngle = trimmed.lastIndex(of: ">"),
           startAngle < endAngle {
            let email = String(trimmed[trimmed.index(after: startAngle)..<endAngle])
                .trimmingCharacters(in: .whitespaces)
            let name = String(trimmed[..<startAngle])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            return (name: name.isEmpty ? nil : name, email: email)
        }

        if trimmed.contains("@") {
            return (name: nil, email: trimmed)
        }

        return (name: trimmed, email: nil)
    }
}
