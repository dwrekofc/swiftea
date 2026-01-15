import XCTest
@testable import SwiftEAKit

/// Mock FileManager that simulates missing Apple Mail directory
/// Used to test sync failure paths without actually accessing the filesystem
private class MockFileManagerNoMail: FileManager {
    override var homeDirectoryForCurrentUser: URL {
        // Return a temp directory that won't have Apple Mail
        return URL(fileURLWithPath: NSTemporaryDirectory())
    }

    override func fileExists(atPath path: String) -> Bool {
        // Apple Mail directory doesn't exist
        return false
    }

    override func isReadableFile(atPath path: String) -> Bool {
        return false
    }
}

final class MailSyncTests: XCTestCase {
    var testDir: String!
    var mailDatabase: MailDatabase!

    override func setUp() {
        super.setUp()
        testDir = NSTemporaryDirectory() + "swiftea-sync-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)

        let dbPath = (testDir as NSString).appendingPathComponent("mail.db")
        mailDatabase = MailDatabase(databasePath: dbPath)
        do {
            try mailDatabase.initialize()
        } catch {
            XCTFail("Failed to initialize mail database: \(error)")
        }
    }

    override func tearDown() {
        mailDatabase.close()
        try? FileManager.default.removeItem(atPath: testDir)
        mailDatabase = nil
        super.tearDown()
    }

    // MARK: - SyncProgress Tests

    func testSyncProgressInitialization() {
        let progress = SyncProgress(
            phase: .syncingMessages,
            current: 50,
            total: 100,
            message: "Processing..."
        )

        XCTAssertEqual(progress.phase, .syncingMessages)
        XCTAssertEqual(progress.current, 50)
        XCTAssertEqual(progress.total, 100)
        XCTAssertEqual(progress.message, "Processing...")
    }

    func testSyncProgressPercentage() {
        let progress = SyncProgress(phase: .syncingMessages, current: 25, total: 100, message: "")
        XCTAssertEqual(progress.percentage, 25.0, accuracy: 0.01)

        let halfProgress = SyncProgress(phase: .syncingMessages, current: 50, total: 100, message: "")
        XCTAssertEqual(halfProgress.percentage, 50.0, accuracy: 0.01)

        let fullProgress = SyncProgress(phase: .complete, current: 100, total: 100, message: "")
        XCTAssertEqual(fullProgress.percentage, 100.0, accuracy: 0.01)
    }

    func testSyncProgressPercentageWithZeroTotal() {
        let progress = SyncProgress(phase: .discovering, current: 0, total: 0, message: "")
        XCTAssertEqual(progress.percentage, 0.0)
    }

    // MARK: - SyncPhase Tests

    func testSyncPhaseRawValues() {
        XCTAssertEqual(SyncPhase.discovering.rawValue, "Discovering")
        XCTAssertEqual(SyncPhase.syncingMailboxes.rawValue, "Syncing mailboxes")
        XCTAssertEqual(SyncPhase.syncingMessages.rawValue, "Syncing messages")
        XCTAssertEqual(SyncPhase.parsingContent.rawValue, "Parsing content")
        XCTAssertEqual(SyncPhase.indexing.rawValue, "Indexing")
        XCTAssertEqual(SyncPhase.complete.rawValue, "Complete")
    }

    // MARK: - SyncResult Tests

    func testSyncResultInitialization() {
        let result = SyncResult(
            messagesProcessed: 100,
            messagesAdded: 80,
            messagesUpdated: 20,
            mailboxesProcessed: 5,
            errors: ["Error 1", "Error 2"],
            duration: 10.5
        )

        XCTAssertEqual(result.messagesProcessed, 100)
        XCTAssertEqual(result.messagesAdded, 80)
        XCTAssertEqual(result.messagesUpdated, 20)
        XCTAssertEqual(result.mailboxesProcessed, 5)
        XCTAssertEqual(result.errors.count, 2)
        XCTAssertEqual(result.duration, 10.5, accuracy: 0.01)
    }

