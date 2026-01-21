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
    case threadingMessages = "Threading messages"
    case detectingChanges = "Detecting changes"
    case detectingDeletions = "Detecting deletions"
    case indexing = "Indexing"
    case complete = "Complete"
}

/// Types of mailboxes in Apple Mail
public enum MailboxType: String, Sendable {
    case inbox
    case archive
    case trash
    case sent
    case drafts
    case junk
    case other
}

/// Classify a mailbox based on its URL and name
/// - Parameters:
///   - url: The mailbox URL (e.g., "mailbox://account/INBOX" or file path)
///   - name: The mailbox name (fallback if URL doesn't contain useful info)
/// - Returns: The classified mailbox type
public func classifyMailbox(url: String?, name: String?) -> MailboxType {
    // Extract the mailbox identifier from URL or use name
    let identifier: String
    if let url = url {
        // Extract last path component from URL
        if let lastComponent = url.components(separatedBy: "/").last, !lastComponent.isEmpty {
            identifier = lastComponent
        } else if let name = name {
            identifier = name
        } else {
            return .other
        }
    } else if let name = name {
        identifier = name
    } else {
        return .other
    }

    let lowercased = identifier.lowercased()

    // Check for INBOX (case-insensitive)
    if lowercased == "inbox" {
        return .inbox
    }

    // Check for Archive (various names used by different providers)
    if lowercased == "archive" || lowercased == "all mail" || lowercased == "all" || lowercased.contains("archive") {
        return .archive
    }

    // Check for Trash/Deleted
    if lowercased == "trash" || lowercased == "deleted" || lowercased == "deleted messages" || lowercased.contains("trash") {
        return .trash
    }

    // Check for Sent
    if lowercased == "sent" || lowercased == "sent messages" || lowercased == "sent mail" || lowercased.contains("sent") {
        return .sent
    }

    // Check for Drafts
    if lowercased == "drafts" || lowercased == "draft" || lowercased.contains("draft") {
        return .drafts
    }

    // Check for Junk/Spam
    if lowercased == "junk" || lowercased == "spam" || lowercased == "junk e-mail" || lowercased.contains("junk") || lowercased.contains("spam") {
        return .junk
    }

    return .other
}

/// Result of a sync operation
public struct SyncResult: Sendable {
    public let messagesProcessed: Int
    public let messagesAdded: Int
    public let messagesUpdated: Int
    public let messagesDeleted: Int
    public let messagesUnchanged: Int
    public let mailboxesProcessed: Int
    public let threadsCreated: Int
    public let threadsUpdated: Int
    public let errors: [String]
    public let duration: TimeInterval
    public let isIncremental: Bool

    public init(messagesProcessed: Int, messagesAdded: Int, messagesUpdated: Int,
                messagesDeleted: Int = 0, messagesUnchanged: Int = 0,
                mailboxesProcessed: Int, threadsCreated: Int = 0, threadsUpdated: Int = 0,
                errors: [String], duration: TimeInterval,
                isIncremental: Bool = false) {
        self.messagesProcessed = messagesProcessed
        self.messagesAdded = messagesAdded
        self.messagesUpdated = messagesUpdated
        self.messagesDeleted = messagesDeleted
        self.messagesUnchanged = messagesUnchanged
        self.mailboxesProcessed = mailboxesProcessed
        self.threadsCreated = threadsCreated
        self.threadsUpdated = threadsUpdated
        self.errors = errors
        self.duration = duration
        self.isIncremental = isIncremental
    }
}

/// Synchronizes Apple Mail data to the libSQL mirror database
/// Cached mailbox metadata to avoid redundant queries
private struct MailboxInfo {
    let id: Int
    let name: String?
    let url: String
    let path: String?
}

public final class MailSync: @unchecked Sendable {
    private let mailDatabase: MailDatabase
    private let discovery: EnvelopeIndexDiscovery
    private let emlxParser: EmlxParser
    private let idGenerator: StableIdGenerator
    private let threadDetectionService: ThreadDetectionService

