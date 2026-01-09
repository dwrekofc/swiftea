// MailSync - Synchronize Apple Mail data to libSQL mirror

import Foundation
import SQLite3

/// Errors that can occur during mail sync
public enum MailSyncError: Error, LocalizedError {
    case sourceConnectionFailed(underlying: Error)
    case sourceDatabaseLocked
    case queryFailed(query: String, underlying: Error)
    case emlxParseFailed(path: String, underlying: Error)
    case syncFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .sourceConnectionFailed(let error):
            return "Failed to connect to Apple Mail database: \(error.localizedDescription)"
        case .sourceDatabaseLocked:
            return "Apple Mail database is locked. Please close Mail and try again."
        case .queryFailed(let query, let error):
            return "Query failed: \(query)\nError: \(error.localizedDescription)"
        case .emlxParseFailed(let path, let error):
            return "Failed to parse .emlx file at \(path): \(error.localizedDescription)"
        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"
        }
    }
}

/// Progress update during sync
public struct SyncProgress: Sendable {
    public let phase: SyncPhase
    public let current: Int
    public let total: Int
    public let message: String

    public init(phase: SyncPhase, current: Int, total: Int, message: String) {
        self.phase = phase
        self.current = current
        self.total = total
        self.message = message
    }

    public var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total) * 100
    }
}

/// Phases of the sync process
public enum SyncPhase: String, Sendable {
    case discovering = "Discovering"
    case syncingMailboxes = "Syncing mailboxes"
    case syncingMessages = "Syncing messages"
    case parsingContent = "Parsing content"
    case detectingChanges = "Detecting changes"
    case detectingDeletions = "Detecting deletions"
    case indexing = "Indexing"
    case complete = "Complete"
}

/// Result of a sync operation
public struct SyncResult: Sendable {
    public let messagesProcessed: Int
    public let messagesAdded: Int
    public let messagesUpdated: Int
    public let messagesDeleted: Int
    public let messagesUnchanged: Int
    public let mailboxesProcessed: Int
    public let errors: [String]
    public let duration: TimeInterval
    public let isIncremental: Bool

    public init(messagesProcessed: Int, messagesAdded: Int, messagesUpdated: Int,
                messagesDeleted: Int = 0, messagesUnchanged: Int = 0,
                mailboxesProcessed: Int, errors: [String], duration: TimeInterval,
                isIncremental: Bool = false) {
        self.messagesProcessed = messagesProcessed
        self.messagesAdded = messagesAdded
        self.messagesUpdated = messagesUpdated
        self.messagesDeleted = messagesDeleted
        self.messagesUnchanged = messagesUnchanged
        self.mailboxesProcessed = mailboxesProcessed
        self.errors = errors
        self.duration = duration
        self.isIncremental = isIncremental
    }
}

/// Synchronizes Apple Mail data to the libSQL mirror database
public final class MailSync: @unchecked Sendable {
    private let mailDatabase: MailDatabase
    private let discovery: EnvelopeIndexDiscovery
    private let emlxParser: EmlxParser
    private let idGenerator: StableIdGenerator

    private var sourceDb: OpaquePointer?
    private var envelopeInfo: EnvelopeIndexInfo?

    /// Progress callback
    public var onProgress: ((SyncProgress) -> Void)?

    public init(
        mailDatabase: MailDatabase,
        discovery: EnvelopeIndexDiscovery = EnvelopeIndexDiscovery(),
        emlxParser: EmlxParser = EmlxParser(),
        idGenerator: StableIdGenerator = StableIdGenerator()
    ) {
        self.mailDatabase = mailDatabase
        self.discovery = discovery
        self.emlxParser = emlxParser
        self.idGenerator = idGenerator
    }

