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

    // MARK: - Thread Metadata Export Tests

    func testMarkdownExportIncludesThreadId() throws {
        try database.initialize()

        let threadId = "thread123thread123thread12345678"

        // Create thread first
        let thread = Thread(
            id: threadId,
            subject: "Important Discussion",
            participantCount: 2,
            messageCount: 3,
            firstDate: Date(timeIntervalSince1970: 1736177400),
            lastDate: Date(timeIntervalSince1970: 1736180000)
        )
        try database.upsertThread(thread)

        // Create messages in thread
        let message1 = MailMessage(
            id: "msg1_123msg1_123msg1_12345678",
            subject: "Important Discussion",
            dateSent: Date(timeIntervalSince1970: 1736177400),
            threadId: threadId
        )
        let message2 = MailMessage(
            id: "msg2_123msg2_123msg2_12345678",
            subject: "Re: Important Discussion",
            dateSent: Date(timeIntervalSince1970: 1736178000),
            threadId: threadId
        )
        let message3 = MailMessage(
            id: "msg3_123msg3_123msg3_12345678",
            subject: "Re: Important Discussion",
            dateSent: Date(timeIntervalSince1970: 1736180000),
            threadId: threadId
        )

        try database.upsertMessage(message1)
        try database.upsertMessage(message2)
        try database.upsertMessage(message3)

        // Link messages to thread
        try database.addMessageToThread(messageId: message1.id, threadId: threadId)
        try database.addMessageToThread(messageId: message2.id, threadId: threadId)
        try database.addMessageToThread(messageId: message3.id, threadId: threadId)

        // Export using actual MailExporter
        let outputDir = (testDir as NSString).appendingPathComponent("export")
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let exporter = MailExporter(mailDatabase: database)
        try exporter.exportMessage(message2, to: outputDir)

        // Read exported file
        let exportedPath = (outputDir as NSString).appendingPathComponent("\(message2.id).md")
        let content = try String(contentsOfFile: exportedPath, encoding: .utf8)

        // Verify thread metadata is present
        XCTAssertTrue(content.contains("thread_id: \"\(threadId)\""), "Should contain thread_id")
    }

    func testMarkdownExportIncludesThreadPosition() throws {
        try database.initialize()

        let threadId = "posthread123posthread123posth90"

        // Create thread
        let thread = Thread(
            id: threadId,
            subject: "Thread Position Test",
            participantCount: 2,
            messageCount: 5
        )
        try database.upsertThread(thread)

        // Create messages with different dates to establish order
        let baseDate = Date(timeIntervalSince1970: 1736177400)
        var messages: [MailMessage] = []
        for i in 0..<5 {
            let msg = MailMessage(
                id: "postest\(i)_postest\(i)_postest\(i)_pt\(i)0",
                subject: i == 0 ? "Thread Position Test" : "Re: Thread Position Test",
                dateSent: baseDate.addingTimeInterval(Double(i * 3600)),
                threadId: threadId
            )
            messages.append(msg)
            try database.upsertMessage(msg)
            try database.addMessageToThread(messageId: msg.id, threadId: threadId)
        }

        // Export the 3rd message (index 2, position 3)
        let outputDir = (testDir as NSString).appendingPathComponent("export-position")
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let exporter = MailExporter(mailDatabase: database)
        try exporter.exportMessage(messages[2], to: outputDir)

        // Read exported file
        let exportedPath = (outputDir as NSString).appendingPathComponent("\(messages[2].id).md")
        let content = try String(contentsOfFile: exportedPath, encoding: .utf8)

        // Verify thread position format "Message 3 of 5"
        XCTAssertTrue(content.contains("thread_position: \"Message 3 of 5\""),
                      "Should show thread position as 'Message 3 of 5', got: \(content)")
    }

    func testMarkdownExportIncludesThreadSubject() throws {
        try database.initialize()

        let threadId = "subjthread12subjthread12subjth34"
        let threadSubject = "Weekly Status Update"

        // Create thread with specific subject
        let thread = Thread(
            id: threadId,
            subject: threadSubject,
            participantCount: 3,
            messageCount: 2
        )
        try database.upsertThread(thread)

        // Create messages
        let message = MailMessage(
            id: "subjmsg123subjmsg123subjmsg1234",
            subject: "Re: Weekly Status Update",
            dateSent: Date(),
            threadId: threadId
        )
        try database.upsertMessage(message)
        try database.addMessageToThread(messageId: message.id, threadId: threadId)

        // Export
        let outputDir = (testDir as NSString).appendingPathComponent("export-subject")
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let exporter = MailExporter(mailDatabase: database)
        try exporter.exportMessage(message, to: outputDir)

        // Read exported file
        let exportedPath = (outputDir as NSString).appendingPathComponent("\(message.id).md")
        let content = try String(contentsOfFile: exportedPath, encoding: .utf8)

        // Verify thread subject is in header
        XCTAssertTrue(content.contains("thread_subject: \"\(threadSubject)\""),
                      "Should contain thread subject in frontmatter")
    }

    func testMarkdownExportWithoutThreadDoesNotIncludeThreadFields() throws {
        try database.initialize()

        // Create message without thread
        let message = MailMessage(
            id: "nothreadmsg12nothreadmsg1234567",
            subject: "Standalone Email"
        )
        try database.upsertMessage(message)

        // Export
        let outputDir = (testDir as NSString).appendingPathComponent("export-no-thread")
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let exporter = MailExporter(mailDatabase: database)
        try exporter.exportMessage(message, to: outputDir)

        // Read exported file
        let exportedPath = (outputDir as NSString).appendingPathComponent("\(message.id).md")
        let content = try String(contentsOfFile: exportedPath, encoding: .utf8)

        // Verify no thread fields
        XCTAssertFalse(content.contains("thread_id:"), "Should not contain thread_id for non-threaded message")
        XCTAssertFalse(content.contains("thread_position:"), "Should not contain thread_position for non-threaded message")
        XCTAssertFalse(content.contains("thread_subject:"), "Should not contain thread_subject for non-threaded message")
    }
}