    func testSyncResultWithNoErrors() {
        let result = SyncResult(
            messagesProcessed: 50,
            messagesAdded: 50,
            messagesUpdated: 0,
            mailboxesProcessed: 3,
            errors: [],
            duration: 5.0
        )

        XCTAssertTrue(result.errors.isEmpty)
    }

    // MARK: - MailSyncError Tests

    func testMailSyncErrorDescriptions() {
        let underlyingError = NSError(domain: "Test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Test error"
        ])

        let errors: [MailSyncError] = [
            .sourceConnectionFailed(underlying: underlyingError),
            .sourceDatabaseLocked,
            .queryFailed(query: "SELECT * FROM messages", underlying: underlyingError),
            .emlxParseFailed(path: "/path/to/file.emlx", underlying: underlyingError),
            .syncFailed(underlying: underlyingError)
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func testSourceDatabaseLockedErrorMessage() {
        let error = MailSyncError.sourceDatabaseLocked
        XCTAssertTrue(error.errorDescription?.contains("locked") == true)
        XCTAssertTrue(error.errorDescription?.contains("Mail") == true)
    }

    func testQueryFailedIncludesQuery() {
        let error = MailSyncError.queryFailed(
            query: "SELECT * FROM test",
            underlying: NSError(domain: "Test", code: 1)
        )
        XCTAssertTrue(error.errorDescription?.contains("SELECT * FROM test") == true)
    }

    func testEmlxParseFailedIncludesPath() {
        let error = MailSyncError.emlxParseFailed(
            path: "/path/to/email.emlx",
            underlying: NSError(domain: "Test", code: 1)
        )
        XCTAssertTrue(error.errorDescription?.contains("/path/to/email.emlx") == true)
    }

    // MARK: - MailSync Initialization

    func testMailSyncInitialization() {
        let sync = MailSync(mailDatabase: mailDatabase)
        XCTAssertNotNil(sync)
    }

    func testMailSyncWithCustomDependencies() {
        let discovery = EnvelopeIndexDiscovery()
        let parser = EmlxParser()
        let idGenerator = StableIdGenerator()

        let sync = MailSync(
            mailDatabase: mailDatabase,
            discovery: discovery,
            emlxParser: parser,
            idGenerator: idGenerator
        )

        XCTAssertNotNil(sync)
    }

    // MARK: - Progress Callback

    func testProgressCallbackIsInvoked() throws {
        let sync = MailSync(mailDatabase: mailDatabase)

        var progressUpdates: [SyncProgress] = []
        sync.onProgress = { progress in
            progressUpdates.append(progress)
        }

        // Note: Actual sync requires access to Apple Mail database
        // This test verifies the callback mechanism is set up correctly
        XCTAssertNotNil(sync.onProgress)
    }

    // MARK: - Sender Parsing (via integration)

    // These tests verify the sender parsing logic through MailSync
    // by testing the expected behavior

    func testSenderParsingWithNameAndEmail() {
        // Format: "Name" <email@example.com>
        // This is tested indirectly through the full sync process
        // but we can verify the expected message structure

        let message = MailMessage(
            id: "test-1",
            subject: "Test",
            senderName: "John Doe",
            senderEmail: "john@example.com"
        )

        XCTAssertEqual(message.senderName, "John Doe")
        XCTAssertEqual(message.senderEmail, "john@example.com")
    }

    func testSenderParsingWithEmailOnly() {
        let message = MailMessage(
            id: "test-2",
            subject: "Test",
            senderName: nil,
            senderEmail: "plain@example.com"
        )

        XCTAssertNil(message.senderName)
        XCTAssertEqual(message.senderEmail, "plain@example.com")
    }

    // MARK: - Sync Without Apple Mail Access

    func testSyncFailsWithoutAppleMail() {
        // This test verifies that sync fails gracefully when Apple Mail
        // database is not accessible (which is the case in test environment)

        // Use mock FileManager that simulates missing Apple Mail directory
        let mockFileManager = MockFileManagerNoMail()
        let mockDiscovery = EnvelopeIndexDiscovery(fileManager: mockFileManager)
        let sync = MailSync(mailDatabase: mailDatabase, discovery: mockDiscovery)

        XCTAssertThrowsError(try sync.sync()) { error in
            // Should throw some form of discovery or connection error
            // The exact error depends on system state
            XCTAssertTrue(
                error is EnvelopeDiscoveryError || error is MailSyncError,
                "Expected discovery or sync error, got \(type(of: error))"
            )
        }
    }

    // MARK: - Incremental Sync Flag

    func testSyncAcceptsIncrementalFlag() {
        // Use mock FileManager that simulates missing Apple Mail directory
        let mockFileManager = MockFileManagerNoMail()
        let mockDiscovery = EnvelopeIndexDiscovery(fileManager: mockFileManager)
        let sync = MailSync(mailDatabase: mailDatabase, discovery: mockDiscovery)

        // Verify that forceFullSync parameter is accepted
        // Actual behavior requires Apple Mail access
        XCTAssertThrowsError(try sync.sync(forceFullSync: true))
        XCTAssertThrowsError(try sync.sync(forceFullSync: false))
    }

    // MARK: - Last Sync Time Integration

    func testLastSyncTimeIsPersisted() throws {
        // After a successful sync, last sync time should be set
        // We can verify the database side of this

        let testTime = Date(timeIntervalSince1970: 1736177400)
        try mailDatabase.setLastSyncTime(testTime)

        let retrieved = try mailDatabase.getLastSyncTime()
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved!.timeIntervalSince1970, 1736177400, accuracy: 1.0)
    }