    /// Run a sync from Apple Mail to the mirror database
    /// - Parameter incremental: If true, only sync changes since last sync (faster). If false, full rebuild.
    public func sync(incremental: Bool = false) throws -> SyncResult {
        let startTime = Date()
        var errors: [String] = []
        var messagesProcessed = 0
        var messagesAdded = 0
        var messagesUpdated = 0
        var messagesDeleted = 0
        var messagesUnchanged = 0
        var mailboxesProcessed = 0

        // Discover envelope index
        reportProgress(.discovering, 0, 1, "Discovering Apple Mail database...")
        let info = try discovery.discover()
        envelopeInfo = info

        // Connect to source database (read-only)
        try connectToSource(path: info.envelopeIndexPath)
        defer { disconnectSource() }

        // Get last sync time for incremental
        var lastSyncTime: Date? = nil
        if incremental {
            lastSyncTime = try mailDatabase.getLastSyncTime()
        }

        // Sync mailboxes first
        reportProgress(.syncingMailboxes, 0, 1, "Syncing mailboxes...")
        let mailboxCount = try syncMailboxes()
        mailboxesProcessed = mailboxCount

        if incremental && lastSyncTime != nil {
            // Incremental sync: new messages + status changes + deletions
            let result = try performIncrementalSync(
                info: info,
                lastSyncTime: lastSyncTime!,
                errors: &errors
            )
            messagesProcessed = result.processed
            messagesAdded = result.added
            messagesUpdated = result.updated
            messagesDeleted = result.deleted
            messagesUnchanged = result.unchanged
        } else {
            // Full sync: process all messages
            reportProgress(.syncingMessages, 0, 1, "Querying messages...")
            let messages = try queryMessages(since: nil)
            let totalMessages = messages.count

            reportProgress(.syncingMessages, 0, totalMessages, "Syncing \(totalMessages) messages...")

            let batchSize = 100
            for (index, messageRow) in messages.enumerated() {
                do {
                    let (added, updated) = try processMessage(messageRow, mailBasePath: info.mailBasePath)
                    if added { messagesAdded += 1 }
                    if updated { messagesUpdated += 1 }
                    messagesProcessed += 1

                    if index % batchSize == 0 || index == totalMessages - 1 {
                        reportProgress(.syncingMessages, index + 1, totalMessages,
                                       "Processed \(index + 1)/\(totalMessages) messages")
                    }
                } catch {
                    errors.append("Message \(messageRow.rowId): \(error.localizedDescription)")
                }
            }
        }

        // Update last sync time
        try mailDatabase.setLastSyncTime(Date())

        reportProgress(.complete, messagesProcessed, messagesProcessed, "Sync complete")

        return SyncResult(
            messagesProcessed: messagesProcessed,
            messagesAdded: messagesAdded,
            messagesUpdated: messagesUpdated,
            messagesDeleted: messagesDeleted,
            messagesUnchanged: messagesUnchanged,
            mailboxesProcessed: mailboxesProcessed,
            errors: errors,
            duration: Date().timeIntervalSince(startTime),
            isIncremental: incremental
        )
    }

    // MARK: - Incremental Sync

    private struct IncrementalSyncResult {
        var processed: Int = 0
        var added: Int = 0
        var updated: Int = 0
        var deleted: Int = 0
        var unchanged: Int = 0
    }

    private func performIncrementalSync(
        info: EnvelopeIndexInfo,
        lastSyncTime: Date,
        errors: inout [String]
    ) throws -> IncrementalSyncResult {
        var result = IncrementalSyncResult()

        // Phase 1: Query new messages (received since last sync)
        reportProgress(.syncingMessages, 0, 1, "Querying new messages...")
        let newMessages = try queryMessages(since: lastSyncTime)

        if !newMessages.isEmpty {
            reportProgress(.syncingMessages, 0, newMessages.count, "Syncing \(newMessages.count) new messages...")

            let batchSize = 100
            for (index, messageRow) in newMessages.enumerated() {
                do {
                    let (added, updated) = try processMessage(messageRow, mailBasePath: info.mailBasePath)
                    if added { result.added += 1 }
                    if updated { result.updated += 1 }
                    result.processed += 1

                    if index % batchSize == 0 || index == newMessages.count - 1 {
                        reportProgress(.syncingMessages, index + 1, newMessages.count,
                                       "Processed \(index + 1)/\(newMessages.count) new messages")
                    }
                } catch {
                    errors.append("Message \(messageRow.rowId): \(error.localizedDescription)")
                }
            }
        }

        // Phase 2: Check for status changes on existing messages (read/flagged)
        reportProgress(.detectingChanges, 0, 1, "Detecting status changes...")
        let statusChanges = try detectStatusChanges()
        if statusChanges > 0 {
            result.updated += statusChanges
            result.processed += statusChanges
        }

        // Phase 3: Detect deleted messages
        reportProgress(.detectingDeletions, 0, 1, "Detecting deleted messages...")
        let deletions = try detectDeletedMessages()
        result.deleted = deletions
        result.processed += deletions

        return result
    }

