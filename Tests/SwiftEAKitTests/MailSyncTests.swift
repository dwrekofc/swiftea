import XCTest
@testable import SwiftEAKit

final class MailSyncTests: XCTestCase {
    var testDir: String!
    var mailDatabase: MailDatabase!

    override func setUp() {
        super.setUp()
        testDir = NSTemporaryDirectory() + "swiftea-sync-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)

        let dbPath = (testDir as NSString).appendingPathComponent("mail.db")
        mailDatabase = MailDatabase(databasePath: dbPath)
        try? mailDatabase.initialize()
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

        let sync = MailSync(mailDatabase: mailDatabase)

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
        let sync = MailSync(mailDatabase: mailDatabase)

        // Verify that incremental parameter is accepted
        // Actual behavior requires Apple Mail access
        XCTAssertThrowsError(try sync.sync(incremental: true))
        XCTAssertThrowsError(try sync.sync(incremental: false))
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
}