    private var sourceDb: OpaquePointer?
    private var envelopeInfo: EnvelopeIndexInfo?

    /// Cache of mailbox metadata to eliminate redundant queries
    private var mailboxCache: [Int: MailboxInfo] = [:]
    private var mailboxCacheHits: Int = 0
    private var mailboxCacheMisses: Int = 0

    /// Sync options (including parallel workers)
    public var options: MailSyncOptions

    /// Progress callback
    public var onProgress: ((SyncProgress) -> Void)?

    public init(
        mailDatabase: MailDatabase,
        discovery: EnvelopeIndexDiscovery = EnvelopeIndexDiscovery(),
        emlxParser: EmlxParser = EmlxParser(),
        idGenerator: StableIdGenerator = StableIdGenerator(),
        threadDetectionService: ThreadDetectionService = ThreadDetectionService(),
        options: MailSyncOptions = .default
    ) {
        self.mailDatabase = mailDatabase
        self.discovery = discovery
        self.emlxParser = emlxParser
        self.idGenerator = idGenerator
        self.threadDetectionService = threadDetectionService
        self.options = options
    }

    /// Run a sync from Apple Mail to the mirror database
    /// - Parameter forceFullSync: If true, force a full sync even if previous sync exists. If false, auto-detect:
    ///   - If last_sync_time exists in database, do incremental sync (only changes since last sync)
    ///   - If no previous sync exists, do full sync
    public func sync(forceFullSync: Bool = false) throws -> SyncResult {
        let startTime = Date()
        var errors: [String] = []
        var messagesProcessed = 0
        var messagesAdded = 0
        var messagesUpdated = 0
        var messagesDeleted = 0
        var messagesUnchanged = 0
        var mailboxesProcessed = 0
        var threadsCreated = 0
        var threadsUpdated = 0

        // Auto-detect incremental mode: use incremental if we have a previous sync and not forcing full
        let lastSyncTime = try mailDatabase.getLastSyncTime()
        let useIncremental = !forceFullSync && lastSyncTime != nil

        // Record sync start
        try mailDatabase.recordSyncStart(isIncremental: useIncremental)

        do {
            return try performSync(
                useIncremental: useIncremental,
                lastSyncTime: lastSyncTime,
                startTime: startTime,
                errors: &errors,
                messagesProcessed: &messagesProcessed,
                messagesAdded: &messagesAdded,
                messagesUpdated: &messagesUpdated,
                messagesDeleted: &messagesDeleted,
                messagesUnchanged: &messagesUnchanged,
                mailboxesProcessed: &mailboxesProcessed,
                threadsCreated: &threadsCreated,
                threadsUpdated: &threadsUpdated
            )
        } catch {
            // Record sync failure
            try? mailDatabase.recordSyncFailure(error: error)
            throw error
        }
    }

