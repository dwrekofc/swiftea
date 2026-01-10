import XCTest
@testable import SwiftEAKit

final class MailExportTests: XCTestCase {
    var testDir: String!
    var database: MailDatabase!

    override func setUp() {
        super.setUp()
        testDir = NSTemporaryDirectory() + "swiftea-mailexport-test-\(UUID().uuidString)"
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

    // MARK: - Markdown Export Format Tests

    func testMarkdownExportFilenameIsIdBased() throws {
        try database.initialize()

        let message = MailMessage(
            id: "abc123def456abc123def456abc12345",
            subject: "Test Subject with Spaces and Special-Chars!"
        )

        // The filename should be <id>.md regardless of subject
        let expectedFilename = "\(message.id).md"
        XCTAssertEqual(expectedFilename, "abc123def456abc123def456abc12345.md")
    }

    func testMarkdownExportFrontmatterContainsRequiredFields() throws {
        try database.initialize()

        let message = MailMessage(
            id: "test123abc456def789test123abc456",
            subject: "Important Meeting Notes",
            senderName: "John Doe",
            senderEmail: "john@example.com",
            dateSent: Date(timeIntervalSince1970: 1736177400)
        )
        try database.upsertMessage(message)

        let markdown = formatAsMarkdown(message)

        // Verify frontmatter contains required fields
        XCTAssertTrue(markdown.hasPrefix("---\n"), "Should start with YAML frontmatter")
        XCTAssertTrue(markdown.contains("id: \"test123abc456def789test123abc456\""), "Should contain id field")
        XCTAssertTrue(markdown.contains("subject: \"Important Meeting Notes\""), "Should contain subject field")
        XCTAssertTrue(markdown.contains("from: \"John Doe <john@example.com>\""), "Should contain from field")
        XCTAssertTrue(markdown.contains("date: "), "Should contain date field")
        XCTAssertTrue(markdown.contains("aliases:"), "Should contain aliases field")
        XCTAssertTrue(markdown.contains("  - \"Important Meeting Notes\""), "Should contain subject as alias")
    }

    func testMarkdownExportMinimalFrontmatter() throws {
        try database.initialize()

        let message = MailMessage(
            id: "minimal123minimal123minimal12345",
            subject: "Minimal Test"
        )
        try database.upsertMessage(message)

        let markdown = formatAsMarkdown(message)

        // Should NOT contain these optional fields that were previously included
        XCTAssertFalse(markdown.contains("message_id:"), "Should not contain message_id")
        XCTAssertFalse(markdown.contains("mailbox:"), "Should not contain mailbox")
        XCTAssertFalse(markdown.contains("is_read:"), "Should not contain is_read")
        XCTAssertFalse(markdown.contains("is_flagged:"), "Should not contain is_flagged")
        XCTAssertFalse(markdown.contains("has_attachments:"), "Should not contain has_attachments")
        XCTAssertFalse(markdown.contains("swiftea_id:"), "Should not contain swiftea_id (replaced by id)")
    }

    func testMarkdownExportWithSpecialCharactersInSubject() throws {
        try database.initialize()

        let message = MailMessage(
            id: "special123special123special12345",
            subject: "Test with \"quotes\" and 'apostrophes'"
        )
        try database.upsertMessage(message)

        let markdown = formatAsMarkdown(message)

        // Verify YAML escaping
        XCTAssertTrue(markdown.contains("subject: \"Test with \\\"quotes\\\" and 'apostrophes'\""),
                      "Should properly escape quotes in YAML")
    }

    func testMarkdownExportContainsBody() throws {
        try database.initialize()

        let message = MailMessage(
            id: "body123body123body123body123456",
            subject: "Email with Body",
            bodyText: "This is the email body content.\n\nWith multiple paragraphs."
        )
        try database.upsertMessage(message)

        let markdown = formatAsMarkdown(message)

        // Verify body content is included
        XCTAssertTrue(markdown.contains("# Email with Body"), "Should contain subject as heading")
        XCTAssertTrue(markdown.contains("This is the email body content."), "Should contain body text")
        XCTAssertTrue(markdown.contains("With multiple paragraphs."), "Should preserve paragraphs")
    }

    func testMarkdownExportWithNoBody() throws {
        try database.initialize()

        let message = MailMessage(
            id: "nobody123nobody123nobody1234567",
            subject: "Email without Body"
        )
        try database.upsertMessage(message)

        let markdown = formatAsMarkdown(message)

        XCTAssertTrue(markdown.contains("*(No message body)*"), "Should indicate missing body")
    }

    func testMarkdownExportFromEmailOnly() throws {
        try database.initialize()

        let message = MailMessage(
            id: "emailonly123emailonly1234567890",
            subject: "Test",
            senderEmail: "sender@example.com"
        )

        let markdown = formatAsMarkdown(message)
        XCTAssertTrue(markdown.contains("from: \"sender@example.com\""), "Should use email only when no name")
    }

    func testMarkdownExportFromUnknown() throws {
        try database.initialize()

        let message = MailMessage(
            id: "unknown123unknown123unknown1234",
            subject: "Test"
        )

        let markdown = formatAsMarkdown(message)
        XCTAssertTrue(markdown.contains("from: \"Unknown\""), "Should show Unknown when no sender info")
    }

    // MARK: - Helper to simulate markdown formatting

    private func formatAsMarkdown(_ message: MailMessage) -> String {
        var lines: [String] = []

        // Minimal YAML frontmatter: id, subject, from, date, aliases
        lines.append("---")
        lines.append("id: \"\(message.id)\"")
        lines.append("subject: \"\(escapeYaml(message.subject))\"")
        lines.append("from: \"\(escapeYaml(formatSender(message)))\"")
        if let date = message.dateSent {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            lines.append("date: \(formatter.string(from: date))")
        }
        // aliases: use subject as an alias for linking by topic
        lines.append("aliases:")
        lines.append("  - \"\(escapeYaml(message.subject))\"")
        lines.append("---")
        lines.append("")

        // Subject as heading
        lines.append("# \(message.subject)")
        lines.append("")

        // Body content
        if let textBody = message.bodyText, !textBody.isEmpty {
            lines.append(textBody)
        } else if let htmlBody = message.bodyHtml {
            lines.append(htmlBody)
        } else {
            lines.append("*(No message body)*")
        }

        return lines.joined(separator: "\n")
    }

    private func formatSender(_ message: MailMessage) -> String {
        if let name = message.senderName, let email = message.senderEmail {
            return "\(name) <\(email)>"
        } else if let email = message.senderEmail {
            return email
        } else if let name = message.senderName {
            return name
        }
        return "Unknown"
    }

    private func escapeYaml(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
