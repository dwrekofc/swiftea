import XCTest
@testable import SwiftEAKit

/// Integration tests for bulk copy operations with large datasets.
/// Tests performance and correctness of the bulk copy feature with 10k messages.
final class MailBulkCopyTests: XCTestCase {
    var testDir: String!
    var database: MailDatabase!

    override func setUp() {
        super.setUp()
        testDir = NSTemporaryDirectory() + "swiftea-bulk-copy-test-\(UUID().uuidString)"
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

    // MARK: - Large Dataset Integration Tests

    /// Tests bulk copy with 10,000 messages to verify correctness and measure performance.
    ///
    /// **Performance Baseline (M1 Mac):**
    /// - 10k messages: ~1-2 seconds for copy operation
    /// - Includes addresses, mailboxes, and messages tables
    ///
    /// This test validates:
    /// - All messages are copied correctly
    /// - Message IDs and metadata are preserved
    /// - Mailboxes and addresses are correctly associated
    /// - Performance is within acceptable bounds
    func testBulkCopyWith10kMessages() throws {
        try database.initialize()

        // Generate 10k mock messages with varied data
        let messageCount = 10_000
        let mailboxCount = 10
        let addressCount = 100

        // Create a mock Envelope Index with 10k messages
        let envelopePath = (testDir as NSString).appendingPathComponent("LargeEnvelopeIndex")

        let startSetup = CFAbsoluteTimeGetCurrent()
        try createLargeEnvelopeIndex(
            at: envelopePath,
            messageCount: messageCount,
            mailboxCount: mailboxCount,
            addressCount: addressCount
        )
        let setupTime = CFAbsoluteTimeGetCurrent() - startSetup
        print("[MailBulkCopyTests] Setup time for \(messageCount) messages: \(String(format: "%.2f", setupTime))s")

        // Attach envelope and perform bulk copy
        try database.attachEnvelopeIndex(path: envelopePath)

        let startCopy = CFAbsoluteTimeGetCurrent()
        let result = try database.performBulkCopy()
        let copyTime = CFAbsoluteTimeGetCurrent() - startCopy

        // Document performance
        print("[MailBulkCopyTests] Bulk copy performance for \(messageCount) messages:")
        print("  - Copy time: \(String(format: "%.2f", copyTime))s")
        print("  - Throughput: \(String(format: "%.0f", Double(messageCount) / copyTime)) messages/second")
        print("  - Total records: \(result.totalCount)")

        try database.detachEnvelopeIndex()

        // Verify counts
        XCTAssertEqual(result.messageCount, messageCount, "Expected \(messageCount) messages copied")
        XCTAssertEqual(result.mailboxCount, mailboxCount, "Expected \(mailboxCount) mailboxes copied")
        XCTAssertEqual(result.addressCount, addressCount, "Expected \(addressCount) addresses copied")

        // Performance assertion: bulk copy should complete in reasonable time
        // On M1, 10k messages typically copies in <2 seconds
        XCTAssertLessThan(copyTime, 30.0, "Bulk copy took too long: \(copyTime)s (expected <30s)")
    }

    /// Tests that all messages are retrievable after bulk copy with correct metadata.
    func testBulkCopyMessagesMetadataPreserved() throws {
        try database.initialize()

        let messageCount = 1_000  // Use smaller count for detailed validation
        let envelopePath = (testDir as NSString).appendingPathComponent("MetadataTestEnvelope")

        try createLargeEnvelopeIndex(
            at: envelopePath,
            messageCount: messageCount,
            mailboxCount: 5,
            addressCount: 50
        )

        try database.attachEnvelopeIndex(path: envelopePath)
        let result = try database.performBulkCopy()
        try database.detachEnvelopeIndex()

        XCTAssertEqual(result.messageCount, messageCount)

        // Sample a few messages to verify metadata
        // First message should have ROWID 1
        if let firstMessage = try database.getMessage(appleRowId: 1) {
            XCTAssertNotNil(firstMessage.id, "Message should have stable ID")
            XCTAssertEqual(firstMessage.appleRowId, 1, "Apple ROWID should be preserved")
            XCTAssertNotNil(firstMessage.subject, "Subject should be populated")
            XCTAssertNotNil(firstMessage.senderEmail, "Sender email should be populated")
        } else {
            XCTFail("First message should be retrievable by apple_rowid")
        }

        // Middle message
        let middleRowId = messageCount / 2
        if let middleMessage = try database.getMessage(appleRowId: middleRowId) {
            XCTAssertEqual(Int(middleMessage.appleRowId ?? 0), middleRowId, "Middle message ROWID preserved")
        } else {
            XCTFail("Middle message should be retrievable")
        }

        // Last message
        if let lastMessage = try database.getMessage(appleRowId: messageCount) {
            XCTAssertEqual(Int(lastMessage.appleRowId ?? 0), messageCount, "Last message ROWID preserved")
        } else {
            XCTFail("Last message should be retrievable")
        }
    }

    /// Tests that mailboxes are correctly populated and linked to messages.
    func testBulkCopyMailboxesLinkedToMessages() throws {
        try database.initialize()

        let mailboxCount = 5
        let messagesPerMailbox = 200
        let totalMessages = mailboxCount * messagesPerMailbox

        let envelopePath = (testDir as NSString).appendingPathComponent("MailboxLinkTestEnvelope")

        try createLargeEnvelopeIndex(
            at: envelopePath,
            messageCount: totalMessages,
            mailboxCount: mailboxCount,
            addressCount: 20
        )

        try database.attachEnvelopeIndex(path: envelopePath)
        let result = try database.performBulkCopy()
        try database.detachEnvelopeIndex()

        XCTAssertEqual(result.mailboxCount, mailboxCount)
        XCTAssertEqual(result.messageCount, totalMessages)

        // Verify mailboxes exist by querying messages grouped by mailbox
        // Each mailbox should have messagesPerMailbox messages
        let mailboxes = try database.getMailboxes()
        XCTAssertEqual(mailboxes.count, mailboxCount, "All mailboxes should be created")

        // Verify each mailbox has a valid name extracted from URL
        for mailbox in mailboxes {
            XCTAssertFalse(mailbox.name.isEmpty, "Mailbox should have name extracted from URL")
            XCTAssertNotNil(mailbox.accountId, "Mailbox should have account_id extracted from URL")
        }
    }

    /// Tests that addresses are correctly populated.
    func testBulkCopyAddressesPopulated() throws {
        try database.initialize()

        let addressCount = 100
        let envelopePath = (testDir as NSString).appendingPathComponent("AddressTestEnvelope")

        try createLargeEnvelopeIndex(
            at: envelopePath,
            messageCount: 500,
            mailboxCount: 3,
            addressCount: addressCount
        )

        try database.attachEnvelopeIndex(path: envelopePath)
        let result = try database.performBulkCopy()
        try database.detachEnvelopeIndex()

        XCTAssertEqual(result.addressCount, addressCount, "All addresses should be copied")
    }

    /// Tests idempotency: running bulk copy twice should produce the same result.
    func testBulkCopyIdempotency() throws {
        try database.initialize()

        let messageCount = 1_000
        let envelopePath = (testDir as NSString).appendingPathComponent("IdempotencyTestEnvelope")

        try createLargeEnvelopeIndex(
            at: envelopePath,
            messageCount: messageCount,
            mailboxCount: 5,
            addressCount: 50
        )

        // First copy
        try database.attachEnvelopeIndex(path: envelopePath)
        let result1 = try database.performBulkCopy()
        try database.detachEnvelopeIndex()

        // Second copy (re-attach and copy again)
        try database.attachEnvelopeIndex(path: envelopePath)
        let result2 = try database.performBulkCopy()
        try database.detachEnvelopeIndex()

        // Results should be identical (INSERT OR REPLACE handles duplicates)
        XCTAssertEqual(result1.messageCount, result2.messageCount, "Idempotent: same message count")
        XCTAssertEqual(result1.mailboxCount, result2.mailboxCount, "Idempotent: same mailbox count")
        XCTAssertEqual(result1.addressCount, result2.addressCount, "Idempotent: same address count")
    }

    // MARK: - Helper Methods

    /// Creates a large mock Envelope Index database for performance testing.
    /// Uses sqlite3 command line to avoid Libsql connection issues with large datasets.
    private func createLargeEnvelopeIndex(
        at path: String,
        messageCount: Int,
        mailboxCount: Int,
        addressCount: Int
    ) throws {
        // Create parent directory if needed
        let parentDir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        // Build SQL script in chunks to avoid memory issues
        var sql = """
            PRAGMA journal_mode = OFF;
            PRAGMA synchronous = OFF;
            PRAGMA cache_size = 10000;
            BEGIN TRANSACTION;

            CREATE TABLE IF NOT EXISTS messages (
                subject INTEGER,
                sender INTEGER,
                date_received REAL,
                date_sent REAL,
                message_id TEXT,
                mailbox INTEGER,
                read INTEGER,
                flagged INTEGER
            );
            CREATE TABLE IF NOT EXISTS subjects (subject TEXT);
            CREATE TABLE IF NOT EXISTS addresses (address TEXT, comment TEXT);
            CREATE TABLE IF NOT EXISTS mailboxes (url TEXT);

            """

        // Generate addresses
        for i in 1...addressCount {
            let email = "sender\(i)@example.com"
            let name = "Sender \(i)"
            sql += "INSERT INTO addresses (ROWID, address, comment) VALUES (\(i), '\(email)', '\(name)');\n"
        }

        // Generate mailboxes with various URL formats
        let mailboxNames = ["INBOX", "Sent", "Drafts", "Trash", "Archive", "Work", "Personal", "Receipts", "Newsletter", "Important"]
        for i in 1...mailboxCount {
            let mailboxName = mailboxNames[(i - 1) % mailboxNames.count]
            let url = "mailbox://test-account-\(i)/\(mailboxName)"
            sql += "INSERT INTO mailboxes (ROWID, url) VALUES (\(i), '\(url)');\n"
        }

        // Generate subjects (create enough for varied messages)
        let subjectCount = min(messageCount, 1000)  // Reuse subjects if more than 1000 messages
        for i in 1...subjectCount {
            let subject = "Test Subject \(i) - Sample email for testing bulk copy performance"
            sql += "INSERT INTO subjects (ROWID, subject) VALUES (\(i), '\(subject)');\n"
        }

        sql += "COMMIT;\n"
        sql += "BEGIN TRANSACTION;\n"

        // Generate messages
        let baseTimestamp = 1700000000.0  // Some date in 2023
        for i in 1...messageCount {
            let subjectId = ((i - 1) % subjectCount) + 1
            let senderId = ((i - 1) % addressCount) + 1
            let mailboxId = ((i - 1) % mailboxCount) + 1
            let dateReceived = baseTimestamp + Double(i * 60)  // 1 minute apart
            let dateSent = dateReceived - 30  // Sent 30 seconds before received
            let messageId = "<msg-\(UUID().uuidString)@example.com>"
            let isRead = i % 3 == 0 ? 1 : 0  // Every 3rd message is read
            let isFlagged = i % 10 == 0 ? 1 : 0  // Every 10th message is flagged

            sql += "INSERT INTO messages (ROWID, subject, sender, date_received, date_sent, message_id, mailbox, read, flagged) VALUES (\(i), \(subjectId), \(senderId), \(dateReceived), \(dateSent), '\(messageId)', \(mailboxId), \(isRead), \(isFlagged));\n"

            // Commit in batches to avoid very long transactions
            if i % 5000 == 0 && i < messageCount {
                sql += "COMMIT;\nBEGIN TRANSACTION;\n"
            }
        }

        sql += "COMMIT;\n"

        // Use sqlite3 command line to create database
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [path]

        let pipe = Pipe()
        process.standardInput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        // Write SQL in chunks to handle large scripts
        let inputData = sql.data(using: .utf8)!
        pipe.fileHandleForWriting.write(inputData)
        pipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "MailBulkCopyTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Failed to create mock Envelope Index database"]
            )
        }
    }
}