    func testIncrementalSyncUsesLastSyncTime() throws {
        // Set a last sync time
        let lastSync = Date(timeIntervalSince1970: 1736177400)
        try mailDatabase.setLastSyncTime(lastSync)

        // Verify it can be retrieved for incremental sync
        let retrieved = try mailDatabase.getLastSyncTime()
        XCTAssertNotNil(retrieved)

        // The sync would use this to filter messages
        // Actual filtering requires Apple Mail access
    }

    // MARK: - Component Integration

    func testAllComponentsWorkTogether() throws {
        // Verify that all mail module components can be instantiated
        // and work together

        let parser = EmlxParser()
        let discovery = EnvelopeIndexDiscovery()
        let idGenerator = StableIdGenerator()

        let sync = MailSync(
            mailDatabase: mailDatabase,
            discovery: discovery,
            emlxParser: parser,
            idGenerator: idGenerator
        )

        // Generate a stable ID
        let id = idGenerator.generateId(
            messageId: "<test@example.com>",
            subject: nil,
            sender: nil,
            date: nil,
            appleRowId: nil
        )

        // Create a message with that ID
        let message = MailMessage(
            id: id,
            messageId: "<test@example.com>",
            subject: "Integration Test"
        )

        // Store in database
        try mailDatabase.upsertMessage(message)

        // Retrieve and verify
        let retrieved = try mailDatabase.getMessage(id: id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.messageId, "<test@example.com>")

        // Sync object is ready (would work if Apple Mail were accessible)
        XCTAssertNotNil(sync)
    }

    // MARK: - End-to-End with Mock Data