    /// Internal sync implementation
    private func performSync(
        useIncremental: Bool,
        lastSyncTime: Date?,
        startTime: Date,
        errors: inout [String],
        messagesProcessed: inout Int,
        messagesAdded: inout Int,
        messagesUpdated: inout Int,
        messagesDeleted: inout Int,
        messagesUnchanged: inout Int,
        mailboxesProcessed: inout Int,
        threadsCreated: inout Int,
        threadsUpdated: inout Int
    ) throws -> SyncResult {
        // Discover envelope index
        reportProgress(.discovering, 0, 1, "Discovering Apple Mail database...")
        let info = try discovery.discover()
        envelopeInfo = info

        // Connect to source database (read-only)
        try connectToSource(path: info.envelopeIndexPath)
        defer { disconnectSource() }

        // Sync mailboxes first
        reportProgress(.syncingMailboxes, 0, 1, "Syncing mailboxes...")
        let mailboxCount = try syncMailboxes()
        mailboxesProcessed = mailboxCount

        // Populate mailbox cache to eliminate redundant queries during message processing
        try populateMailboxCache(mailBasePath: info.mailBasePath)

        if useIncremental, let syncTime = lastSyncTime {
            // Incremental sync: new messages + status changes + deletions
            let result = try performIncrementalSync(
                info: info,
                lastSyncTime: syncTime,
                errors: &errors
            )
            messagesProcessed = result.processed
            messagesAdded = result.added
            messagesUpdated = result.updated
            messagesDeleted = result.deleted
            messagesUnchanged = result.unchanged
            threadsCreated = result.threadsCreated
            threadsUpdated = result.threadsUpdated
        } else {
            // Full sync: process all messages with batched database transactions
            reportProgress(.syncingMessages, 0, 1, "Querying messages...")
            let messageRows = try queryMessages(since: nil)
            let totalMessages = messageRows.count

            reportProgress(.syncingMessages, 0, totalMessages, "Syncing \(totalMessages) messages...")

            // Phase 1: Process all messages into MailMessage objects
            var processedMessages: [MailMessage] = []
            processedMessages.reserveCapacity(totalMessages)

            let progressBatchSize = 100
            for (index, messageRow) in messageRows.enumerated() {
                do {
                    let message = try processMessageToObject(messageRow, mailBasePath: info.mailBasePath)
                    processedMessages.append(message)

                    if index % progressBatchSize == 0 || index == totalMessages - 1 {
                        reportProgress(.syncingMessages, index + 1, totalMessages,
                                       "Processed \(index + 1)/\(totalMessages) messages")
                    }
                } catch {
                    errors.append("Message \(messageRow.rowId): \(error.localizedDescription)")
                }
            }

            // Phase 2: Batch insert all processed messages
            // Note: FTS triggers are disabled during batch insert and index is rebuilt after
            // This prevents the O(n^2) slowdown from per-row FTS updates on second sync
            reportProgress(.syncingMessages, totalMessages, totalMessages, "Writing \(processedMessages.count) messages to database...")

            let batchConfig = MailDatabase.BatchInsertConfig(batchSize: options.databaseBatchSize)
            let batchResult = try mailDatabase.batchUpsertMessages(processedMessages, config: batchConfig)

            messagesAdded = batchResult.inserted
            messagesUpdated = batchResult.updated
            messagesProcessed = batchResult.inserted + batchResult.updated
            errors.append(contentsOf: batchResult.errors)

            // Report indexing phase (FTS rebuild happens in batchUpsertMessages defer block)
            reportProgress(.indexing, messagesProcessed, messagesProcessed, "Full-text index rebuilt")

            // Phase 3: Thread detection - assign messages to threads
            let threadingResult = performThreadDetection(
                for: processedMessages,
                errors: &errors
            )
            threadsCreated = threadingResult.created
            threadsUpdated = threadingResult.updated
        }

        reportProgress(.complete, messagesProcessed, messagesProcessed, "Sync complete")

        // Log mailbox cache efficiency
        let totalCacheLookups = mailboxCacheHits + mailboxCacheMisses
        if totalCacheLookups > 0 {
            let hitRate = Double(mailboxCacheHits) / Double(totalCacheLookups) * 100
            let logMessage = "Mailbox cache: \(mailboxCacheHits) hits, \(mailboxCacheMisses) misses (\(String(format: "%.1f", hitRate))% hit rate)"
            reportProgress(.complete, messagesProcessed, messagesProcessed, logMessage)
        }

        let result = SyncResult(
            messagesProcessed: messagesProcessed,
            messagesAdded: messagesAdded,
            messagesUpdated: messagesUpdated,
            messagesDeleted: messagesDeleted,
            messagesUnchanged: messagesUnchanged,
            mailboxesProcessed: mailboxesProcessed,
            threadsCreated: threadsCreated,
            threadsUpdated: threadsUpdated,
            errors: errors,
            duration: Date().timeIntervalSince(startTime),
            isIncremental: useIncremental
        )

        // Record successful sync completion with all stats
        try mailDatabase.recordSyncSuccess(result: result)

        return result
    }