    /// Detect messages in the mirror that have changed status (read/flagged) in Apple Mail
    private func detectStatusChanges() throws -> Int {
        // Get existing messages from mirror with their current status
        let existingMessages = try mailDatabase.getAllMessageStatuses()
        var changesDetected = 0

        // Query current status from Apple Mail for these messages
        let rowIds = existingMessages.map { $0.appleRowId }
        guard !rowIds.isEmpty else { return 0 }

        // Batch query status from source
        let batchSize = 500
        for batch in stride(from: 0, to: rowIds.count, by: batchSize) {
            let end = min(batch + batchSize, rowIds.count)
            let batchIds = Array(rowIds[batch..<end])

            let idList = batchIds.map { String($0) }.joined(separator: ",")
            let sql = """
                SELECT ROWID, read, flagged
                FROM messages
                WHERE ROWID IN (\(idList))
                """

            let rows = try executeQuery(sql)

            for row in rows {
                guard let rowId = row["ROWID"] as? Int64 else { continue }

                let isRead = (row["read"] as? Int64 ?? 0) == 1
                let isFlagged = (row["flagged"] as? Int64 ?? 0) == 1

                // Find the existing message status
                if let existing = existingMessages.first(where: { $0.appleRowId == Int(rowId) }) {
                    if existing.isRead != isRead || existing.isFlagged != isFlagged {
                        // Status changed, update it
                        try mailDatabase.updateMessageStatus(
                            id: existing.id,
                            isRead: isRead,
                            isFlagged: isFlagged
                        )
                        changesDetected += 1
                    }
                }
            }
        }

        return changesDetected
    }

    /// Detect messages that exist in the mirror but have been deleted from Apple Mail
    private func detectDeletedMessages() throws -> Int {
        // Get all Apple rowids from the mirror
        let mirrorRowIds = try mailDatabase.getAllAppleRowIds()
        guard !mirrorRowIds.isEmpty else { return 0 }

        // Query which of these still exist in Apple Mail
        let batchSize = 500
        var deletedCount = 0
        var existingInSource = Set<Int>()

        for batch in stride(from: 0, to: mirrorRowIds.count, by: batchSize) {
            let end = min(batch + batchSize, mirrorRowIds.count)
            let batchIds = Array(mirrorRowIds[batch..<end])

            let idList = batchIds.map { String($0) }.joined(separator: ",")
            let sql = "SELECT ROWID FROM messages WHERE ROWID IN (\(idList))"

            let rows = try executeQuery(sql)
            for row in rows {
                if let rowId = row["ROWID"] as? Int64 {
                    existingInSource.insert(Int(rowId))
                }
            }
        }

        // Mark messages as deleted if they're not in source
        for rowId in mirrorRowIds {
            if !existingInSource.contains(rowId) {
                try mailDatabase.markMessageDeleted(appleRowId: rowId)
                deletedCount += 1
            }
        }

        return deletedCount
    }

    // MARK: - Source Database Operations

    private func connectToSource(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX

        let result = sqlite3_open_v2(path, &db, flags, nil)

        if result == SQLITE_BUSY {
            throw MailSyncError.sourceDatabaseLocked
        }

        guard result == SQLITE_OK else {
            let error = NSError(domain: "SQLite", code: Int(result), userInfo: [
                NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
            ])
            throw MailSyncError.sourceConnectionFailed(underlying: error)
        }

        sourceDb = db
    }

    private func disconnectSource() {
        if let db = sourceDb {
            sqlite3_close(db)
            sourceDb = nil
        }
    }

    private func executeQuery(_ sql: String) throws -> [[String: Any]] {
        guard let db = sourceDb else {
            throw MailSyncError.sourceConnectionFailed(underlying:
                NSError(domain: "MailSync", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Not connected to source database"
                ])
            )
        }

