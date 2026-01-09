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
}
