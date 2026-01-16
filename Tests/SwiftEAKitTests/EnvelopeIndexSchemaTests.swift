import XCTest
@testable import SwiftEAKit

final class EnvelopeIndexSchemaTests: XCTestCase {

    // MARK: - Table Name Tests

    func testEnvelopeIndexMessagesTableName() {
        XCTAssertEqual(EnvelopeIndexMessages.tableName, "messages")
    }

    func testEnvelopeIndexSubjectsTableName() {
        XCTAssertEqual(EnvelopeIndexSubjects.tableName, "subjects")
    }

    func testEnvelopeIndexAddressesTableName() {
        XCTAssertEqual(EnvelopeIndexAddresses.tableName, "addresses")
    }

    func testEnvelopeIndexMailboxesTableName() {
        XCTAssertEqual(EnvelopeIndexMailboxes.tableName, "mailboxes")
    }

    func testVaultMessagesTableName() {
        XCTAssertEqual(VaultMessages.tableName, "messages")
    }

    func testVaultMailboxesTableName() {
        XCTAssertEqual(VaultMailboxes.tableName, "mailboxes")
    }

    // MARK: - Envelope Index Messages Column Names

    func testEnvelopeIndexMessagesColumnNames() {
        XCTAssertEqual(EnvelopeIndexMessages.rowId, "ROWID")
        XCTAssertEqual(EnvelopeIndexMessages.subject, "subject")
        XCTAssertEqual(EnvelopeIndexMessages.sender, "sender")
        XCTAssertEqual(EnvelopeIndexMessages.dateReceived, "date_received")
        XCTAssertEqual(EnvelopeIndexMessages.dateSent, "date_sent")
        XCTAssertEqual(EnvelopeIndexMessages.messageId, "message_id")
        XCTAssertEqual(EnvelopeIndexMessages.mailbox, "mailbox")
        XCTAssertEqual(EnvelopeIndexMessages.read, "read")
        XCTAssertEqual(EnvelopeIndexMessages.flagged, "flagged")
    }

    // MARK: - Envelope Index Addresses Column Names

    func testEnvelopeIndexAddressesColumnNames() {
        XCTAssertEqual(EnvelopeIndexAddresses.rowId, "ROWID")
        XCTAssertEqual(EnvelopeIndexAddresses.address, "address")
        XCTAssertEqual(EnvelopeIndexAddresses.comment, "comment")
    }

    // MARK: - Envelope Index Subjects Column Names

    func testEnvelopeIndexSubjectsColumnNames() {
        XCTAssertEqual(EnvelopeIndexSubjects.rowId, "ROWID")
        XCTAssertEqual(EnvelopeIndexSubjects.subject, "subject")
    }

    // MARK: - Envelope Index Mailboxes Column Names

    func testEnvelopeIndexMailboxesColumnNames() {
        XCTAssertEqual(EnvelopeIndexMailboxes.rowId, "ROWID")
        XCTAssertEqual(EnvelopeIndexMailboxes.url, "url")
    }

    // MARK: - Vault Messages Column Names

    func testVaultMessagesColumnNames() {
        XCTAssertEqual(VaultMessages.id, "id")
        XCTAssertEqual(VaultMessages.appleRowId, "apple_rowid")
        XCTAssertEqual(VaultMessages.messageId, "message_id")
        XCTAssertEqual(VaultMessages.mailboxId, "mailbox_id")
        XCTAssertEqual(VaultMessages.mailboxName, "mailbox_name")
        XCTAssertEqual(VaultMessages.subject, "subject")
        XCTAssertEqual(VaultMessages.senderName, "sender_name")
        XCTAssertEqual(VaultMessages.senderEmail, "sender_email")
        XCTAssertEqual(VaultMessages.dateReceived, "date_received")
        XCTAssertEqual(VaultMessages.dateSent, "date_sent")
        XCTAssertEqual(VaultMessages.isRead, "is_read")
        XCTAssertEqual(VaultMessages.isFlagged, "is_flagged")
        XCTAssertEqual(VaultMessages.isDeleted, "is_deleted")
        XCTAssertEqual(VaultMessages.hasAttachments, "has_attachments")
        XCTAssertEqual(VaultMessages.threadId, "thread_id")
    }