        var statement: OpaquePointer?
        var results: [[String: Any]] = []

        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            let error = NSError(domain: "SQLite", code: Int(prepareResult), userInfo: [
                NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
            ])
            throw MailSyncError.queryFailed(query: sql, underlying: error)
        }

        defer { sqlite3_finalize(statement) }

        let columnCount = sqlite3_column_count(statement)

        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any] = [:]

            for i in 0..<columnCount {
                let columnName = String(cString: sqlite3_column_name(statement, i))
                let columnType = sqlite3_column_type(statement, i)

                switch columnType {
                case SQLITE_INTEGER:
                    row[columnName] = sqlite3_column_int64(statement, i)
                case SQLITE_FLOAT:
                    row[columnName] = sqlite3_column_double(statement, i)
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, i) {
                        row[columnName] = String(cString: text)
                    }
                case SQLITE_BLOB:
                    let length = sqlite3_column_bytes(statement, i)
                    if let blob = sqlite3_column_blob(statement, i) {
                        row[columnName] = Data(bytes: blob, count: Int(length))
                    }
                case SQLITE_NULL:
                    row[columnName] = NSNull()
                default:
                    break
                }
            }

            results.append(row)
        }

        return results
    }

    // MARK: - Mailbox Sync

    private func syncMailboxes() throws -> Int {
        // Query mailboxes from Apple Mail database
        // Only select ROWID and url which are guaranteed to exist across Mail versions
        let sql = """
            SELECT ROWID, url
            FROM mailboxes
            WHERE url IS NOT NULL
            """

        let rows = try executeQuery(sql)
        var count = 0

        for row in rows {
            guard let rowId = row["ROWID"] as? Int64,
                  let url = row["url"] as? String else {
                continue
            }

            // Extract mailbox name from URL
            let name = extractMailboxName(from: url)
            let fullPath = url

            let mailbox = Mailbox(
                id: Int(rowId),
                accountId: "",
                name: name,
                fullPath: fullPath,
                parentId: nil,
                messageCount: 0,
                unreadCount: 0
            )

            try mailDatabase.upsertMailbox(mailbox)
            count += 1
        }

        return count
    }

    private func extractMailboxName(from url: String) -> String {
        // URL format is typically like: mailbox://account/INBOX or file path
        if let lastComponent = url.components(separatedBy: "/").last {
            return lastComponent
        }
        return url
    }

    // MARK: - Message Sync

    /// Raw message data from Apple Mail database
    private struct MessageRow {
        let rowId: Int64
        let subject: String?
        let sender: String?
        let dateReceived: Double?
        let dateSent: Double?
        let messageId: String?
        let mailboxId: Int64?
        let isRead: Bool
        let isFlagged: Bool
        let hasAttachments: Bool
    }

    private func queryMessages(since: Date?) throws -> [MessageRow] {
        // Query message columns with JOINs to resolve subject/sender foreign keys
        // The messages.subject and messages.sender columns are FK integers, not text
        // Attachment detection is done during .emlx parsing instead
        var sql = """
            SELECT m.ROWID, s.subject, a.address AS sender_email, a.comment AS sender_name,
                   m.date_received, m.date_sent, m.message_id, m.mailbox, m.read, m.flagged
            FROM messages m
            LEFT JOIN subjects s ON m.subject = s.ROWID
            LEFT JOIN addresses a ON m.sender = a.ROWID
            """

        if let sinceDate = since {
            let timestamp = sinceDate.timeIntervalSince1970
            sql += " WHERE m.date_received > \(timestamp)"
        }

        sql += " ORDER BY m.date_received DESC"

        let rows = try executeQuery(sql)

        return rows.compactMap { row -> MessageRow? in
            guard let rowId = row["ROWID"] as? Int64 else { return nil }

            // Reconstruct sender string from email/name for downstream parsing
            let senderEmail = row["sender_email"] as? String
            let senderName = row["sender_name"] as? String
            var sender: String? = nil
            if let email = senderEmail {
                if let name = senderName, !name.isEmpty {
                    sender = "\"\(name)\" <\(email)>"
                } else {
                    sender = email
                }
            }

            // Dates are stored as Int64 in SQLite, convert to Double for TimeInterval
            let dateReceived: Double? = (row["date_received"] as? Int64).map { Double($0) }
                ?? (row["date_received"] as? Double)
            let dateSent: Double? = (row["date_sent"] as? Int64).map { Double($0) }
                ?? (row["date_sent"] as? Double)

            return MessageRow(
                rowId: rowId,
                subject: row["subject"] as? String,
                sender: sender,
                dateReceived: dateReceived,
                dateSent: dateSent,
                messageId: row["message_id"] as? String,
                mailboxId: row["mailbox"] as? Int64,
                isRead: (row["read"] as? Int64 ?? 0) == 1,
                isFlagged: (row["flagged"] as? Int64 ?? 0) == 1,
                hasAttachments: false  // Detected during .emlx parsing
            )
        }
    }

    private func processMessage(_ row: MessageRow, mailBasePath: String) throws -> (added: Bool, updated: Bool) {
        // Generate stable ID
        let stableId = idGenerator.generateId(
            messageId: row.messageId,
            subject: row.subject,
            sender: row.sender,
            date: row.dateReceived.map { Date(timeIntervalSince1970: $0) },
            appleRowId: Int(row.rowId)
        )

        // Check if message already exists
        let existing = try mailDatabase.getMessage(id: stableId)

        // Parse sender
        var senderName: String? = nil
        var senderEmail: String? = nil
        if let sender = row.sender {
            let parsed = parseSenderString(sender)
            senderName = parsed.name
            senderEmail = parsed.email
        }

        // Get mailbox info
        var mailboxName: String? = nil
        if let mailboxId = row.mailboxId {
            let mailboxSql = "SELECT url FROM mailboxes WHERE ROWID = \(mailboxId)"
            if let mailboxRows = try? executeQuery(mailboxSql),
               let first = mailboxRows.first,
               let url = first["url"] as? String {
                mailboxName = extractMailboxName(from: url)
            }
        }

        // Try to get body content from .emlx file
        var bodyText: String? = nil
        var bodyHtml: String? = nil
        var emlxPath: String? = nil

        if let mailboxId = row.mailboxId {
            // Find mailbox path
            let mailboxPathSql = "SELECT url FROM mailboxes WHERE ROWID = \(mailboxId)"
            if let mailboxRows = try? executeQuery(mailboxPathSql),
               let first = mailboxRows.first,
               let url = first["url"] as? String {
                // Convert mailbox URL to file path
                let mailboxPath = convertMailboxUrlToPath(url, mailBasePath: mailBasePath)
                emlxPath = discovery.emlxPath(forMessageId: Int(row.rowId), mailboxPath: mailboxPath, mailBasePath: mailBasePath)

                // Try to parse .emlx
                if let path = emlxPath {
                    do {
                        let parsed = try emlxParser.parse(path: path)
                        bodyText = parsed.bodyText
                        bodyHtml = parsed.bodyHtml
                    } catch {
                        // Log but don't fail - body content is optional
                    }
                }
            }
        }

        let message = MailMessage(
            id: stableId,
            appleRowId: Int(row.rowId),
            messageId: row.messageId,
            mailboxId: row.mailboxId.map { Int($0) },
            mailboxName: mailboxName,
            accountId: nil, // Could be extracted from mailbox
            subject: row.subject ?? "(No Subject)",
            senderName: senderName,
            senderEmail: senderEmail,
            dateSent: row.dateSent.map { Date(timeIntervalSince1970: $0) },
            dateReceived: row.dateReceived.map { Date(timeIntervalSince1970: $0) },
            isRead: row.isRead,
            isFlagged: row.isFlagged,
            isDeleted: false,
            hasAttachments: row.hasAttachments,
            emlxPath: emlxPath,
            bodyText: bodyText,
            bodyHtml: bodyHtml
        )

        try mailDatabase.upsertMessage(message)

        return (added: existing == nil, updated: existing != nil)
    }

    private func parseSenderString(_ sender: String) -> (name: String?, email: String?) {
        // Format: "Name" <email@example.com> or Name <email@example.com> or email@example.com
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

        return (name: nil, email: nil)
    }

    private func convertMailboxUrlToPath(_ url: String, mailBasePath: String) -> String {
        // URLs can be file:// URLs or internal references
        if url.hasPrefix("file://") {
            return url.replacingOccurrences(of: "file://", with: "")
        }

        // Try to construct path from mailbox URL
        // This is simplified - actual implementation needs to handle various URL formats
        return (mailBasePath as NSString).appendingPathComponent(url)
    }

    // MARK: - Progress Reporting

    private func reportProgress(_ phase: SyncPhase, _ current: Int, _ total: Int, _ message: String) {
        let progress = SyncProgress(phase: phase, current: current, total: total, message: message)
        onProgress?(progress)
    }
}