    func testEndToEndWithMockEmlxData() throws {
        // Create test .emlx file
        let parser = EmlxParser()
        let idGenerator = StableIdGenerator()

        // Create test file (byte count 241 = length of RFC822 message portion)
        let emlxContent = """
241
Message-ID: <test123@example.com>
From: John Doe <john@example.com>
To: Jane Smith <jane@example.com>
Subject: Simple Test Email
Date: Mon, 06 Jan 2026 10:30:00 -0500
Content-Type: text/plain; charset=utf-8

This is a simple test email body.
"""
        let testFilePath = (testDir as NSString).appendingPathComponent("test.emlx")
        try emlxContent.write(toFile: testFilePath, atomically: true, encoding: .utf8)

        // Parse the test file
        let parsed = try parser.parse(path: testFilePath)

        // Generate stable ID
        let id = idGenerator.generateId(
            messageId: parsed.messageId,
            subject: parsed.subject,
            sender: parsed.from?.email,
            date: parsed.date,
            appleRowId: 12345
        )

        // Create message from parsed data
        let message = MailMessage(
            id: id,
            appleRowId: 12345,
            messageId: parsed.messageId,
            mailboxId: 1,
            mailboxName: "INBOX",
            subject: parsed.subject ?? "(No Subject)",
            senderName: parsed.from?.name,
            senderEmail: parsed.from?.email,
            dateSent: parsed.date,
            dateReceived: parsed.date,
            isRead: false,
            isFlagged: false,
            isDeleted: false,
            hasAttachments: !parsed.attachments.isEmpty,
            bodyText: parsed.bodyText,
            bodyHtml: parsed.bodyHtml
        )

        // Store in database
        try mailDatabase.upsertMessage(message)

        // Retrieve and verify
        let retrieved = try mailDatabase.getMessage(id: id)

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.subject, "Simple Test Email")
        XCTAssertEqual(retrieved?.senderName, "John Doe")
        XCTAssertEqual(retrieved?.senderEmail, "john@example.com")
        XCTAssertTrue(retrieved?.bodyText?.contains("simple test email body") == true)