    // MARK: - Incremental Sync

    private struct IncrementalSyncResult {
        var processed: Int = 0
        var added: Int = 0
        var updated: Int = 0
        var deleted: Int = 0
        var unchanged: Int = 0
        var mailboxMoves: Int = 0
        var threadsCreated: Int = 0
        var threadsUpdated: Int = 0
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

            // Process messages into objects
            var processedMessages: [MailMessage] = []
            processedMessages.reserveCapacity(newMessages.count)

            let progressBatchSize = 100
            for (index, messageRow) in newMessages.enumerated() {
                do {
                    let message = try processMessageToObject(messageRow, mailBasePath: info.mailBasePath)
                    processedMessages.append(message)

                    if index % progressBatchSize == 0 || index == newMessages.count - 1 {
                        reportProgress(.syncingMessages, index + 1, newMessages.count,
                                       "Processed \(index + 1)/\(newMessages.count) new messages")
                    }
                } catch {
                    errors.append("Message \(messageRow.rowId): \(error.localizedDescription)")
                }
            }

            // Batch insert all processed messages
            // Note: FTS triggers are disabled during batch insert and index is rebuilt after
            let batchConfig = MailDatabase.BatchInsertConfig(batchSize: options.databaseBatchSize)
            let batchResult = try mailDatabase.batchUpsertMessages(processedMessages, config: batchConfig)

            result.added = batchResult.inserted
            result.updated = batchResult.updated
            result.processed = batchResult.inserted + batchResult.updated
            errors.append(contentsOf: batchResult.errors)

            // Report indexing phase (FTS rebuild happens in batchUpsertMessages defer block)
            reportProgress(.indexing, result.processed, result.processed, "Full-text index rebuilt")

            // Thread detection for new messages
            let threadingResult = performThreadDetection(
                for: processedMessages,
                errors: &errors
            )
            result.threadsCreated = threadingResult.created
            result.threadsUpdated = threadingResult.updated
        }

        // Phase 1.5: Detect missed messages (ROWID-based)
        // This catches messages that slipped through timestamp-based sync due to
        // Apple Mail's delayed writes to the Envelope Index (race condition fix).
        // A message received at T1 might not be in the DB until after we sync at T2,
        // causing the next sync to skip it because T1 < T2.
        reportProgress(.syncingMessages, 0, 1, "Checking for missed messages...")
        let missedMessages = try detectMissedMessages(info: info, errors: &errors)
        result.added += missedMessages.added
        result.processed += missedMessages.added

        // Phase 2: Check for status changes on existing messages (read/flagged)
        reportProgress(.detectingChanges, 0, 1, "Detecting status changes...")
        let statusChanges = try detectStatusChanges()
        if statusChanges > 0 {
            result.updated += statusChanges
            result.processed += statusChanges
        }

        // Phase 3: Detect mailbox moves (forward sync - Apple Mail wins)
        reportProgress(.detectingChanges, 0, 1, "Detecting mailbox moves...")
        let mailboxMoves = try detectMailboxMoves()
        result.mailboxMoves = mailboxMoves
        result.processed += mailboxMoves

        // Phase 4: Detect deleted messages
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