    // MARK: - Query Template Tests

    func testEnvelopeIndexMessagesSelectWithJoinsQuery() {
        let query = EnvelopeIndexMessages.selectWithJoinsQuery
        XCTAssertTrue(query.contains("SELECT"))
        XCTAssertTrue(query.contains("FROM messages m"))
        XCTAssertTrue(query.contains("LEFT JOIN subjects s"))
        XCTAssertTrue(query.contains("LEFT JOIN addresses a"))
        XCTAssertTrue(query.contains("sender_email"))
        XCTAssertTrue(query.contains("sender_name"))
    }

    func testEnvelopeIndexMessagesSelectInboxOnlyQuery() {
        let query = EnvelopeIndexMessages.selectInboxOnlyQuery
        XCTAssertTrue(query.contains("INNER JOIN mailboxes mb"))
        XCTAssertTrue(query.contains("LIKE '%/inbox'"))
    }

    func testEnvelopeIndexMessagesExistsQuery() {
        let query = EnvelopeIndexMessages.existsQuery(rowIds: [1, 2, 3])
        XCTAssertEqual(query, "SELECT ROWID FROM messages WHERE ROWID IN (1,2,3)")
    }

    func testEnvelopeIndexMessagesStatusQuery() {
        let query = EnvelopeIndexMessages.statusQuery(rowIds: [100, 200])
        XCTAssertEqual(query, "SELECT ROWID, read, flagged FROM messages WHERE ROWID IN (100,200)")
    }

    func testEnvelopeIndexMailboxesSelectAllQuery() {
        let query = EnvelopeIndexMailboxes.selectAllQuery
        XCTAssertTrue(query.contains("SELECT ROWID, url"))
        XCTAssertTrue(query.contains("FROM mailboxes"))
        XCTAssertTrue(query.contains("WHERE url IS NOT NULL"))
    }

    func testEnvelopeIndexMailboxesSelectByIdQuery() {
        let query = EnvelopeIndexMailboxes.selectByIdQuery(id: 42)
        XCTAssertEqual(query, "SELECT url FROM mailboxes WHERE ROWID = 42")
    }

    func testEnvelopeIndexMailboxesSelectMessageMailboxQuery() {
        let query = EnvelopeIndexMailboxes.selectMessageMailboxQuery(rowIds: [1, 2])
        XCTAssertTrue(query.contains("SELECT m.ROWID, m.mailbox, mb.url"))
        XCTAssertTrue(query.contains("FROM messages m"))
        XCTAssertTrue(query.contains("LEFT JOIN mailboxes mb"))
        XCTAssertTrue(query.contains("IN (1,2)"))
    }

    // MARK: - Schema Mapping Utilities Tests

    func testConvertDateWithValue() {
        let result = EnvelopeIndexSchemaMapping.convertDate(1700000000.5)
        XCTAssertEqual(result, 1700000000)
    }

    func testConvertDateWithNil() {
        let result = EnvelopeIndexSchemaMapping.convertDate(nil)
        XCTAssertNil(result)
    }

    func testConvertBoolTrue() {
        XCTAssertTrue(EnvelopeIndexSchemaMapping.convertBool(1))
    }

    func testConvertBoolFalse() {
        XCTAssertFalse(EnvelopeIndexSchemaMapping.convertBool(0))
    }

    func testConvertBoolNil() {
        XCTAssertFalse(EnvelopeIndexSchemaMapping.convertBool(nil))
    }

    func testConvertBoolToIntTrue() {
        XCTAssertEqual(EnvelopeIndexSchemaMapping.convertBoolToInt(true), 1)
    }