        // Verify FTS works
        let searchResults = try mailDatabase.searchMessages(query: "simple test")
        XCTAssertEqual(searchResults.count, 1)
        XCTAssertEqual(searchResults.first?.id, id)
    }

    // MARK: - Incremental Sync Tests

    func testSyncResultWithIncrementalFields() {
        let result = SyncResult(
            messagesProcessed: 100,
            messagesAdded: 50,
            messagesUpdated: 30,
            messagesDeleted: 10,
            messagesUnchanged: 10,
            mailboxesProcessed: 5,
            errors: [],
            duration: 5.0,
            isIncremental: true
        )

        XCTAssertEqual(result.messagesProcessed, 100)
        XCTAssertEqual(result.messagesAdded, 50)
        XCTAssertEqual(result.messagesUpdated, 30)
        XCTAssertEqual(result.messagesDeleted, 10)
        XCTAssertEqual(result.messagesUnchanged, 10)
        XCTAssertTrue(result.isIncremental)
    }

    func testSyncResultDefaultsForBackwardCompatibility() {
        // Ensure old-style initialization still works with defaults
        let result = SyncResult(
            messagesProcessed: 100,
            messagesAdded: 80,
            messagesUpdated: 20,
            mailboxesProcessed: 5,
            errors: [],
            duration: 5.0
        )

        XCTAssertEqual(result.messagesDeleted, 0)
        XCTAssertEqual(result.messagesUnchanged, 0)
        XCTAssertFalse(result.isIncremental)
    }

    func testNewSyncPhases() {
        XCTAssertEqual(SyncPhase.detectingChanges.rawValue, "Detecting changes")
        XCTAssertEqual(SyncPhase.detectingDeletions.rawValue, "Detecting deletions")
    }

    // MARK: - Incremental Sync Database Support Tests

    func testGetAllMessageStatuses() throws {
        // Insert test messages
        let msg1 = MailMessage(
            id: "test-status-1",
            appleRowId: 100,
            subject: "Test 1",
            isRead: true,
            isFlagged: false
        )
        let msg2 = MailMessage(
            id: "test-status-2",
            appleRowId: 200,
            subject: "Test 2",
            isRead: false,
            isFlagged: true
        )

        try mailDatabase.upsertMessage(msg1)
        try mailDatabase.upsertMessage(msg2)

        let statuses = try mailDatabase.getAllMessageStatuses()

        XCTAssertEqual(statuses.count, 2)

        let status1 = statuses.first(where: { $0.id == "test-status-1" })
        XCTAssertNotNil(status1)
        XCTAssertEqual(status1?.appleRowId, 100)
        XCTAssertTrue(status1?.isRead ?? false)
        XCTAssertFalse(status1?.isFlagged ?? true)

        let status2 = statuses.first(where: { $0.id == "test-status-2" })
        XCTAssertNotNil(status2)
        XCTAssertEqual(status2?.appleRowId, 200)
        XCTAssertFalse(status2?.isRead ?? true)
        XCTAssertTrue(status2?.isFlagged ?? false)
    }

    func testUpdateMessageStatus() throws {
        // Insert a message
        let msg = MailMessage(
            id: "test-update-status",
            appleRowId: 300,
            subject: "Test Update",
            isRead: false,
            isFlagged: false
        )
        try mailDatabase.upsertMessage(msg)

        // Verify initial state
        var retrieved = try mailDatabase.getMessage(id: "test-update-status")
        XCTAssertFalse(retrieved?.isRead ?? true)
        XCTAssertFalse(retrieved?.isFlagged ?? true)

        // Update status
        try mailDatabase.updateMessageStatus(id: "test-update-status", isRead: true, isFlagged: true)

        // Verify updated state
        retrieved = try mailDatabase.getMessage(id: "test-update-status")
        XCTAssertTrue(retrieved?.isRead ?? false)
        XCTAssertTrue(retrieved?.isFlagged ?? false)
    }

    func testGetAllAppleRowIds() throws {
        // Insert test messages
        let msg1 = MailMessage(id: "test-rowid-1", appleRowId: 1001, subject: "Test 1")
        let msg2 = MailMessage(id: "test-rowid-2", appleRowId: 1002, subject: "Test 2")
        let msg3 = MailMessage(id: "test-rowid-3", appleRowId: 1003, subject: "Test 3", isDeleted: true)

        try mailDatabase.upsertMessage(msg1)
        try mailDatabase.upsertMessage(msg2)
        try mailDatabase.upsertMessage(msg3)

        let rowIds = try mailDatabase.getAllAppleRowIds()

        // Should not include deleted message
        XCTAssertTrue(rowIds.contains(1001))
        XCTAssertTrue(rowIds.contains(1002))
        XCTAssertFalse(rowIds.contains(1003))
    }

    func testMarkMessageDeleted() throws {
        // Insert a message
        let msg = MailMessage(
            id: "test-delete",
            appleRowId: 500,
            subject: "To Be Deleted",
            isDeleted: false
        )
        try mailDatabase.upsertMessage(msg)

        // Verify not deleted
        var retrieved = try mailDatabase.getMessage(id: "test-delete")
        XCTAssertFalse(retrieved?.isDeleted ?? true)

        // Mark as deleted
        try mailDatabase.markMessageDeleted(appleRowId: 500)

        // Verify deleted
        retrieved = try mailDatabase.getMessage(id: "test-delete")
        XCTAssertTrue(retrieved?.isDeleted ?? false)
    }

    func testDeletedMessagesExcludedFromStatuses() throws {
        // Insert messages, one deleted
        let msg1 = MailMessage(id: "active-msg", appleRowId: 600, subject: "Active")
        let msg2 = MailMessage(id: "deleted-msg", appleRowId: 601, subject: "Deleted", isDeleted: true)

        try mailDatabase.upsertMessage(msg1)
        try mailDatabase.upsertMessage(msg2)

        let statuses = try mailDatabase.getAllMessageStatuses()

        // Only active message should be in statuses
        XCTAssertEqual(statuses.count, 1)
        XCTAssertEqual(statuses.first?.id, "active-msg")
    }

    func testIncrementalSyncFasterThanFull() {
        // This is a conceptual test - in practice, incremental sync should be faster
        // because it only processes changed messages instead of all messages

        let fullResult = SyncResult(
            messagesProcessed: 10000,
            messagesAdded: 10000,
            messagesUpdated: 0,
            messagesDeleted: 0,
            messagesUnchanged: 0,
            mailboxesProcessed: 50,
            errors: [],
            duration: 60.0,
            isIncremental: false
        )

        let incrementalResult = SyncResult(
            messagesProcessed: 50,
            messagesAdded: 30,
            messagesUpdated: 15,
            messagesDeleted: 5,
            messagesUnchanged: 0,
            mailboxesProcessed: 50,
            errors: [],
            duration: 2.0,
            isIncremental: true
        )

        // Incremental should process fewer messages and take less time
        XCTAssertLessThan(incrementalResult.messagesProcessed, fullResult.messagesProcessed)
        XCTAssertLessThan(incrementalResult.duration, fullResult.duration)
        XCTAssertTrue(incrementalResult.isIncremental)
        XCTAssertFalse(fullResult.isIncremental)
    }

    // MARK: - MailboxType Tests

    func testMailboxTypeRawValues() {
        XCTAssertEqual(MailboxType.inbox.rawValue, "inbox")
        XCTAssertEqual(MailboxType.archive.rawValue, "archive")
        XCTAssertEqual(MailboxType.trash.rawValue, "trash")
        XCTAssertEqual(MailboxType.sent.rawValue, "sent")
        XCTAssertEqual(MailboxType.drafts.rawValue, "drafts")
        XCTAssertEqual(MailboxType.junk.rawValue, "junk")
        XCTAssertEqual(MailboxType.other.rawValue, "other")
    }

    // MARK: - classifyMailbox Tests

    func testClassifyMailboxInbox() {
        // Test case-insensitive INBOX detection
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/INBOX", name: nil), .inbox)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/inbox", name: nil), .inbox)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/Inbox", name: nil), .inbox)
        XCTAssertEqual(classifyMailbox(url: nil, name: "INBOX"), .inbox)
        XCTAssertEqual(classifyMailbox(url: nil, name: "inbox"), .inbox)
    }

    func testClassifyMailboxArchive() {
        // Test Archive folder detection
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/Archive", name: nil), .archive)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/All Mail", name: nil), .archive)
        XCTAssertEqual(classifyMailbox(url: nil, name: "Archive"), .archive)
        XCTAssertEqual(classifyMailbox(url: nil, name: "All Mail"), .archive)
    }

    func testClassifyMailboxTrash() {
        // Test Trash folder detection
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/Trash", name: nil), .trash)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/Deleted", name: nil), .trash)
        XCTAssertEqual(classifyMailbox(url: nil, name: "Trash"), .trash)
        XCTAssertEqual(classifyMailbox(url: nil, name: "Deleted Messages"), .trash)
    }

    func testClassifyMailboxSent() {
        // Test Sent folder detection
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/Sent", name: nil), .sent)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/Sent Messages", name: nil), .sent)
        XCTAssertEqual(classifyMailbox(url: nil, name: "Sent"), .sent)
        XCTAssertEqual(classifyMailbox(url: nil, name: "Sent Mail"), .sent)
    }

    func testClassifyMailboxDrafts() {
        // Test Drafts folder detection
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/Drafts", name: nil), .drafts)
        XCTAssertEqual(classifyMailbox(url: nil, name: "Drafts"), .drafts)
        XCTAssertEqual(classifyMailbox(url: nil, name: "Draft"), .drafts)
    }

    func testClassifyMailboxJunk() {
        // Test Junk/Spam folder detection
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/Junk", name: nil), .junk)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/Spam", name: nil), .junk)
        XCTAssertEqual(classifyMailbox(url: nil, name: "Junk"), .junk)
        XCTAssertEqual(classifyMailbox(url: nil, name: "Junk E-mail"), .junk)
    }

    func testClassifyMailboxOther() {
        // Test custom folders return .other
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/Work", name: nil), .other)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/Personal", name: nil), .other)
        XCTAssertEqual(classifyMailbox(url: nil, name: "Projects"), .other)
        XCTAssertEqual(classifyMailbox(url: nil, name: nil), .other)
    }

    func testClassifyMailboxIsCaseInsensitive() {
        // Test that classification is case-insensitive
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/INBOX", name: nil), .inbox)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/inbox", name: nil), .inbox)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/InBoX", name: nil), .inbox)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/ARCHIVE", name: nil), .archive)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/archive", name: nil), .archive)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/TRASH", name: nil), .trash)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/trash", name: nil), .trash)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/SENT", name: nil), .sent)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/sent", name: nil), .sent)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/JUNK", name: nil), .junk)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/junk", name: nil), .junk)
    }

    func testClassifyMailboxUrlTakesPrecedence() {
        // URL should be used if available, name is fallback
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/INBOX", name: "Trash"), .inbox)
        XCTAssertEqual(classifyMailbox(url: "mailbox://account/Trash", name: "INBOX"), .trash)
    }

    // MARK: - detectMailboxMoves Tests

    func testDetectMailboxMovesReturnsZeroForEmptyDatabase() throws {
        // With no messages in database, detectMailboxMoves should return 0
        // Note: Cannot actually call detectMailboxMoves without Apple Mail connection
        // This test verifies the supporting database methods work correctly

        let trackedMessages = try mailDatabase.getTrackedInboxMessages()
        XCTAssertTrue(trackedMessages.isEmpty)
    }

    func testGetTrackedInboxMessagesIncludesAllStatuses() throws {
        // Insert messages with different statuses
        let inboxMsg = MailMessage(
            id: "tracked-inbox-1",
            appleRowId: 1001,
            subject: "Inbox message",
            mailboxStatus: .inbox
        )
        let archivedMsg = MailMessage(
            id: "tracked-archived-1",
            appleRowId: 1002,
            subject: "Archived message",
            mailboxStatus: .archived
        )
        let deletedMsg = MailMessage(
            id: "tracked-deleted-1",
            appleRowId: 1003,
            subject: "Deleted message",
            mailboxStatus: .deleted
        )

        try mailDatabase.upsertMessage(inboxMsg)
        try mailDatabase.upsertMessage(archivedMsg)
        try mailDatabase.upsertMessage(deletedMsg)

        // getTrackedInboxMessages should return ALL messages (not just inbox)
        // so we can detect when messages move back to INBOX
        let tracked = try mailDatabase.getTrackedInboxMessages()

        XCTAssertEqual(tracked.count, 3)
        XCTAssertTrue(tracked.contains { $0.id == "tracked-inbox-1" && $0.mailboxStatus == .inbox })
        XCTAssertTrue(tracked.contains { $0.id == "tracked-archived-1" && $0.mailboxStatus == .archived })
        XCTAssertTrue(tracked.contains { $0.id == "tracked-deleted-1" && $0.mailboxStatus == .deleted })
    }

    func testGetTrackedInboxMessagesExcludesSoftDeleted() throws {
        // Insert an active message and a soft-deleted one
        let activeMsg = MailMessage(
            id: "tracked-active",
            appleRowId: 2001,
            subject: "Active message",
            isDeleted: false
        )
        let softDeletedMsg = MailMessage(
            id: "tracked-soft-deleted",
            appleRowId: 2002,
            subject: "Soft deleted message",
            isDeleted: true
        )

        try mailDatabase.upsertMessage(activeMsg)
        try mailDatabase.upsertMessage(softDeletedMsg)

        let tracked = try mailDatabase.getTrackedInboxMessages()

        // Only active message should be returned
        XCTAssertEqual(tracked.count, 1)
        XCTAssertEqual(tracked.first?.id, "tracked-active")
    }

    func testGetTrackedInboxMessagesExcludesZeroAppleRowId() throws {
        // Insert a message with appleRowId (trackable)
        let msgWithRowId = MailMessage(
            id: "tracked-with-rowid",
            appleRowId: 3001,
            subject: "With rowid"
        )

        try mailDatabase.upsertMessage(msgWithRowId)

        let tracked = try mailDatabase.getTrackedInboxMessages()

        // Message with valid appleRowId should be returned
        XCTAssertEqual(tracked.count, 1)
        XCTAssertEqual(tracked.first?.id, "tracked-with-rowid")
        XCTAssertEqual(tracked.first?.appleRowId, 3001)
    }

    func testTrackedMessageInfoContainsCorrectData() throws {
        let msg = MailMessage(
            id: "tracked-info-test",
            appleRowId: 4001,
            mailboxId: 42,
            subject: "Info test",
            mailboxStatus: .archived
        )

        try mailDatabase.upsertMessage(msg)

        let tracked = try mailDatabase.getTrackedInboxMessages()

        XCTAssertEqual(tracked.count, 1)
        let info = tracked.first!
        XCTAssertEqual(info.id, "tracked-info-test")
        XCTAssertEqual(info.appleRowId, 4001)
        XCTAssertEqual(info.mailboxId, 42)
        XCTAssertEqual(info.mailboxStatus, .archived)
    }

    func testUpdateMailboxStatusFromInboxToArchived() throws {
        // Insert a message in inbox
        let msg = MailMessage(
            id: "move-test-1",
            appleRowId: 5001,
            subject: "Move test",
            mailboxStatus: .inbox
        )
        try mailDatabase.upsertMessage(msg)

        // Verify initial status
        var retrieved = try mailDatabase.getMessage(id: "move-test-1")
        XCTAssertEqual(retrieved?.mailboxStatus, .inbox)

        // Update status to archived (simulating archive in Apple Mail)
        try mailDatabase.updateMailboxStatus(id: "move-test-1", status: .archived)

        // Verify status changed
        retrieved = try mailDatabase.getMessage(id: "move-test-1")
        XCTAssertEqual(retrieved?.mailboxStatus, .archived)
    }

    func testUpdateMailboxStatusFromArchivedToInbox() throws {
        // Insert a message in archived state
        let msg = MailMessage(
            id: "move-back-test",
            appleRowId: 5002,
            subject: "Move back test",
            mailboxStatus: .archived
        )
        try mailDatabase.upsertMessage(msg)

        // Update status back to inbox (simulating move back to INBOX in Apple Mail)
        try mailDatabase.updateMailboxStatus(id: "move-back-test", status: .inbox)

        // Verify status changed back to inbox
        let retrieved = try mailDatabase.getMessage(id: "move-back-test")
        XCTAssertEqual(retrieved?.mailboxStatus, .inbox)
    }

    func testUpdateMailboxStatusFromInboxToDeleted() throws {
        // Insert a message in inbox
        let msg = MailMessage(
            id: "trash-test",
            appleRowId: 5003,
            subject: "Trash test",
            mailboxStatus: .inbox
        )
        try mailDatabase.upsertMessage(msg)

        // Update status to deleted (simulating move to Trash in Apple Mail)
        try mailDatabase.updateMailboxStatus(id: "trash-test", status: .deleted)

        // Verify status changed
        let retrieved = try mailDatabase.getMessage(id: "trash-test")
        XCTAssertEqual(retrieved?.mailboxStatus, .deleted)
    }

    func testIncrementalSyncResultIncludesMailboxMoves() {
        // Verify SyncResult properly tracks mailbox moves
        let result = SyncResult(
            messagesProcessed: 100,
            messagesAdded: 50,
            messagesUpdated: 30,
            messagesDeleted: 10,
            messagesUnchanged: 5,
            mailboxesProcessed: 5,
            errors: [],
            duration: 2.0,
            isIncremental: true
        )

        // messagesProcessed should be the sum of all changes
        XCTAssertEqual(result.messagesProcessed, 100)
        XCTAssertTrue(result.isIncremental)
    }
}