    /// Detect messages that exist in Apple Mail but are missing from the mirror database.
    /// This fixes a race condition where Apple Mail delays writing to the Envelope Index:
    /// - Message received at time T1
    /// - Not written to Envelope Index yet
    /// - Sync runs at T2, updating last_sync_time = T2
    /// - Mail finally writes message to Envelope Index
    /// - Next sync skips it because T1 < T2
    ///
    /// By comparing ROWIDs instead of just timestamps, we catch any messages that slipped through.
    private func detectMissedMessages(
        info: EnvelopeIndexInfo,
        errors: inout [String]
    ) throws -> (added: Int, processed: Int) {
        // Get all ROWIDs currently in Apple Mail's Inbox
        let sourceRowIds = try queryInboxRowIds()
        guard !sourceRowIds.isEmpty else { return (0, 0) }

        // Get all ROWIDs we've already synced to the mirror
        let mirrorRowIds = Set(try mailDatabase.getAllAppleRowIds())

        // Find ROWIDs in source that are NOT in mirror (missed messages)
        let missedRowIds = sourceRowIds.subtracting(mirrorRowIds)
        guard !missedRowIds.isEmpty else { return (0, 0) }

        reportProgress(.syncingMessages, 0, missedRowIds.count,
                       "Found \(missedRowIds.count) missed messages, syncing...")

        // Query full message details for the missed ROWIDs
        let missedMessages = try queryMessagesByRowIds(Array(missedRowIds))

        // Process messages into objects
        var processedMessages: [MailMessage] = []
        processedMessages.reserveCapacity(missedMessages.count)

        for messageRow in missedMessages {
            do {
                let message = try processMessageToObject(messageRow, mailBasePath: info.mailBasePath)
                processedMessages.append(message)
            } catch {
                errors.append("Missed message \(messageRow.rowId): \(error.localizedDescription)")
            }
        }

        guard !processedMessages.isEmpty else { return (0, 0) }

        // Batch insert the missed messages
        let batchConfig = MailDatabase.BatchInsertConfig(batchSize: options.databaseBatchSize)
        let batchResult = try mailDatabase.batchUpsertMessages(processedMessages, config: batchConfig)
        errors.append(contentsOf: batchResult.errors)

        return (batchResult.inserted, batchResult.inserted + batchResult.updated)
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

    /// Detect messages that have moved between mailboxes in Apple Mail (forward sync)
    /// This detects when users archive or delete messages in Apple Mail and updates the mirror.
    /// Apple Mail is the source of truth - if a message moves back to INBOX, we reset to .inbox status.
    /// - Returns: Count of status changes detected
    public func detectMailboxMoves() throws -> Int {
        // Get all inbox messages we're tracking
        let trackedMessages = try mailDatabase.getTrackedInboxMessages()
        guard !trackedMessages.isEmpty else { return 0 }

        var changesDetected = 0

        // Batch query current mailbox from Apple Mail for these messages
        let batchSize = 500
        for batch in stride(from: 0, to: trackedMessages.count, by: batchSize) {
            let end = min(batch + batchSize, trackedMessages.count)
            let batchMessages = Array(trackedMessages[batch..<end])

            let rowIds = batchMessages.map { $0.appleRowId }
            let idList = rowIds.map { String($0) }.joined(separator: ",")

            // Query current mailbox for each message
            let sql = """
                SELECT m.ROWID, m.mailbox, mb.url
                FROM messages m
                LEFT JOIN mailboxes mb ON m.mailbox = mb.ROWID
                WHERE m.ROWID IN (\(idList))
                """

            let rows = try executeQuery(sql)

            // Build a map of rowId -> mailbox info
            var mailboxInfoMap: [Int: (mailboxId: Int, mailboxType: MailboxType)] = [:]
            for row in rows {
                guard let rowId = row["ROWID"] as? Int64,
                      let mailboxId = row["mailbox"] as? Int64 else {
                    continue
                }
                let url = row["url"] as? String
                let mailboxType = classifyMailbox(url: url, name: nil)
                mailboxInfoMap[Int(rowId)] = (Int(mailboxId), mailboxType)
            }

            // Check each tracked message for moves
            for tracked in batchMessages {
                guard let mailboxInfo = mailboxInfoMap[tracked.appleRowId] else {
                    // Message no longer exists in Apple Mail - will be handled by deletion detection
                    continue
                }

                let newMailboxType = mailboxInfo.mailboxType
                let currentStatus = tracked.mailboxStatus

                // Determine if status needs to change based on mailbox type
                let newStatus: MailboxStatus
                switch newMailboxType {
                case .inbox:
                    newStatus = .inbox
                case .archive:
                    newStatus = .archived
                case .trash:
                    newStatus = .deleted
                default:
                    // For other mailbox types (sent, drafts, junk, other), keep as inbox
                    // These moves are less common and don't fit our status model
                    continue
                }

                // Update if status changed
                if newStatus != currentStatus {
                    try mailDatabase.updateMailboxStatus(id: tracked.id, status: newStatus)
                    changesDetected += 1
                }
            }
        }

        return changesDetected
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

        // Set busy timeout to prevent indefinite hangs when Mail.app holds locks
        // 5 second timeout - if locked longer, fail with SQLITE_BUSY rather than hang
        sqlite3_busy_timeout(db, 5000)

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

    /// Populate the mailbox cache from the database to eliminate redundant queries during message processing.
    /// Caches mailbox ID -> (name, url, path) mappings for all mailboxes.
    private func populateMailboxCache(mailBasePath: String) throws {
        mailboxCache.removeAll()
        mailboxCacheHits = 0
        mailboxCacheMisses = 0

        let sql = """
            SELECT ROWID, url
            FROM mailboxes
            WHERE url IS NOT NULL
            """

        let rows = try executeQuery(sql)

        for row in rows {
            guard let rowId = row["ROWID"] as? Int64,
                  let url = row["url"] as? String else {
                continue
            }

            let name = extractMailboxName(from: url)
            let path = convertMailboxUrlToPath(url, mailBasePath: mailBasePath)

            let info = MailboxInfo(
                id: Int(rowId),
                name: name,
                url: url,
                path: path
            )

            mailboxCache[Int(rowId)] = info
        }
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

    /// Query all ROWIDs from Apple Mail's Inbox (for detecting missed messages)
    /// This helps catch messages that slipped through timestamp-based sync due to
    /// Apple Mail's delayed writes to the Envelope Index.
    private func queryInboxRowIds() throws -> Set<Int> {
        let sql = """
            SELECT m.ROWID
            FROM messages m
            INNER JOIN mailboxes mb ON m.mailbox = mb.ROWID
            WHERE LOWER(mb.url) LIKE '%/inbox'
            """

        let rows = try executeQuery(sql)
        var rowIds = Set<Int>()
        for row in rows {
            if let rowId = row["ROWID"] as? Int64 {
                rowIds.insert(Int(rowId))
            }
        }
        return rowIds
    }

    /// Query messages by specific ROWIDs (for syncing missed messages)
    private func queryMessagesByRowIds(_ rowIds: [Int]) throws -> [MessageRow] {
        guard !rowIds.isEmpty else { return [] }

        let idList = rowIds.map { String($0) }.joined(separator: ",")
        let sql = """
            SELECT m.ROWID, s.subject, a.address AS sender_email, a.comment AS sender_name,
                   m.date_received, m.date_sent, m.message_id, m.mailbox, m.read, m.flagged
            FROM messages m
            LEFT JOIN subjects s ON m.subject = s.ROWID
            LEFT JOIN addresses a ON m.sender = a.ROWID
            INNER JOIN mailboxes mb ON m.mailbox = mb.ROWID
            WHERE LOWER(mb.url) LIKE '%/inbox' AND m.ROWID IN (\(idList))
            ORDER BY m.date_received DESC
            """

        let rows = try executeQuery(sql)

        return rows.compactMap { row -> MessageRow? in
            guard let rowId = row["ROWID"] as? Int64 else { return nil }

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
                hasAttachments: false
            )
        }
    }

    private func queryMessages(since: Date?) throws -> [MessageRow] {
        // Query message columns with JOINs to resolve subject/sender foreign keys
        // The messages.subject and messages.sender columns are FK integers, not text
        // Attachment detection is done during .emlx parsing instead
        // Filter to main INBOX only: excludes subfolders like Inbox/Kudos
        var sql = """
            SELECT m.ROWID, s.subject, a.address AS sender_email, a.comment AS sender_name,
                   m.date_received, m.date_sent, m.message_id, m.mailbox, m.read, m.flagged
            FROM messages m
            LEFT JOIN subjects s ON m.subject = s.ROWID
            LEFT JOIN addresses a ON m.sender = a.ROWID
            INNER JOIN mailboxes mb ON m.mailbox = mb.ROWID
            WHERE LOWER(mb.url) LIKE '%/inbox'
            """

        if let sinceDate = since {
            let timestamp = sinceDate.timeIntervalSince1970
            sql += " AND m.date_received > \(timestamp)"
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

        // Try to get body content and threading headers from .emlx file
        var bodyText: String? = nil
        var bodyHtml: String? = nil
        var emlxPath: String? = nil
        var inReplyTo: String? = nil
        var references: [String] = []
        var messageId: String? = row.messageId  // Initialize with DB value as fallback

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
                        // Extract threading headers and RFC822 Message-ID
                        inReplyTo = parsed.inReplyTo
                        references = parsed.references
                        messageId = parsed.messageId ?? messageId  // Prefer parsed value from .emlx
                    } catch {
                        // Log but don't fail - body content is optional
                    }
                }
            }
        }

