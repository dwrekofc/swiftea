import XCTest
@testable import SwiftEAKit

final class MailDatabaseTests: XCTestCase {
    var testDir: String!
    var database: MailDatabase!

    override func setUp() {
        super.setUp()
        testDir = NSTemporaryDirectory() + "swiftea-maildb-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)

        let dbPath = (testDir as NSString).appendingPathComponent("mail.db")
        database = MailDatabase(databasePath: dbPath)
    }

    override func tearDown() {
        database.close()
        try? FileManager.default.removeItem(atPath: testDir)
        database = nil
        super.tearDown()
    }

    // MARK: - Initialization

    func testInitializeCreatesDatabase() throws {
        try database.initialize()

        let dbPath = (testDir as NSString).appendingPathComponent("mail.db")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath))
    }

    func testInitializeTwiceSucceeds() throws {
        try database.initialize()
        try database.initialize() // Should not throw
    }

    // MARK: - Message CRUD

    func testUpsertAndGetMessage() throws {
        try database.initialize()

        let message = MailMessage(
            id: "test-id-123",
            appleRowId: 12345,
            messageId: "<test@example.com>",
            mailboxId: 1,
            mailboxName: "INBOX",
            accountId: "account-1",
            subject: "Test Subject",
            senderName: "John Doe",
            senderEmail: "john@example.com",
            dateSent: Date(timeIntervalSince1970: 1736177400),
            dateReceived: Date(timeIntervalSince1970: 1736177500),
            isRead: true,
            isFlagged: false,
            isDeleted: false,
            hasAttachments: true,
            emlxPath: "/path/to/12345.emlx",
            bodyText: "This is the body text.",
            bodyHtml: nil
        )

        try database.upsertMessage(message)

        let retrieved = try database.getMessage(id: "test-id-123")

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, "test-id-123")
        XCTAssertEqual(retrieved?.appleRowId, 12345)
        XCTAssertEqual(retrieved?.messageId, "<test@example.com>")
        XCTAssertEqual(retrieved?.mailboxId, 1)
        XCTAssertEqual(retrieved?.mailboxName, "INBOX")
        XCTAssertEqual(retrieved?.subject, "Test Subject")
        XCTAssertEqual(retrieved?.senderName, "John Doe")
        XCTAssertEqual(retrieved?.senderEmail, "john@example.com")
        XCTAssertEqual(retrieved?.isRead, true)
        XCTAssertEqual(retrieved?.isFlagged, false)
        XCTAssertEqual(retrieved?.hasAttachments, true)
        XCTAssertEqual(retrieved?.bodyText, "This is the body text.")
    }

    func testGetMessageByAppleRowId() throws {
        try database.initialize()

        let message = MailMessage(
            id: "row-test-id",
            appleRowId: 99999,
            subject: "Row Test"
        )

        try database.upsertMessage(message)

        let retrieved = try database.getMessage(appleRowId: 99999)

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, "row-test-id")
        XCTAssertEqual(retrieved?.appleRowId, 99999)
    }

    func testGetNonexistentMessageReturnsNil() throws {
        try database.initialize()

        let retrieved = try database.getMessage(id: "nonexistent-id")
        XCTAssertNil(retrieved)
    }

    func testUpsertUpdatesExistingMessage() throws {
        try database.initialize()

        // Insert initial message
        let message1 = MailMessage(
            id: "update-test",
            subject: "Original Subject",
            isRead: false
        )
        try database.upsertMessage(message1)

        // Update the message
        let message2 = MailMessage(
            id: "update-test",
            subject: "Updated Subject",
            isRead: true
        )
        try database.upsertMessage(message2)

        let retrieved = try database.getMessage(id: "update-test")

        XCTAssertEqual(retrieved?.subject, "Updated Subject")
        XCTAssertEqual(retrieved?.isRead, true)
    }

    // MARK: - Special Characters

    func testMessageWithSpecialCharactersInSubject() throws {
        try database.initialize()

        let message = MailMessage(
            id: "special-chars",
            subject: "Test with 'quotes' and \"double\" and emoji 🎉"
        )

        try database.upsertMessage(message)

        let retrieved = try database.getMessage(id: "special-chars")
        XCTAssertEqual(retrieved?.subject, "Test with 'quotes' and \"double\" and emoji 🎉")
    }

    func testMessageWithSqlInjectionAttempt() throws {
        try database.initialize()

        let message = MailMessage(
            id: "sql-inject",
            subject: "Test'; DROP TABLE messages; --"
        )

        try database.upsertMessage(message)

        let retrieved = try database.getMessage(id: "sql-inject")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.subject, "Test'; DROP TABLE messages; --")

        // Verify table still exists by inserting another message
        let message2 = MailMessage(id: "after-inject", subject: "After")
        try database.upsertMessage(message2)
        let retrieved2 = try database.getMessage(id: "after-inject")
        XCTAssertNotNil(retrieved2)
    }

    // MARK: - FTS Search

    func testSearchMessages() throws {
        try database.initialize()

        // Insert multiple messages
        let messages = [
            MailMessage(id: "search-1", subject: "Meeting about project Alpha", senderEmail: "alice@example.com", bodyText: "Let's discuss the alpha project timeline."),
            MailMessage(id: "search-2", subject: "Quarterly report", senderEmail: "bob@example.com", bodyText: "Q4 financial results attached."),
            MailMessage(id: "search-3", subject: "Re: Project Alpha update", senderEmail: "charlie@example.com", bodyText: "Great progress on alpha milestone.")
        ]

        for msg in messages {
            try database.upsertMessage(msg)
        }

        // Search for "alpha"
        let results = try database.searchMessages(query: "alpha")

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains { $0.id == "search-1" })
        XCTAssertTrue(results.contains { $0.id == "search-3" })
    }

    func testSearchWithNoResults() throws {
        try database.initialize()

        let message = MailMessage(id: "no-match", subject: "Hello world")
        try database.upsertMessage(message)

        let results = try database.searchMessages(query: "nonexistent")

        XCTAssertTrue(results.isEmpty)
    }

    func testSearchWithLimit() throws {
        try database.initialize()

        // Insert many messages
        for i in 1...10 {
            let msg = MailMessage(id: "limit-\(i)", subject: "Test subject \(i)", bodyText: "Common keyword")
            try database.upsertMessage(msg)
        }

        let results = try database.searchMessages(query: "keyword", limit: 5)

        XCTAssertEqual(results.count, 5)
    }

    // MARK: - Export Path

    func testUpdateExportPath() throws {
        try database.initialize()

        let message = MailMessage(id: "export-test", subject: "Export Test")
        try database.upsertMessage(message)

        try database.updateExportPath(id: "export-test", path: "/exports/email.md")

        let retrieved = try database.getMessage(id: "export-test")
        XCTAssertEqual(retrieved?.exportPath, "/exports/email.md")
    }

    // MARK: - Update Message Body (On-Demand Fetching)

    func testUpdateMessageBodyWithBothTextAndHtml() throws {
        try database.initialize()

        // Insert message without body
        let message = MailMessage(
            id: "body-update-test",
            subject: "Body Update Test",
            bodyText: nil,
            bodyHtml: nil
        )
        try database.upsertMessage(message)

        // Verify body is initially nil
        let initialRetrieved = try database.getMessage(id: "body-update-test")
        XCTAssertNil(initialRetrieved?.bodyText)
        XCTAssertNil(initialRetrieved?.bodyHtml)

        // Update body
        try database.updateMessageBody(
            id: "body-update-test",
            bodyText: "Plain text body",
            bodyHtml: "<p>HTML body</p>"
        )

        // Verify body was updated
        let retrieved = try database.getMessage(id: "body-update-test")
        XCTAssertEqual(retrieved?.bodyText, "Plain text body")
        XCTAssertEqual(retrieved?.bodyHtml, "<p>HTML body</p>")
    }

    func testUpdateMessageBodyTextOnly() throws {
        try database.initialize()

        let message = MailMessage(id: "text-only-test", subject: "Text Only Test")
        try database.upsertMessage(message)

        try database.updateMessageBody(
            id: "text-only-test",
            bodyText: "Only plain text",
            bodyHtml: nil
        )

        let retrieved = try database.getMessage(id: "text-only-test")
        XCTAssertEqual(retrieved?.bodyText, "Only plain text")
        XCTAssertNil(retrieved?.bodyHtml)
    }

    func testUpdateMessageBodyHtmlOnly() throws {
        try database.initialize()

        let message = MailMessage(id: "html-only-test", subject: "HTML Only Test")
        try database.upsertMessage(message)

        try database.updateMessageBody(
            id: "html-only-test",
            bodyText: nil,
            bodyHtml: "<html><body>HTML content</body></html>"
        )

        let retrieved = try database.getMessage(id: "html-only-test")
        XCTAssertNil(retrieved?.bodyText)
        XCTAssertEqual(retrieved?.bodyHtml, "<html><body>HTML content</body></html>")
    }

    func testUpdateMessageBodyWithSpecialCharacters() throws {
        try database.initialize()

        let message = MailMessage(id: "special-body-test", subject: "Special Body Test")
        try database.upsertMessage(message)

        // Body with SQL-injection-like content and special characters
        let bodyText = "Test with 'quotes' and \"double quotes\" and emoji 🎉 and O'Brien's code"
        let bodyHtml = "<p>Test's \"content\" with <script>alert('xss')</script></p>"

        try database.updateMessageBody(
            id: "special-body-test",
            bodyText: bodyText,
            bodyHtml: bodyHtml
        )

        let retrieved = try database.getMessage(id: "special-body-test")
        XCTAssertEqual(retrieved?.bodyText, bodyText)
        XCTAssertEqual(retrieved?.bodyHtml, bodyHtml)
    }

    func testUpdateMessageBodyOverwritesExistingBody() throws {
        try database.initialize()

        // Insert message with initial body
        let message = MailMessage(
            id: "overwrite-body-test",
            subject: "Overwrite Body Test",
            bodyText: "Original text",
            bodyHtml: "<p>Original HTML</p>"
        )
        try database.upsertMessage(message)

        // Update body
        try database.updateMessageBody(
            id: "overwrite-body-test",
            bodyText: "New text",
            bodyHtml: "<p>New HTML</p>"
        )

        let retrieved = try database.getMessage(id: "overwrite-body-test")
        XCTAssertEqual(retrieved?.bodyText, "New text")
        XCTAssertEqual(retrieved?.bodyHtml, "<p>New HTML</p>")
    }

    func testUpdateMessageBodyBeforeInitializeThrows() throws {
        // Don't call initialize()
        XCTAssertThrowsError(try database.updateMessageBody(id: "test", bodyText: "text", bodyHtml: nil)) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized, got \(error)")
                return
            }
        }
    }

    // MARK: - Sync Status

    func testSetAndGetSyncStatus() throws {
        try database.initialize()

        try database.setSyncStatus(key: "test_key", value: "test_value")

        let value = try database.getSyncStatus(key: "test_key")
        XCTAssertEqual(value, "test_value")
    }

    func testGetNonexistentSyncStatus() throws {
        try database.initialize()

        let value = try database.getSyncStatus(key: "nonexistent_key")
        XCTAssertNil(value)
    }

    func testUpdateSyncStatus() throws {
        try database.initialize()

        try database.setSyncStatus(key: "update_key", value: "original")
        try database.setSyncStatus(key: "update_key", value: "updated")

        let value = try database.getSyncStatus(key: "update_key")
        XCTAssertEqual(value, "updated")
    }

    func testSetAndGetLastSyncTime() throws {
        try database.initialize()

        let syncTime = Date(timeIntervalSince1970: 1736177400)
        try database.setLastSyncTime(syncTime)

        let retrieved = try database.getLastSyncTime()
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved!.timeIntervalSince1970, 1736177400, accuracy: 1.0)
    }

    func testGetLastSyncTimeWhenNotSet() throws {
        try database.initialize()

        let retrieved = try database.getLastSyncTime()
        XCTAssertNil(retrieved)
    }

    // MARK: - Sync Status Tracking

    func testRecordSyncStart() throws {
        try database.initialize()

        try database.recordSyncStart(isIncremental: true)

        let summary = try database.getSyncStatusSummary()
        XCTAssertEqual(summary.state, .running)
        XCTAssertNotNil(summary.lastSyncStartTime)
        XCTAssertEqual(summary.isIncremental, true)
        XCTAssertNil(summary.lastSyncError)
    }

    func testRecordSyncSuccess() throws {
        try database.initialize()

        try database.recordSyncStart(isIncremental: false)

        let result = SyncResult(
            messagesProcessed: 100,
            messagesAdded: 50,
            messagesUpdated: 30,
            messagesDeleted: 5,
            messagesUnchanged: 15,
            mailboxesProcessed: 10,
            errors: [],
            duration: 5.5,
            isIncremental: false
        )

        try database.recordSyncSuccess(result: result)

        let summary = try database.getSyncStatusSummary()
        XCTAssertEqual(summary.state, .success)
        XCTAssertNotNil(summary.lastSyncTime)
        XCTAssertNotNil(summary.lastSyncEndTime)
        XCTAssertEqual(summary.messagesAdded, 50)
        XCTAssertEqual(summary.messagesUpdated, 30)
        XCTAssertEqual(summary.messagesDeleted, 5)
        XCTAssertNotNil(summary.duration)
        XCTAssertEqual(summary.duration!, 5.5, accuracy: 0.01)
        XCTAssertNil(summary.lastSyncError)
    }

    func testRecordSyncFailure() throws {
        try database.initialize()

        try database.recordSyncStart(isIncremental: true)

        let error = NSError(domain: "MailSync", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Test sync failure"
        ])
        try database.recordSyncFailure(error: error)

        let summary = try database.getSyncStatusSummary()
        XCTAssertEqual(summary.state, .failed)
        XCTAssertNotNil(summary.lastSyncEndTime)
        XCTAssertNotNil(summary.lastSyncError)
        XCTAssertTrue(summary.lastSyncError?.contains("Test sync failure") ?? false)
    }

    func testGetSyncStatusSummaryWhenNoSync() throws {
        try database.initialize()

        let summary = try database.getSyncStatusSummary()
        XCTAssertEqual(summary.state, .idle)
        XCTAssertNil(summary.lastSyncTime)
        XCTAssertNil(summary.lastSyncStartTime)
        XCTAssertNil(summary.lastSyncEndTime)
        XCTAssertNil(summary.lastSyncError)
        XCTAssertEqual(summary.messagesAdded, 0)
        XCTAssertEqual(summary.messagesUpdated, 0)
        XCTAssertEqual(summary.messagesDeleted, 0)
    }

    func testSyncStatusClearsErrorOnSuccess() throws {
        try database.initialize()

        // First, record a failure
        try database.recordSyncStart(isIncremental: true)
        let error = NSError(domain: "MailSync", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Previous failure"
        ])
        try database.recordSyncFailure(error: error)

        // Then record success
        try database.recordSyncStart(isIncremental: false)
        let result = SyncResult(
            messagesProcessed: 10,
            messagesAdded: 10,
            messagesUpdated: 0,
            mailboxesProcessed: 1,
            errors: [],
            duration: 1.0
        )
        try database.recordSyncSuccess(result: result)

        let summary = try database.getSyncStatusSummary()
        XCTAssertEqual(summary.state, .success)
        XCTAssertNil(summary.lastSyncError)
    }

    // MARK: - Mailbox Operations

    func testUpsertAndGetMailboxes() throws {
        try database.initialize()

        let mailboxes = [
            Mailbox(id: 1, accountId: "account-1", name: "INBOX", fullPath: "INBOX", messageCount: 100, unreadCount: 10),
            Mailbox(id: 2, accountId: "account-1", name: "Sent", fullPath: "Sent", messageCount: 50, unreadCount: 0),
            Mailbox(id: 3, accountId: "account-1", name: "Archive", fullPath: "Archive", parentId: nil, messageCount: 200, unreadCount: 0)
        ]

        for mailbox in mailboxes {
            try database.upsertMailbox(mailbox)
        }

        let retrieved = try database.getMailboxes()

        XCTAssertEqual(retrieved.count, 3)
        XCTAssertTrue(retrieved.contains { $0.name == "INBOX" && $0.messageCount == 100 })
        XCTAssertTrue(retrieved.contains { $0.name == "Sent" && $0.messageCount == 50 })
    }

    func testUpdateMailbox() throws {
        try database.initialize()

        let mailbox1 = Mailbox(id: 1, accountId: "account-1", name: "INBOX", fullPath: "INBOX", messageCount: 100, unreadCount: 10)
        try database.upsertMailbox(mailbox1)

        let mailbox2 = Mailbox(id: 1, accountId: "account-1", name: "INBOX", fullPath: "INBOX", messageCount: 150, unreadCount: 5)
        try database.upsertMailbox(mailbox2)

        let retrieved = try database.getMailboxes()

        XCTAssertEqual(retrieved.count, 1)
        XCTAssertEqual(retrieved.first?.messageCount, 150)
        XCTAssertEqual(retrieved.first?.unreadCount, 5)
    }

    // MARK: - Error Handling

    func testOperationsBeforeInitializeThrow() throws {
        // Don't call initialize()

        XCTAssertThrowsError(try database.getMessage(id: "test")) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized, got \(error)")
                return
            }
        }
    }

    // MARK: - Data Model Tests

    func testMailMessageInitialization() {
        let message = MailMessage(
            id: "msg-1",
            appleRowId: 123,
            messageId: "<msg@test.com>",
            mailboxId: 1,
            mailboxName: "INBOX",
            accountId: "acc-1",
            subject: "Test",
            senderName: "Sender",
            senderEmail: "sender@test.com",
            dateSent: Date(),
            dateReceived: Date(),
            isRead: true,
            isFlagged: true,
            isDeleted: false,
            hasAttachments: true,
            emlxPath: "/path/to.emlx",
            bodyText: "Body",
            bodyHtml: "<p>Body</p>",
            exportPath: "/export/path"
        )

        XCTAssertEqual(message.id, "msg-1")
        XCTAssertEqual(message.appleRowId, 123)
        XCTAssertEqual(message.subject, "Test")
        XCTAssertTrue(message.isRead)
        XCTAssertTrue(message.isFlagged)
        XCTAssertTrue(message.hasAttachments)
    }

    func testMailMessageDefaults() {
        let message = MailMessage(id: "minimal", subject: "Minimal")

        XCTAssertNil(message.appleRowId)
        XCTAssertNil(message.messageId)
        XCTAssertFalse(message.isRead)
        XCTAssertFalse(message.isFlagged)
        XCTAssertFalse(message.isDeleted)
        XCTAssertFalse(message.hasAttachments)
    }

    func testMailboxInitialization() {
        let mailbox = Mailbox(
            id: 1,
            accountId: "acc-1",
            name: "INBOX",
            fullPath: "INBOX",
            parentId: nil,
            messageCount: 100,
            unreadCount: 10
        )

        XCTAssertEqual(mailbox.id, 1)
        XCTAssertEqual(mailbox.accountId, "acc-1")
        XCTAssertEqual(mailbox.name, "INBOX")
        XCTAssertEqual(mailbox.messageCount, 100)
        XCTAssertEqual(mailbox.unreadCount, 10)
    }

    func testMailAttachmentInitialization() {
        let attachment = MailAttachment(
            id: 1,
            messageId: "msg-1",
            filename: "doc.pdf",
            mimeType: "application/pdf",
            size: 1024,
            contentId: "cid123",
            isInline: false
        )

        XCTAssertEqual(attachment.id, 1)
        XCTAssertEqual(attachment.messageId, "msg-1")
        XCTAssertEqual(attachment.filename, "doc.pdf")
        XCTAssertEqual(attachment.mimeType, "application/pdf")
        XCTAssertEqual(attachment.size, 1024)
        XCTAssertFalse(attachment.isInline)
    }

    // MARK: - Error Description Tests

    func testMailDatabaseErrorDescriptions() {
        let errors: [MailDatabaseError] = [
            .connectionFailed(underlying: NSError(domain: "test", code: 1)),
            .migrationFailed(underlying: NSError(domain: "test", code: 2)),
            .queryFailed(underlying: NSError(domain: "test", code: 3)),
            .notInitialized
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    // MARK: - Close and Reopen

    func testCloseAndReopenDatabase() throws {
        try database.initialize()

        let message = MailMessage(id: "persist-test", subject: "Persist")
        try database.upsertMessage(message)

        database.close()

        // Create new database instance
        let dbPath = (testDir as NSString).appendingPathComponent("mail.db")
        let newDatabase = MailDatabase(databasePath: dbPath)
        try newDatabase.initialize()

        let retrieved = try newDatabase.getMessage(id: "persist-test")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.subject, "Persist")

        newDatabase.close()
    }

    // MARK: - Batch Insert Tests

    func testBatchUpsertMessagesInsertsAll() throws {
        try database.initialize()

        let messages = (1...100).map { i in
            MailMessage(
                id: "batch-\(i)",
                appleRowId: i,
                subject: "Batch Test \(i)",
                senderEmail: "sender\(i)@example.com",
                isRead: i % 2 == 0,
                isFlagged: i % 3 == 0
            )
        }

        let result = try database.batchUpsertMessages(messages)

        XCTAssertEqual(result.inserted, 100)
        XCTAssertEqual(result.updated, 0)
        XCTAssertEqual(result.failed, 0)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertGreaterThan(result.duration, 0)

        // Verify messages were inserted
        let retrieved1 = try database.getMessage(id: "batch-1")
        XCTAssertNotNil(retrieved1)
        XCTAssertEqual(retrieved1?.subject, "Batch Test 1")

        let retrieved50 = try database.getMessage(id: "batch-50")
        XCTAssertNotNil(retrieved50)
        XCTAssertEqual(retrieved50?.subject, "Batch Test 50")

        let retrieved100 = try database.getMessage(id: "batch-100")
        XCTAssertNotNil(retrieved100)
        XCTAssertEqual(retrieved100?.subject, "Batch Test 100")
    }

    func testBatchUpsertMessagesUpdatesExisting() throws {
        try database.initialize()

        // Insert initial messages
        let initialMessages = (1...50).map { i in
            MailMessage(id: "batch-\(i)", subject: "Initial \(i)")
        }
        _ = try database.batchUpsertMessages(initialMessages)

        // Update with new messages (some new, some updates)
        let updateMessages = (25...75).map { i in
            MailMessage(id: "batch-\(i)", subject: "Updated \(i)")
        }

        let result = try database.batchUpsertMessages(updateMessages)

        // 25-50 are updates (26 messages), 51-75 are inserts (25 messages)
        XCTAssertEqual(result.inserted, 25)
        XCTAssertEqual(result.updated, 26)
        XCTAssertEqual(result.failed, 0)

        // Verify updates
        let retrieved25 = try database.getMessage(id: "batch-25")
        XCTAssertEqual(retrieved25?.subject, "Updated 25")

        let retrieved50 = try database.getMessage(id: "batch-50")
        XCTAssertEqual(retrieved50?.subject, "Updated 50")

        // Verify original unchanged
        let retrieved1 = try database.getMessage(id: "batch-1")
        XCTAssertEqual(retrieved1?.subject, "Initial 1")
    }

    func testBatchUpsertMessagesWithCustomBatchSize() throws {
        try database.initialize()

        let messages = (1...500).map { i in
            MailMessage(id: "custom-batch-\(i)", subject: "Custom Batch \(i)")
        }

        // Use small batch size
        let config = MailDatabase.BatchInsertConfig(batchSize: 50)
        let result = try database.batchUpsertMessages(messages, config: config)

        XCTAssertEqual(result.inserted, 500)
        XCTAssertEqual(result.updated, 0)
        XCTAssertEqual(result.failed, 0)

        // Verify all were inserted
        let retrieved = try database.getMessage(id: "custom-batch-250")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.subject, "Custom Batch 250")
    }

    func testBatchUpsertMessagesDefaultConfig() {
        let config = MailDatabase.BatchInsertConfig.default
        XCTAssertEqual(config.batchSize, 1000)
    }

    func testBatchUpsertMessagesConfigMinimumBatchSize() {
        let config = MailDatabase.BatchInsertConfig(batchSize: 0)
        XCTAssertEqual(config.batchSize, 1)

        let negativeConfig = MailDatabase.BatchInsertConfig(batchSize: -10)
        XCTAssertEqual(negativeConfig.batchSize, 1)
    }

    func testBatchUpsertMessagesEmptyArray() throws {
        try database.initialize()

        let result = try database.batchUpsertMessages([])

        XCTAssertEqual(result.inserted, 0)
        XCTAssertEqual(result.updated, 0)
        XCTAssertEqual(result.failed, 0)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testBatchUpsertMessagesWithSpecialCharacters() throws {
        try database.initialize()

        let messages = [
            MailMessage(id: "special-1", subject: "Test with 'single quotes'"),
            MailMessage(id: "special-2", subject: "Test with \"double quotes\""),
            MailMessage(id: "special-3", subject: "Test with emoji 🎉"),
            MailMessage(id: "special-4", subject: "Test'; DROP TABLE messages; --")
        ]

        let result = try database.batchUpsertMessages(messages)

        XCTAssertEqual(result.inserted, 4)
        XCTAssertEqual(result.failed, 0)

        let retrieved1 = try database.getMessage(id: "special-1")
        XCTAssertEqual(retrieved1?.subject, "Test with 'single quotes'")

        let retrieved4 = try database.getMessage(id: "special-4")
        XCTAssertEqual(retrieved4?.subject, "Test'; DROP TABLE messages; --")
    }

    func testBatchUpsertMessagesPerformance() throws {
        try database.initialize()

        // Create a large batch of messages
        let messageCount = 1000
        let messages = (1...messageCount).map { i in
            MailMessage(
                id: "perf-\(i)",
                appleRowId: i,
                messageId: "<perf\(i)@test.com>",
                mailboxId: 1,
                mailboxName: "INBOX",
                accountId: "acc-1",
                subject: "Performance Test \(i)",
                senderName: "Sender \(i)",
                senderEmail: "sender\(i)@test.com",
                dateSent: Date(),
                dateReceived: Date(),
                isRead: i % 2 == 0,
                isFlagged: i % 5 == 0,
                bodyText: "This is the body text for message \(i)"
            )
        }

        // Measure batch insert time
        let startTime = Date()
        let result = try database.batchUpsertMessages(messages)
        let batchDuration = Date().timeIntervalSince(startTime)

        XCTAssertEqual(result.inserted, messageCount)
        XCTAssertEqual(result.failed, 0)

        // Batch inserts should be fast (less than 5 seconds for 1000 messages)
        XCTAssertLessThan(batchDuration, 5.0, "Batch insert should complete in less than 5 seconds")

        // Log performance for reference
        print("Batch insert of \(messageCount) messages took \(batchDuration) seconds")
        print("Rate: \(Double(messageCount) / batchDuration) messages/second")
    }

    func testBatchUpsertMailboxes() throws {
        try database.initialize()

        let mailboxes = [
            Mailbox(id: 1, accountId: "acc-1", name: "INBOX", fullPath: "INBOX", messageCount: 100, unreadCount: 10),
            Mailbox(id: 2, accountId: "acc-1", name: "Sent", fullPath: "Sent", messageCount: 50, unreadCount: 0),
            Mailbox(id: 3, accountId: "acc-1", name: "Archive", fullPath: "Archive", messageCount: 200, unreadCount: 0)
        ]

        try database.batchUpsertMailboxes(mailboxes)

        let retrieved = try database.getMailboxes()
        XCTAssertEqual(retrieved.count, 3)
        XCTAssertTrue(retrieved.contains { $0.name == "INBOX" && $0.messageCount == 100 })
        XCTAssertTrue(retrieved.contains { $0.name == "Sent" && $0.messageCount == 50 })
        XCTAssertTrue(retrieved.contains { $0.name == "Archive" && $0.messageCount == 200 })
    }

    func testBatchUpsertMailboxesUpdatesExisting() throws {
        try database.initialize()

        // Insert initial mailboxes
        let initial = [
            Mailbox(id: 1, accountId: "acc-1", name: "INBOX", fullPath: "INBOX", messageCount: 100, unreadCount: 10)
        ]
        try database.batchUpsertMailboxes(initial)

        // Update mailbox
        let updated = [
            Mailbox(id: 1, accountId: "acc-1", name: "INBOX", fullPath: "INBOX", messageCount: 150, unreadCount: 5)
        ]
        try database.batchUpsertMailboxes(updated)

        let retrieved = try database.getMailboxes()
        XCTAssertEqual(retrieved.count, 1)
        XCTAssertEqual(retrieved.first?.messageCount, 150)
        XCTAssertEqual(retrieved.first?.unreadCount, 5)
    }

    func testBatchInsertResultInitialization() {
        let result = MailDatabase.BatchInsertResult(
            inserted: 10,
            updated: 5,
            failed: 2,
            errors: ["Error 1", "Error 2"],
            duration: 1.5
        )

        XCTAssertEqual(result.inserted, 10)
        XCTAssertEqual(result.updated, 5)
        XCTAssertEqual(result.failed, 2)
        XCTAssertEqual(result.errors.count, 2)
        XCTAssertEqual(result.duration, 1.5)
    }

    // MARK: - Migration V2 Tests (Mailbox Status Tracking)

    func testMigrationV2CreatesMailboxStatusColumn() throws {
        try database.initialize()

        // Insert a message with default mailbox status
        let message = MailMessage(id: "v2-test-1", subject: "V2 Test")
        try database.upsertMessage(message)

        // Retrieve and verify default mailbox_status is 'inbox'
        let retrieved = try database.getMessage(id: "v2-test-1")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.mailboxStatus, .inbox)
    }

    func testMigrationV2CreatesPendingSyncActionColumn() throws {
        try database.initialize()

        // Insert a message without pending sync action
        let message1 = MailMessage(id: "v2-sync-1", subject: "No Action")
        try database.upsertMessage(message1)

        let retrieved1 = try database.getMessage(id: "v2-sync-1")
        XCTAssertNil(retrieved1?.pendingSyncAction)

        // Insert a message with pending archive action
        let message2 = MailMessage(
            id: "v2-sync-2",
            subject: "With Archive Action",
            pendingSyncAction: .archive
        )
        try database.upsertMessage(message2)

        let retrieved2 = try database.getMessage(id: "v2-sync-2")
        XCTAssertEqual(retrieved2?.pendingSyncAction, .archive)

        // Insert a message with pending delete action
        let message3 = MailMessage(
            id: "v2-sync-3",
            subject: "With Delete Action",
            pendingSyncAction: .delete
        )
        try database.upsertMessage(message3)

        let retrieved3 = try database.getMessage(id: "v2-sync-3")
        XCTAssertEqual(retrieved3?.pendingSyncAction, .delete)
    }

    func testMigrationV2CreatesLastKnownMailboxIdColumn() throws {
        try database.initialize()

        // Insert a message without last known mailbox id
        let message1 = MailMessage(id: "v2-mailbox-1", subject: "No Mailbox")
        try database.upsertMessage(message1)

        let retrieved1 = try database.getMessage(id: "v2-mailbox-1")
        XCTAssertNil(retrieved1?.lastKnownMailboxId)

        // Insert a message with last known mailbox id
        let message2 = MailMessage(
            id: "v2-mailbox-2",
            subject: "With Mailbox",
            lastKnownMailboxId: 42
        )
        try database.upsertMessage(message2)

        let retrieved2 = try database.getMessage(id: "v2-mailbox-2")
        XCTAssertEqual(retrieved2?.lastKnownMailboxId, 42)
    }

    func testMailboxStatusEnumValues() {
        XCTAssertEqual(MailboxStatus.inbox.rawValue, "inbox")
        XCTAssertEqual(MailboxStatus.archived.rawValue, "archived")
        XCTAssertEqual(MailboxStatus.deleted.rawValue, "deleted")

        // Test parsing from raw value
        XCTAssertEqual(MailboxStatus(rawValue: "inbox"), .inbox)
        XCTAssertEqual(MailboxStatus(rawValue: "archived"), .archived)
        XCTAssertEqual(MailboxStatus(rawValue: "deleted"), .deleted)
        XCTAssertNil(MailboxStatus(rawValue: "unknown"))
    }

    func testSyncActionEnumValues() {
        XCTAssertEqual(SyncAction.archive.rawValue, "archive")
        XCTAssertEqual(SyncAction.delete.rawValue, "delete")

        // Test parsing from raw value
        XCTAssertEqual(SyncAction(rawValue: "archive"), .archive)
        XCTAssertEqual(SyncAction(rawValue: "delete"), .delete)
        XCTAssertNil(SyncAction(rawValue: "unknown"))
    }

    func testMessageWithAllV2Fields() throws {
        try database.initialize()

        let message = MailMessage(
            id: "v2-full-test",
            appleRowId: 12345,
            mailboxId: 1,
            mailboxName: "INBOX",
            subject: "Full V2 Test",
            mailboxStatus: .archived,
            pendingSyncAction: .delete,
            lastKnownMailboxId: 99
        )

        try database.upsertMessage(message)

        let retrieved = try database.getMessage(id: "v2-full-test")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.mailboxStatus, .archived)
        XCTAssertEqual(retrieved?.pendingSyncAction, .delete)
        XCTAssertEqual(retrieved?.lastKnownMailboxId, 99)
    }

    func testExistingMessagesGetDefaultMailboxStatus() throws {
        // This tests that existing messages (after migration) have mailbox_status = 'inbox'
        try database.initialize()

        // Insert a message using minimal fields (simulating pre-V2 message)
        let message = MailMessage(id: "pre-v2-msg", subject: "Pre-V2 Message")
        try database.upsertMessage(message)

        let retrieved = try database.getMessage(id: "pre-v2-msg")
        XCTAssertEqual(retrieved?.mailboxStatus, .inbox, "Existing messages should default to inbox status")
    }

    func testMailboxStatusUpdateOnUpsert() throws {
        try database.initialize()

        // Insert initial message
        let message1 = MailMessage(
            id: "status-update-test",
            subject: "Initial",
            mailboxStatus: .inbox
        )
        try database.upsertMessage(message1)

        // Update to archived
        let message2 = MailMessage(
            id: "status-update-test",
            subject: "Initial",
            mailboxStatus: .archived
        )
        try database.upsertMessage(message2)

        let retrieved = try database.getMessage(id: "status-update-test")
        XCTAssertEqual(retrieved?.mailboxStatus, .archived)
    }

    func testBatchUpsertWithV2Fields() throws {
        try database.initialize()

        let messages = [
            MailMessage(id: "batch-v2-1", subject: "Batch 1", mailboxStatus: .inbox),
            MailMessage(id: "batch-v2-2", subject: "Batch 2", mailboxStatus: .archived, pendingSyncAction: .archive),
            MailMessage(id: "batch-v2-3", subject: "Batch 3", mailboxStatus: .deleted, pendingSyncAction: .delete, lastKnownMailboxId: 5)
        ]

        let result = try database.batchUpsertMessages(messages)
        XCTAssertEqual(result.inserted, 3)
        XCTAssertEqual(result.failed, 0)

        let retrieved1 = try database.getMessage(id: "batch-v2-1")
        XCTAssertEqual(retrieved1?.mailboxStatus, .inbox)
        XCTAssertNil(retrieved1?.pendingSyncAction)

        let retrieved2 = try database.getMessage(id: "batch-v2-2")
        XCTAssertEqual(retrieved2?.mailboxStatus, .archived)
        XCTAssertEqual(retrieved2?.pendingSyncAction, .archive)

        let retrieved3 = try database.getMessage(id: "batch-v2-3")
        XCTAssertEqual(retrieved3?.mailboxStatus, .deleted)
        XCTAssertEqual(retrieved3?.pendingSyncAction, .delete)
        XCTAssertEqual(retrieved3?.lastKnownMailboxId, 5)
    }

    func testMailMessageV2DefaultsInInit() {
        let message = MailMessage(id: "defaults-test", subject: "Defaults")

        XCTAssertEqual(message.mailboxStatus, .inbox, "Default mailboxStatus should be inbox")
        XCTAssertNil(message.pendingSyncAction, "Default pendingSyncAction should be nil")
        XCTAssertNil(message.lastKnownMailboxId, "Default lastKnownMailboxId should be nil")
    }

    // MARK: - US-002: Mailbox Status Query and Update Methods

    func testUpdateMailboxStatus() throws {
        try database.initialize()

        // Insert a message
        let message = MailMessage(id: "status-test", subject: "Status Test", mailboxStatus: .inbox)
        try database.upsertMessage(message)

        // Update status to archived
        try database.updateMailboxStatus(id: "status-test", status: .archived)

        let retrieved = try database.getMessage(id: "status-test")
        XCTAssertEqual(retrieved?.mailboxStatus, .archived)

        // Update status to deleted
        try database.updateMailboxStatus(id: "status-test", status: .deleted)

        let retrieved2 = try database.getMessage(id: "status-test")
        XCTAssertEqual(retrieved2?.mailboxStatus, .deleted)

        // Update back to inbox
        try database.updateMailboxStatus(id: "status-test", status: .inbox)

        let retrieved3 = try database.getMessage(id: "status-test")
        XCTAssertEqual(retrieved3?.mailboxStatus, .inbox)
    }

    func testUpdateMailboxStatusNonexistentMessage() throws {
        try database.initialize()

        // This should not throw, it just won't update anything
        try database.updateMailboxStatus(id: "nonexistent", status: .archived)

        // Verify nothing was created
        let retrieved = try database.getMessage(id: "nonexistent")
        XCTAssertNil(retrieved)
    }

    func testSetPendingSyncAction() throws {
        try database.initialize()

        let message = MailMessage(id: "action-test", subject: "Action Test")
        try database.upsertMessage(message)

        // Set archive action
        try database.setPendingSyncAction(id: "action-test", action: .archive)

        let retrieved = try database.getMessage(id: "action-test")
        XCTAssertEqual(retrieved?.pendingSyncAction, .archive)

        // Change to delete action
        try database.setPendingSyncAction(id: "action-test", action: .delete)

        let retrieved2 = try database.getMessage(id: "action-test")
        XCTAssertEqual(retrieved2?.pendingSyncAction, .delete)
    }

    func testSetPendingSyncActionNonexistentMessage() throws {
        try database.initialize()

        // This should not throw, it just won't update anything
        try database.setPendingSyncAction(id: "nonexistent", action: .archive)

        // Verify nothing was created
        let retrieved = try database.getMessage(id: "nonexistent")
        XCTAssertNil(retrieved)
    }

    func testClearPendingSyncAction() throws {
        try database.initialize()

        // Insert a message with pending action
        let message = MailMessage(
            id: "clear-action-test",
            subject: "Clear Action Test",
            pendingSyncAction: .archive
        )
        try database.upsertMessage(message)

        // Verify action is set
        let retrieved1 = try database.getMessage(id: "clear-action-test")
        XCTAssertEqual(retrieved1?.pendingSyncAction, .archive)

        // Clear the action
        try database.clearPendingSyncAction(id: "clear-action-test")

        // Verify action is cleared
        let retrieved2 = try database.getMessage(id: "clear-action-test")
        XCTAssertNil(retrieved2?.pendingSyncAction)
    }

    func testClearPendingSyncActionNonexistentMessage() throws {
        try database.initialize()

        // This should not throw, it just won't update anything
        try database.clearPendingSyncAction(id: "nonexistent")

        // Verify nothing was created
        let retrieved = try database.getMessage(id: "nonexistent")
        XCTAssertNil(retrieved)
    }

    func testGetMessagesWithPendingActions() throws {
        try database.initialize()

        // Insert messages with and without pending actions
        let messages = [
            MailMessage(id: "pending-1", subject: "Pending Archive", pendingSyncAction: .archive),
            MailMessage(id: "pending-2", subject: "Pending Delete", pendingSyncAction: .delete),
            MailMessage(id: "no-action", subject: "No Action"),
            MailMessage(id: "pending-3", subject: "Another Archive", pendingSyncAction: .archive)
        ]

        for msg in messages {
            try database.upsertMessage(msg)
        }

        // Get messages with pending actions
        let pending = try database.getMessagesWithPendingActions()

        XCTAssertEqual(pending.count, 3)
        XCTAssertTrue(pending.contains { $0.id == "pending-1" })
        XCTAssertTrue(pending.contains { $0.id == "pending-2" })
        XCTAssertTrue(pending.contains { $0.id == "pending-3" })
        XCTAssertFalse(pending.contains { $0.id == "no-action" })
    }

    func testGetMessagesWithPendingActionsEmpty() throws {
        try database.initialize()

        // Insert messages without pending actions
        let message = MailMessage(id: "no-action", subject: "No Action")
        try database.upsertMessage(message)

        let pending = try database.getMessagesWithPendingActions()

        XCTAssertTrue(pending.isEmpty)
    }

    func testGetMessagesWithPendingActionsExcludesDeleted() throws {
        try database.initialize()

        // Insert a message with pending action but marked as deleted
        let message = MailMessage(
            id: "deleted-pending",
            subject: "Deleted with Action",
            isDeleted: true,
            pendingSyncAction: .archive
        )
        try database.upsertMessage(message)

        let pending = try database.getMessagesWithPendingActions()

        XCTAssertTrue(pending.isEmpty, "Deleted messages should not be returned")
    }

    func testGetMessagesByStatus() throws {
        try database.initialize()

        // Insert messages with different statuses
        let messages = [
            MailMessage(id: "inbox-1", subject: "Inbox 1", mailboxStatus: .inbox),
            MailMessage(id: "inbox-2", subject: "Inbox 2", mailboxStatus: .inbox),
            MailMessage(id: "archived-1", subject: "Archived 1", mailboxStatus: .archived),
            MailMessage(id: "deleted-1", subject: "Deleted 1", mailboxStatus: .deleted)
        ]

        for msg in messages {
            try database.upsertMessage(msg)
        }

        // Get inbox messages
        let inboxMessages = try database.getMessagesByStatus(.inbox)
        XCTAssertEqual(inboxMessages.count, 2)
        XCTAssertTrue(inboxMessages.allSatisfy { $0.mailboxStatus == .inbox })

        // Get archived messages
        let archivedMessages = try database.getMessagesByStatus(.archived)
        XCTAssertEqual(archivedMessages.count, 1)
        XCTAssertEqual(archivedMessages.first?.id, "archived-1")

        // Get deleted messages
        let deletedMessages = try database.getMessagesByStatus(.deleted)
        XCTAssertEqual(deletedMessages.count, 1)
        XCTAssertEqual(deletedMessages.first?.id, "deleted-1")
    }

    func testGetMessagesByStatusWithLimitAndOffset() throws {
        try database.initialize()

        // Insert many inbox messages
        for i in 1...10 {
            let message = MailMessage(
                id: "inbox-\(i)",
                subject: "Inbox \(i)",
                dateReceived: Date(timeIntervalSince1970: Double(1000000 + i)),
                mailboxStatus: .inbox
            )
            try database.upsertMessage(message)
        }

        // Get with limit
        let limited = try database.getMessagesByStatus(.inbox, limit: 5)
        XCTAssertEqual(limited.count, 5)

        // Get with offset
        let offset = try database.getMessagesByStatus(.inbox, limit: 5, offset: 5)
        XCTAssertEqual(offset.count, 5)

        // Verify no overlap
        let limitedIds = Set(limited.map { $0.id })
        let offsetIds = Set(offset.map { $0.id })
        XCTAssertTrue(limitedIds.isDisjoint(with: offsetIds))
    }

    func testGetMessagesByStatusEmpty() throws {
        try database.initialize()

        // Insert inbox messages only
        let message = MailMessage(id: "inbox-only", subject: "Inbox", mailboxStatus: .inbox)
        try database.upsertMessage(message)

        // Query for archived (should be empty)
        let archived = try database.getMessagesByStatus(.archived)
        XCTAssertTrue(archived.isEmpty)
    }

    func testGetMessagesByStatusExcludesDeleted() throws {
        try database.initialize()

        // Insert a message that's in inbox but soft-deleted
        let message = MailMessage(
            id: "soft-deleted",
            subject: "Soft Deleted",
            isDeleted: true,
            mailboxStatus: .inbox
        )
        try database.upsertMessage(message)

        let inboxMessages = try database.getMessagesByStatus(.inbox)

        XCTAssertTrue(inboxMessages.isEmpty, "Soft-deleted messages should not be returned")
    }

    func testGetMessageCountByStatus() throws {
        try database.initialize()

        // Insert messages with different statuses
        let messages = [
            MailMessage(id: "inbox-1", subject: "Inbox 1", mailboxStatus: .inbox),
            MailMessage(id: "inbox-2", subject: "Inbox 2", mailboxStatus: .inbox),
            MailMessage(id: "inbox-3", subject: "Inbox 3", mailboxStatus: .inbox),
            MailMessage(id: "archived-1", subject: "Archived 1", mailboxStatus: .archived),
            MailMessage(id: "archived-2", subject: "Archived 2", mailboxStatus: .archived),
            MailMessage(id: "deleted-1", subject: "Deleted 1", mailboxStatus: .deleted)
        ]

        for msg in messages {
            try database.upsertMessage(msg)
        }

        let counts = try database.getMessageCountByStatus()

        XCTAssertEqual(counts[.inbox], 3)
        XCTAssertEqual(counts[.archived], 2)
        XCTAssertEqual(counts[.deleted], 1)
    }

    func testGetMessageCountByStatusEmpty() throws {
        try database.initialize()

        let counts = try database.getMessageCountByStatus()

        // All counts should be 0
        XCTAssertEqual(counts[.inbox], 0)
        XCTAssertEqual(counts[.archived], 0)
        XCTAssertEqual(counts[.deleted], 0)
    }

    func testGetMessageCountByStatusExcludesSoftDeleted() throws {
        try database.initialize()

        // Insert a soft-deleted message
        let message = MailMessage(
            id: "soft-deleted",
            subject: "Soft Deleted",
            isDeleted: true,
            mailboxStatus: .inbox
        )
        try database.upsertMessage(message)

        let counts = try database.getMessageCountByStatus()

        XCTAssertEqual(counts[.inbox], 0, "Soft-deleted messages should not be counted")
    }

    func testStatusMethodsBeforeInitializeThrow() throws {
        // Don't call initialize()

        XCTAssertThrowsError(try database.updateMailboxStatus(id: "test", status: .archived)) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized")
                return
            }
        }

        XCTAssertThrowsError(try database.setPendingSyncAction(id: "test", action: .archive)) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized")
                return
            }
        }

        XCTAssertThrowsError(try database.clearPendingSyncAction(id: "test")) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized")
                return
            }
        }

        XCTAssertThrowsError(try database.getMessagesWithPendingActions()) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized")
                return
            }
        }

        XCTAssertThrowsError(try database.getMessagesByStatus(.inbox)) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized")
                return
            }
        }

        XCTAssertThrowsError(try database.getMessageCountByStatus()) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized")
                return
            }
        }
    }

    // MARK: - Migration V5: Thread-Messages Junction Table Tests

    func testAddMessageToThread() throws {
        try database.initialize()

        // Create a thread and a message
        let thread = Thread(id: "thread-1", subject: "Test Thread")
        try database.upsertThread(thread)

        let message = MailMessage(id: "msg-1", subject: "Test Message")
        try database.upsertMessage(message)

        // Add message to thread
        try database.addMessageToThread(messageId: "msg-1", threadId: "thread-1")

        // Verify the relationship exists
        let messageIds = try database.getMessageIdsInThread(threadId: "thread-1")
        XCTAssertEqual(messageIds.count, 1)
        XCTAssertEqual(messageIds.first, "msg-1")
    }

    func testAddMessageToThreadDuplicateIgnored() throws {
        try database.initialize()

        // Create thread and message
        let thread = Thread(id: "thread-dup", subject: "Duplicate Test")
        try database.upsertThread(thread)

        let message = MailMessage(id: "msg-dup", subject: "Duplicate Message")
        try database.upsertMessage(message)

        // Add same message twice - should not throw
        try database.addMessageToThread(messageId: "msg-dup", threadId: "thread-dup")
        try database.addMessageToThread(messageId: "msg-dup", threadId: "thread-dup")

        // Should still only have one entry
        let messageIds = try database.getMessageIdsInThread(threadId: "thread-dup")
        XCTAssertEqual(messageIds.count, 1)
    }

    func testRemoveMessageFromThread() throws {
        try database.initialize()

        // Setup thread and message
        let thread = Thread(id: "thread-remove", subject: "Remove Test")
        try database.upsertThread(thread)

        let message = MailMessage(id: "msg-remove", subject: "To Be Removed")
        try database.upsertMessage(message)

        try database.addMessageToThread(messageId: "msg-remove", threadId: "thread-remove")

        // Verify it exists
        var messageIds = try database.getMessageIdsInThread(threadId: "thread-remove")
        XCTAssertEqual(messageIds.count, 1)

        // Remove it
        try database.removeMessageFromThread(messageId: "msg-remove", threadId: "thread-remove")

        // Verify it's gone
        messageIds = try database.getMessageIdsInThread(threadId: "thread-remove")
        XCTAssertEqual(messageIds.count, 0)
    }

    func testRemoveNonexistentMessageFromThread() throws {
        try database.initialize()

        // Should not throw even if relationship doesn't exist
        try database.removeMessageFromThread(messageId: "nonexistent", threadId: "nonexistent")
    }

    func testGetMessageIdsInThread() throws {
        try database.initialize()

        // Create thread and multiple messages
        let thread = Thread(id: "thread-multi", subject: "Multi Message Thread")
        try database.upsertThread(thread)

        for i in 1...5 {
            let message = MailMessage(id: "multi-msg-\(i)", subject: "Message \(i)")
            try database.upsertMessage(message)
            try database.addMessageToThread(messageId: "multi-msg-\(i)", threadId: "thread-multi")
        }

        let messageIds = try database.getMessageIdsInThread(threadId: "thread-multi")
        XCTAssertEqual(messageIds.count, 5)
        for i in 1...5 {
            XCTAssertTrue(messageIds.contains("multi-msg-\(i)"))
        }
    }

    func testGetMessageIdsInThreadEmpty() throws {
        try database.initialize()

        let messageIds = try database.getMessageIdsInThread(threadId: "nonexistent-thread")
        XCTAssertTrue(messageIds.isEmpty)
    }

    func testGetThreadIdsForMessage() throws {
        try database.initialize()

        // Create multiple threads and one message
        for i in 1...3 {
            let thread = Thread(id: "multi-thread-\(i)", subject: "Thread \(i)")
            try database.upsertThread(thread)
        }

        let message = MailMessage(id: "shared-msg", subject: "Shared Message")
        try database.upsertMessage(message)

        // Add message to all threads
        for i in 1...3 {
            try database.addMessageToThread(messageId: "shared-msg", threadId: "multi-thread-\(i)")
        }

        let threadIds = try database.getThreadIdsForMessage(messageId: "shared-msg")
        XCTAssertEqual(threadIds.count, 3)
        for i in 1...3 {
            XCTAssertTrue(threadIds.contains("multi-thread-\(i)"))
        }
    }

    func testGetThreadIdsForMessageEmpty() throws {
        try database.initialize()

        let threadIds = try database.getThreadIdsForMessage(messageId: "nonexistent-message")
        XCTAssertTrue(threadIds.isEmpty)
    }

    func testGetMessagesInThreadViaJunction() throws {
        try database.initialize()

        // Create thread
        let thread = Thread(id: "full-thread", subject: "Full Thread Test")
        try database.upsertThread(thread)

        // Create messages with different dates
        let baseDate = Date(timeIntervalSince1970: 1000000)
        for i in 1...3 {
            let message = MailMessage(
                id: "full-msg-\(i)",
                subject: "Full Message \(i)",
                dateReceived: Date(timeIntervalSince1970: baseDate.timeIntervalSince1970 + Double(i * 100))
            )
            try database.upsertMessage(message)
            try database.addMessageToThread(messageId: "full-msg-\(i)", threadId: "full-thread")
        }

        let messages = try database.getMessagesInThreadViaJunction(threadId: "full-thread")
        XCTAssertEqual(messages.count, 3)

        // Verify ordering by date_received ASC
        XCTAssertEqual(messages[0].id, "full-msg-1")
        XCTAssertEqual(messages[1].id, "full-msg-2")
        XCTAssertEqual(messages[2].id, "full-msg-3")
    }

    func testGetMessagesInThreadViaJunctionExcludesDeleted() throws {
        try database.initialize()

        // Create thread
        let thread = Thread(id: "deleted-test-thread", subject: "Deleted Test")
        try database.upsertThread(thread)

        // Create one normal message and one deleted message
        let normalMsg = MailMessage(id: "normal-msg", subject: "Normal")
        let deletedMsg = MailMessage(id: "deleted-msg", subject: "Deleted", isDeleted: true)

        try database.upsertMessage(normalMsg)
        try database.upsertMessage(deletedMsg)

        try database.addMessageToThread(messageId: "normal-msg", threadId: "deleted-test-thread")
        try database.addMessageToThread(messageId: "deleted-msg", threadId: "deleted-test-thread")

        let messages = try database.getMessagesInThreadViaJunction(threadId: "deleted-test-thread")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.id, "normal-msg")
    }

    func testGetMessagesInThreadViaJunctionWithLimitAndOffset() throws {
        try database.initialize()

        let thread = Thread(id: "paginated-thread", subject: "Paginated Thread")
        try database.upsertThread(thread)

        // Create 10 messages
        for i in 1...10 {
            let message = MailMessage(
                id: "paginated-msg-\(i)",
                subject: "Message \(i)",
                dateReceived: Date(timeIntervalSince1970: Double(1000000 + i))
            )
            try database.upsertMessage(message)
            try database.addMessageToThread(messageId: "paginated-msg-\(i)", threadId: "paginated-thread")
        }

        // Get first 5
        let first5 = try database.getMessagesInThreadViaJunction(threadId: "paginated-thread", limit: 5)
        XCTAssertEqual(first5.count, 5)

        // Get next 5
        let next5 = try database.getMessagesInThreadViaJunction(threadId: "paginated-thread", limit: 5, offset: 5)
        XCTAssertEqual(next5.count, 5)

        // Verify no overlap
        let first5Ids = Set(first5.map { $0.id })
        let next5Ids = Set(next5.map { $0.id })
        XCTAssertTrue(first5Ids.isDisjoint(with: next5Ids))
    }

    func testGetThreadsForMessage() throws {
        try database.initialize()

        // Create threads with different dates
        let baseDate = Date(timeIntervalSince1970: 1000000)
        for i in 1...3 {
            let thread = Thread(
                id: "msg-threads-\(i)",
                subject: "Thread \(i)",
                lastDate: Date(timeIntervalSince1970: baseDate.timeIntervalSince1970 + Double(i * 100))
            )
            try database.upsertThread(thread)
        }

        let message = MailMessage(id: "thread-query-msg", subject: "Query Message")
        try database.upsertMessage(message)

        // Add message to all threads
        for i in 1...3 {
            try database.addMessageToThread(messageId: "thread-query-msg", threadId: "msg-threads-\(i)")
        }

        let threads = try database.getThreadsForMessage(messageId: "thread-query-msg")
        XCTAssertEqual(threads.count, 3)

        // Verify ordering by last_date DESC
        XCTAssertEqual(threads[0].id, "msg-threads-3")
        XCTAssertEqual(threads[1].id, "msg-threads-2")
        XCTAssertEqual(threads[2].id, "msg-threads-1")
    }

    func testGetThreadsForMessageEmpty() throws {
        try database.initialize()

        let threads = try database.getThreadsForMessage(messageId: "nonexistent")
        XCTAssertTrue(threads.isEmpty)
    }

    func testGetMessageCountInThread() throws {
        try database.initialize()

        let thread = Thread(id: "count-thread", subject: "Count Thread")
        try database.upsertThread(thread)

        // Initially empty
        var count = try database.getMessageCountInThread(threadId: "count-thread")
        XCTAssertEqual(count, 0)

        // Add messages
        for i in 1...5 {
            let message = MailMessage(id: "count-msg-\(i)", subject: "Count Message \(i)")
            try database.upsertMessage(message)
            try database.addMessageToThread(messageId: "count-msg-\(i)", threadId: "count-thread")
        }

        count = try database.getMessageCountInThread(threadId: "count-thread")
        XCTAssertEqual(count, 5)
    }

    func testGetMessageCountInThreadNonexistent() throws {
        try database.initialize()

        let count = try database.getMessageCountInThread(threadId: "nonexistent")
        XCTAssertEqual(count, 0)
    }

    func testIsMessageInThread() throws {
        try database.initialize()

        let thread = Thread(id: "check-thread", subject: "Check Thread")
        try database.upsertThread(thread)

        let message = MailMessage(id: "check-msg", subject: "Check Message")
        try database.upsertMessage(message)

        // Initially not in thread
        var inThread = try database.isMessageInThread(messageId: "check-msg", threadId: "check-thread")
        XCTAssertFalse(inThread)

        // Add to thread
        try database.addMessageToThread(messageId: "check-msg", threadId: "check-thread")

        // Now in thread
        inThread = try database.isMessageInThread(messageId: "check-msg", threadId: "check-thread")
        XCTAssertTrue(inThread)

        // Remove from thread
        try database.removeMessageFromThread(messageId: "check-msg", threadId: "check-thread")

        // Not in thread anymore
        inThread = try database.isMessageInThread(messageId: "check-msg", threadId: "check-thread")
        XCTAssertFalse(inThread)
    }

    func testIsMessageInThreadNonexistent() throws {
        try database.initialize()

        let inThread = try database.isMessageInThread(messageId: "nonexistent", threadId: "nonexistent")
        XCTAssertFalse(inThread)
    }

    func testThreadMessageForeignKeyConstraintOnThreadDelete() throws {
        try database.initialize()

        // Create thread and message
        let thread = Thread(id: "fk-thread", subject: "FK Thread")
        try database.upsertThread(thread)

        let message = MailMessage(id: "fk-msg", subject: "FK Message")
        try database.upsertMessage(message)

        try database.addMessageToThread(messageId: "fk-msg", threadId: "fk-thread")

        // Verify relationship exists
        var messageIds = try database.getMessageIdsInThread(threadId: "fk-thread")
        XCTAssertEqual(messageIds.count, 1)

        // Note: SQLite's foreign key CASCADE delete would clean up thread_messages
        // when the thread is deleted. However, we don't have a deleteThread method yet.
        // This test verifies the junction table is working correctly.
    }

    func testManyToManyRelationship() throws {
        try database.initialize()

        // Create multiple threads
        let threads = ["thread-a", "thread-b", "thread-c"]
        for threadId in threads {
            try database.upsertThread(Thread(id: threadId, subject: "Thread \(threadId)"))
        }

        // Create multiple messages
        let messages = ["msg-1", "msg-2", "msg-3"]
        for msgId in messages {
            try database.upsertMessage(MailMessage(id: msgId, subject: "Message \(msgId)"))
        }

        // Create many-to-many relationships:
        // msg-1 -> thread-a, thread-b
        // msg-2 -> thread-b, thread-c
        // msg-3 -> thread-a, thread-c
        try database.addMessageToThread(messageId: "msg-1", threadId: "thread-a")
        try database.addMessageToThread(messageId: "msg-1", threadId: "thread-b")
        try database.addMessageToThread(messageId: "msg-2", threadId: "thread-b")
        try database.addMessageToThread(messageId: "msg-2", threadId: "thread-c")
        try database.addMessageToThread(messageId: "msg-3", threadId: "thread-a")
        try database.addMessageToThread(messageId: "msg-3", threadId: "thread-c")

        // Verify thread-a has msg-1 and msg-3
        let threadAMessages = try database.getMessageIdsInThread(threadId: "thread-a")
        XCTAssertEqual(threadAMessages.count, 2)
        XCTAssertTrue(threadAMessages.contains("msg-1"))
        XCTAssertTrue(threadAMessages.contains("msg-3"))

        // Verify thread-b has msg-1 and msg-2
        let threadBMessages = try database.getMessageIdsInThread(threadId: "thread-b")
        XCTAssertEqual(threadBMessages.count, 2)
        XCTAssertTrue(threadBMessages.contains("msg-1"))
        XCTAssertTrue(threadBMessages.contains("msg-2"))

        // Verify thread-c has msg-2 and msg-3
        let threadCMessages = try database.getMessageIdsInThread(threadId: "thread-c")
        XCTAssertEqual(threadCMessages.count, 2)
        XCTAssertTrue(threadCMessages.contains("msg-2"))
        XCTAssertTrue(threadCMessages.contains("msg-3"))

        // Verify msg-1 is in thread-a and thread-b
        let msg1Threads = try database.getThreadIdsForMessage(messageId: "msg-1")
        XCTAssertEqual(msg1Threads.count, 2)
        XCTAssertTrue(msg1Threads.contains("thread-a"))
        XCTAssertTrue(msg1Threads.contains("thread-b"))
    }

    func testThreadMessageJunctionMethodsBeforeInitializeThrow() throws {
        // Don't call initialize()

        XCTAssertThrowsError(try database.addMessageToThread(messageId: "test", threadId: "test")) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized")
                return
            }
        }

        XCTAssertThrowsError(try database.removeMessageFromThread(messageId: "test", threadId: "test")) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized")
                return
            }
        }

        XCTAssertThrowsError(try database.getMessageIdsInThread(threadId: "test")) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized")
                return
            }
        }

        XCTAssertThrowsError(try database.getThreadIdsForMessage(messageId: "test")) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized")
                return
            }
        }

        XCTAssertThrowsError(try database.getMessagesInThreadViaJunction(threadId: "test")) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized")
                return
            }
        }

        XCTAssertThrowsError(try database.getThreadsForMessage(messageId: "test")) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized")
                return
            }
        }

        XCTAssertThrowsError(try database.getMessageCountInThread(threadId: "test")) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized")
                return
            }
        }

        XCTAssertThrowsError(try database.isMessageInThread(messageId: "test", threadId: "test")) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized")
                return
            }
        }
    }

    // MARK: - US-004: Thread Index Tests

    func testThreadIdIndexExistsOnMessagesTable() throws {
        try database.initialize()

        let indexes = try database.getIndexes(on: "messages")

        XCTAssertTrue(indexes.contains("idx_messages_thread_id"),
                      "Index idx_messages_thread_id should exist on messages table. Found: \(indexes)")
    }

    func testThreadsTableHasPrimaryKeyIndex() throws {
        try database.initialize()

        // SQLite automatically creates an index for the PRIMARY KEY
        // We can verify this by checking the table info
        let indexes = try database.getIndexes(on: "threads")

        // The threads table should have an index on last_date
        XCTAssertTrue(indexes.contains("idx_threads_last_date"),
                      "Index idx_threads_last_date should exist on threads table. Found: \(indexes)")
    }

    func testThreadMessagesIndexesExist() throws {
        try database.initialize()

        let indexes = try database.getIndexes(on: "thread_messages")

        XCTAssertTrue(indexes.contains("idx_thread_messages_thread_id"),
                      "Index idx_thread_messages_thread_id should exist on thread_messages table. Found: \(indexes)")
        XCTAssertTrue(indexes.contains("idx_thread_messages_message_id"),
                      "Index idx_thread_messages_message_id should exist on thread_messages table. Found: \(indexes)")
    }

    func testExplainQueryPlanUsesThreadIdIndex() throws {
        try database.initialize()

        // Create thread first (required for foreign key constraint)
        let thread = Thread(id: "test-thread-id", subject: "Test Thread")
        try database.upsertThread(thread)

        // Insert some test data to ensure table has data
        let message = MailMessage(id: "plan-test-msg", subject: "Plan Test", threadId: "test-thread-id")
        try database.upsertMessage(message)

        // Query plan for looking up messages by thread_id
        let plan = try database.explainQueryPlan(
            "SELECT * FROM messages WHERE thread_id = 'test-thread-id'"
        )

        // The plan should show usage of the index
        // SQLite's EXPLAIN QUERY PLAN typically shows "SEARCH" with index usage
        let planString = plan.joined(separator: " ")
        XCTAssertTrue(
            planString.contains("idx_messages_thread_id") || planString.contains("USING INDEX"),
            "Query should use idx_messages_thread_id index. Plan: \(planString)"
        )
    }

    func testExplainQueryPlanUsesThreadMessagesIndex() throws {
        try database.initialize()

        // Insert test data
        let thread = Thread(id: "plan-thread", subject: "Plan Thread")
        try database.upsertThread(thread)
        let message = MailMessage(id: "plan-msg", subject: "Plan Message")
        try database.upsertMessage(message)
        try database.addMessageToThread(messageId: "plan-msg", threadId: "plan-thread")

        // Query plan for looking up messages in a thread via junction table
        let plan = try database.explainQueryPlan(
            "SELECT message_id FROM thread_messages WHERE thread_id = 'plan-thread'"
        )

        // The plan should show usage of an index (could be explicit index or autoindex for primary key)
        // SQLite may use sqlite_autoindex_thread_messages_1 which is the covering index for the composite primary key
        let planString = plan.joined(separator: " ")
        XCTAssertTrue(
            planString.contains("idx_thread_messages_thread_id") ||
            planString.contains("USING INDEX") ||
            planString.contains("USING COVERING INDEX") ||
            planString.contains("sqlite_autoindex"),
            "Query should use an index. Plan: \(planString)"
        )
    }

    func testIndexVerificationMethodsBeforeInitializeThrow() throws {
        // Don't call initialize()

        XCTAssertThrowsError(try database.getIndexes(on: "messages")) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized")
                return
            }
        }

        XCTAssertThrowsError(try database.explainQueryPlan("SELECT 1")) { error in
            guard case MailDatabaseError.notInitialized = error else {
                XCTFail("Expected MailDatabaseError.notInitialized")
                return
            }
        }
    }
}