    func testConvertBoolToIntFalse() {
        XCTAssertEqual(EnvelopeIndexSchemaMapping.convertBoolToInt(false), 0)
    }

    func testExtractMailboxNameFromURL() {
        let result = EnvelopeIndexSchemaMapping.extractMailboxName(from: "mailbox://account/INBOX")
        XCTAssertEqual(result, "INBOX")
    }

    func testExtractMailboxNameFromFilePath() {
        let result = EnvelopeIndexSchemaMapping.extractMailboxName(from: "/Users/test/Mail/INBOX.mbox")
        XCTAssertEqual(result, "INBOX.mbox")
    }

    func testExtractMailboxNameFromNil() {
        let result = EnvelopeIndexSchemaMapping.extractMailboxName(from: nil)
        XCTAssertNil(result)
    }

    func testFormatSenderWithNameAndEmail() {
        let result = EnvelopeIndexSchemaMapping.formatSender(email: "user@example.com", name: "John Doe")
        XCTAssertEqual(result, "\"John Doe\" <user@example.com>")
    }

    func testFormatSenderWithEmailOnly() {
        let result = EnvelopeIndexSchemaMapping.formatSender(email: "user@example.com", name: nil)
        XCTAssertEqual(result, "user@example.com")
    }

    func testFormatSenderWithEmptyName() {
        let result = EnvelopeIndexSchemaMapping.formatSender(email: "user@example.com", name: "")
        XCTAssertEqual(result, "user@example.com")
    }

    func testFormatSenderWithNilEmail() {
        let result = EnvelopeIndexSchemaMapping.formatSender(email: nil, name: "John Doe")
        XCTAssertNil(result)
    }

    func testParseSenderWithNameAndEmail() {
        let result = EnvelopeIndexSchemaMapping.parseSender("\"John Doe\" <user@example.com>")
        XCTAssertEqual(result.name, "John Doe")
        XCTAssertEqual(result.email, "user@example.com")
    }

    func testParseSenderWithEmailOnly() {
        let result = EnvelopeIndexSchemaMapping.parseSender("user@example.com")
        XCTAssertNil(result.name)
        XCTAssertEqual(result.email, "user@example.com")
    }

    func testParseSenderWithNameNoQuotes() {
        let result = EnvelopeIndexSchemaMapping.parseSender("John Doe <user@example.com>")
        XCTAssertEqual(result.name, "John Doe")
        XCTAssertEqual(result.email, "user@example.com")
    }

    func testParseSenderWithNil() {
        let result = EnvelopeIndexSchemaMapping.parseSender(nil)
        XCTAssertNil(result.name)
        XCTAssertNil(result.email)
    }

    func testParseSenderWithNameOnly() {
        // Edge case: name only, no email
        let result = EnvelopeIndexSchemaMapping.parseSender("John Doe")
        XCTAssertEqual(result.name, "John Doe")
        XCTAssertNil(result.email)
    }

    // MARK: - Round-trip Tests

    func testFormatAndParseSenderRoundTrip() {
        let originalEmail = "test@example.com"
        let originalName = "Test User"

        let formatted = EnvelopeIndexSchemaMapping.formatSender(email: originalEmail, name: originalName)
        XCTAssertNotNil(formatted)

        let parsed = EnvelopeIndexSchemaMapping.parseSender(formatted)
        XCTAssertEqual(parsed.email, originalEmail)
        XCTAssertEqual(parsed.name, originalName)
    }

    func testFormatAndParseSenderRoundTripEmailOnly() {
        let originalEmail = "test@example.com"

        let formatted = EnvelopeIndexSchemaMapping.formatSender(email: originalEmail, name: nil)
        XCTAssertNotNil(formatted)

        let parsed = EnvelopeIndexSchemaMapping.parseSender(formatted)
        XCTAssertEqual(parsed.email, originalEmail)
        XCTAssertNil(parsed.name)
    }
}