        let message = MailMessage(
            id: stableId,
            appleRowId: Int(row.rowId),
            messageId: messageId,
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
            bodyHtml: bodyHtml,
            inReplyTo: inReplyTo,
            references: references
        )

        try mailDatabase.upsertMessage(message)

        return (added: existing == nil, updated: existing != nil)
    }

    /// Process a message row into a MailMessage object without database operations.
    /// Used for batch insert operations.
    private func processMessageToObject(_ row: MessageRow, mailBasePath: String) throws -> MailMessage {
        // Generate stable ID
        let stableId = idGenerator.generateId(
            messageId: row.messageId,
            subject: row.subject,
            sender: row.sender,
            date: row.dateReceived.map { Date(timeIntervalSince1970: $0) },
            appleRowId: Int(row.rowId)
        )

        // Parse sender
        var senderName: String? = nil
        var senderEmail: String? = nil
        if let sender = row.sender {
            let parsed = parseSenderString(sender)
            senderName = parsed.name
            senderEmail = parsed.email
        }

        // Get mailbox info from cache
        var mailboxName: String? = nil
        var mailboxPath: String? = nil
        if let mailboxId = row.mailboxId {
            if let cached = mailboxCache[Int(mailboxId)] {
                mailboxName = cached.name
                mailboxPath = cached.path
                mailboxCacheHits += 1
            } else {
                // Cache miss - fallback to database query
                let mailboxSql = "SELECT url FROM mailboxes WHERE ROWID = \(mailboxId)"
                if let mailboxRows = try? executeQuery(mailboxSql),
                   let first = mailboxRows.first,
                   let url = first["url"] as? String {
                    mailboxName = extractMailboxName(from: url)
                    mailboxPath = convertMailboxUrlToPath(url, mailBasePath: mailBasePath)
                    mailboxCacheMisses += 1
                }
            }
        }

        // Try to get body content and threading headers from .emlx file
        var bodyText: String? = nil
        var bodyHtml: String? = nil
        var emlxPath: String? = nil
        var inReplyTo: String? = nil
        var references: [String] = []
        var messageId: String? = row.messageId  // Initialize with DB value as fallback

        if let path = mailboxPath {
            // Use cached mailbox path to locate .emlx file
            emlxPath = discovery.emlxPath(forMessageId: Int(row.rowId), mailboxPath: path, mailBasePath: mailBasePath)

            // Try to parse .emlx
            if let path = emlxPath {
                do {
                    let parsed = try emlxParser.parse(path: path)
                    bodyText = parsed.bodyText
                    bodyHtml = parsed.bodyHtml
                    // Extract threading headers and RFC822 Message-ID
                    inReplyTo = parsed.inReplyTo
                    references = parsed.references
                    messageId = parsed.messageId ?? messageId  // Prefer parsed value from .emlx
                } catch {
                    // Log but don't fail - body content is optional
                }
            }
        }

        return MailMessage(
            id: stableId,
            appleRowId: Int(row.rowId),
            messageId: messageId,
            mailboxId: row.mailboxId.map { Int($0) },
            mailboxName: mailboxName,
            accountId: nil,
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
            bodyHtml: bodyHtml,
            inReplyTo: inReplyTo,
            references: references
        )
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
        // Handle file:// URLs directly
        if url.hasPrefix("file://") {
            return url.replacingOccurrences(of: "file://", with: "")
        }

        // Strip URL scheme (ews://, imap://, etc.)
        var path = url
        if let schemeEnd = url.range(of: "://") {
            path = String(url[schemeEnd.upperBound...])
        }

        // URL decode (e.g., %20 -> space)
        if let decoded = path.removingPercentEncoding {
            path = decoded
        }

        // Split into components: first is account UUID, rest is mailbox path
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else {
            return (mailBasePath as NSString).appendingPathComponent(url)
        }

        // Build the filesystem path:
        // {mailBasePath}/{versionDirectory}/{accountUUID}/{mailbox}.mbox/{submailbox}.mbox/...
        let versionDir = envelopeInfo?.versionDirectory ?? "V10"
        var fsPath = (mailBasePath as NSString).appendingPathComponent(versionDir)

        // First component is the account UUID (no .mbox suffix)
        fsPath = (fsPath as NSString).appendingPathComponent(components[0])

        // Remaining components are mailbox hierarchy (each gets .mbox suffix)
        for i in 1..<components.count {
            fsPath = (fsPath as NSString).appendingPathComponent(components[i] + ".mbox")
        }

        return fsPath
    }

    // MARK: - Thread Detection

    /// Result of thread detection operation
    private struct ThreadDetectionSyncResult {
        var created: Int = 0
        var updated: Int = 0
    }

    /// Perform thread detection for a batch of messages.
    ///
    /// This method processes messages through the ThreadDetectionService to:
    /// 1. Generate thread IDs based on threading headers
    /// 2. Create new threads or update existing ones
    /// 3. Link messages to their threads
    ///
    /// Thread detection errors are non-fatal - they are logged but don't fail the sync.
    ///
    /// - Parameters:
    ///   - messages: The messages to process for threading
    ///   - errors: Array to append any threading errors to
    /// - Returns: Threading statistics (threads created/updated)
    private func performThreadDetection(
        for messages: [MailMessage],
        errors: inout [String]
    ) -> ThreadDetectionSyncResult {
        var result = ThreadDetectionSyncResult()

        guard !messages.isEmpty else { return result }

        reportProgress(.threadingMessages, 0, messages.count, "Detecting threads for \(messages.count) messages...")

        let progressBatchSize = 100
        for (index, message) in messages.enumerated() {
            do {
                let threadResult = try threadDetectionService.processMessageForThreading(
                    message,
                    database: mailDatabase
                )

                if threadResult.isNewThread {
                    result.created += 1
                } else {
                    result.updated += 1
                }

                if index % progressBatchSize == 0 || index == messages.count - 1 {
                    reportProgress(.threadingMessages, index + 1, messages.count,
                                   "Threaded \(index + 1)/\(messages.count) messages")
                }
            } catch {
                // Thread detection errors are non-fatal - log but continue
                errors.append("Threading for message \(message.id): \(error.localizedDescription)")
            }
        }

        reportProgress(.threadingMessages, messages.count, messages.count,
                       "Created \(result.created) threads, updated \(result.updated)")

        return result
    }

    // MARK: - Progress Reporting

    private func reportProgress(_ phase: SyncPhase, _ current: Int, _ total: Int, _ message: String) {
        let progress = SyncProgress(phase: phase, current: current, total: total, message: message)
        onProgress?(progress)
    }
}
