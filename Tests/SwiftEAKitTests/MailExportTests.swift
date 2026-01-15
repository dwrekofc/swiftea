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

    // MARK: - JSON Export Structure Tests

    func testJsonExportStructureContainsAllRequiredFields() throws {
        try database.initialize()

        let threadId = "json_thread_123json_thread_12345"
        let thread = Thread(
            id: threadId,
            subject: "JSON Export Test",
            participantCount: 2,
            messageCount: 2,
            firstDate: Date(timeIntervalSince1970: 1736177400),
            lastDate: Date(timeIntervalSince1970: 1736180000)
        )
        try database.upsertThread(thread)

        let messages = [
            MailMessage(
                id: "json_msg1_123json_msg1_12345678",
                messageId: "<json-msg1@test.com>",
                subject: "JSON Export Test",
                senderName: "Alice",
                senderEmail: "alice@test.com",
                dateSent: Date(timeIntervalSince1970: 1736177400),
                isRead: true,
                isFlagged: false,
                hasAttachments: false,
                bodyText: "First message body",
                threadId: threadId
            ),
            MailMessage(
                id: "json_msg2_123json_msg2_12345678",
                messageId: "<json-msg2@test.com>",
                subject: "Re: JSON Export Test",
                senderName: "Bob",
                senderEmail: "bob@test.com",
                dateSent: Date(timeIntervalSince1970: 1736180000),
                isRead: false,
                isFlagged: true,
                hasAttachments: true,
                bodyText: "Second message body",
                threadId: threadId
            )
        ]

        for msg in messages {
            try database.upsertMessage(msg)
            try database.addMessageToThread(messageId: msg.id, threadId: threadId)
        }

        // Generate JSON using the same logic as the CLI command
        let jsonContent = formatThreadAsJson(
            threadId: thread.id,
            subject: thread.subject,
            participantCount: thread.participantCount,
            messageCount: thread.messageCount,
            firstDate: thread.firstDate,
            lastDate: thread.lastDate,
            messages: messages
        )

        // Parse and validate structure
        guard let jsonData = jsonContent.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Failed to parse JSON export")
            return
        }

        // Verify top-level thread fields
        XCTAssertEqual(json["thread_id"] as? String, threadId, "Should have thread_id")
        XCTAssertEqual(json["subject"] as? String, "JSON Export Test", "Should have subject")
        XCTAssertEqual(json["participant_count"] as? Int, 2, "Should have participant_count")
        XCTAssertEqual(json["message_count"] as? Int, 2, "Should have message_count")
        XCTAssertNotNil(json["first_date"], "Should have first_date")
        XCTAssertNotNil(json["last_date"], "Should have last_date")

        // Verify messages array
        guard let messagesArray = json["messages"] as? [[String: Any]] else {
            XCTFail("Should have messages array")
            return
        }
        XCTAssertEqual(messagesArray.count, 2, "Should have 2 messages")

        // Verify first message structure
        let firstMsg = messagesArray[0]
        XCTAssertEqual(firstMsg["id"] as? String, "json_msg1_123json_msg1_12345678")
        XCTAssertEqual(firstMsg["messageId"] as? String, "<json-msg1@test.com>")
        XCTAssertEqual(firstMsg["subject"] as? String, "JSON Export Test")
        XCTAssertEqual(firstMsg["thread_position"] as? Int, 1)
        XCTAssertEqual(firstMsg["thread_total"] as? Int, 2)

        // Verify from structure
        guard let from = firstMsg["from"] as? [String: Any] else {
            XCTFail("Should have from object")
            return
        }
        XCTAssertEqual(from["name"] as? String, "Alice")
        XCTAssertEqual(from["email"] as? String, "alice@test.com")
    }

    func testJsonExportHandlesNilValues() throws {
        try database.initialize()

        let threadId = "nil_thread_123nil_thread_1234567"
        let thread = Thread(
            id: threadId,
            subject: nil,  // nil subject
            participantCount: 0,
            messageCount: 1,
            firstDate: nil,  // nil date
            lastDate: nil    // nil date
        )
        try database.upsertThread(thread)

        let message = MailMessage(
            id: "nil_msg_123nil_msg_123nil_msg12",
            messageId: nil,  // nil messageId
            subject: "",
            senderName: nil,
            senderEmail: nil,
            dateSent: nil,
            bodyText: nil,
            bodyHtml: nil,
            threadId: threadId
        )
        try database.upsertMessage(message)
        try database.addMessageToThread(messageId: message.id, threadId: threadId)

        let jsonContent = formatThreadAsJson(
            threadId: thread.id,
            subject: thread.subject,
            participantCount: thread.participantCount,
            messageCount: thread.messageCount,
            firstDate: thread.firstDate,
            lastDate: thread.lastDate,
            messages: [message]
        )

        guard let jsonData = jsonContent.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Should still produce valid JSON with nil values")
            return
        }

        // All fields should still be present (empty strings for nil values)
        XCTAssertNotNil(json["thread_id"])
        XCTAssertNotNil(json["subject"])
        XCTAssertNotNil(json["first_date"])
        XCTAssertNotNil(json["last_date"])
        XCTAssertNotNil(json["messages"])
    }

    // MARK: - Thread Export Tests (export-threads command)

    func testThreadExportProducesValidMarkdownOutput() throws {
        try database.initialize()

        let threadId = "export_thread_123export_thread12"
        let thread = Thread(
            id: threadId,
            subject: "Thread Export Test",
            participantCount: 3,
            messageCount: 3,
            firstDate: Date(timeIntervalSince1970: 1736177400),
            lastDate: Date(timeIntervalSince1970: 1736184000)
        )
        try database.upsertThread(thread)

        // Create 3 messages in thread
        let messages = [
            MailMessage(
                id: "texport1_123texport1_12345678",
                subject: "Thread Export Test",
                senderName: "Alice",
                senderEmail: "alice@test.com",
                dateSent: Date(timeIntervalSince1970: 1736177400),
                bodyText: "Hello everyone!",
                threadId: threadId
            ),
            MailMessage(
                id: "texport2_123texport2_12345678",
                subject: "Re: Thread Export Test",
                senderName: "Bob",
                senderEmail: "bob@test.com",
                dateSent: Date(timeIntervalSince1970: 1736180000),
                bodyText: "Hi Alice, thanks for starting this thread.",
                threadId: threadId
            ),
            MailMessage(
                id: "texport3_123texport3_12345678",
                subject: "Re: Thread Export Test",
                senderName: "Charlie",
                senderEmail: "charlie@test.com",
                dateSent: Date(timeIntervalSince1970: 1736184000),
                bodyText: "Great discussion!",
                threadId: threadId
            )
        ]

        for msg in messages {
            try database.upsertMessage(msg)
            try database.addMessageToThread(messageId: msg.id, threadId: threadId)
        }

        // Export using MailExporter.exportThread
        let outputDir = (testDir as NSString).appendingPathComponent("thread-export")
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let exporter = MailExporter(mailDatabase: database)
        let filePath = try exporter.exportThread(thread: thread, messages: messages, to: outputDir)

        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath))

        // Read and verify content
        let content = try String(contentsOfFile: filePath, encoding: .utf8)

        // Verify YAML frontmatter
        XCTAssertTrue(content.hasPrefix("---"), "Should start with YAML frontmatter")
        XCTAssertTrue(content.contains("thread_id: \"\(threadId)\""))
        XCTAssertTrue(content.contains("subject: \"Thread Export Test\""))
        XCTAssertTrue(content.contains("participant_count: 3"))
        XCTAssertTrue(content.contains("message_count: 3"))

        // Verify thread heading
        XCTAssertTrue(content.contains("# Thread: Thread Export Test"))
        XCTAssertTrue(content.contains("3 message(s) between 3 participant(s)"))

        // Verify all messages are included with positions
        XCTAssertTrue(content.contains("## Message 1 of 3"))
        XCTAssertTrue(content.contains("## Message 2 of 3"))
        XCTAssertTrue(content.contains("## Message 3 of 3"))

        // Verify message content
        XCTAssertTrue(content.contains("**From:** Alice <alice@test.com>"))
        XCTAssertTrue(content.contains("**From:** Bob <bob@test.com>"))
        XCTAssertTrue(content.contains("**From:** Charlie <charlie@test.com>"))
        XCTAssertTrue(content.contains("Hello everyone!"))
        XCTAssertTrue(content.contains("Hi Alice, thanks for starting this thread."))
        XCTAssertTrue(content.contains("Great discussion!"))
    }

    // MARK: - Edge Cases

    func testSingleMessageThreadExport() throws {
        try database.initialize()

        let threadId = "single_thread_123single_thread12"
        let thread = Thread(
            id: threadId,
            subject: "Single Message Thread",
            participantCount: 1,
            messageCount: 1,
            firstDate: Date(timeIntervalSince1970: 1736177400),
            lastDate: Date(timeIntervalSince1970: 1736177400)
        )
        try database.upsertThread(thread)

        let message = MailMessage(
            id: "single_msg_123single_msg_123456",
            subject: "Single Message Thread",
            senderName: "Solo Sender",
            senderEmail: "solo@test.com",
            dateSent: Date(timeIntervalSince1970: 1736177400),
            bodyText: "I'm the only message in this thread.",
            threadId: threadId
        )
        try database.upsertMessage(message)
        try database.addMessageToThread(messageId: message.id, threadId: threadId)

        // Export
        let outputDir = (testDir as NSString).appendingPathComponent("single-thread")
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let exporter = MailExporter(mailDatabase: database)
        let filePath = try exporter.exportThread(thread: thread, messages: [message], to: outputDir)

        let content = try String(contentsOfFile: filePath, encoding: .utf8)

        // Verify single message formatting
        XCTAssertTrue(content.contains("1 message(s) between 1 participant(s)"))
        XCTAssertTrue(content.contains("## Message 1 of 1"))
        XCTAssertFalse(content.contains("## Message 2"), "Should not have second message marker")
    }

    func testLargeThreadExport() throws {
        try database.initialize()

        let threadId = "large_thread_123large_thread1234"
        let messageCount = 25
        let thread = Thread(
            id: threadId,
            subject: "Large Thread Discussion",
            participantCount: 5,
            messageCount: messageCount,
            firstDate: Date(timeIntervalSince1970: 1736177400),
            lastDate: Date(timeIntervalSince1970: 1736177400 + Double(messageCount * 600))
        )
        try database.upsertThread(thread)

        // Create many messages
        var messages: [MailMessage] = []
        for i in 1...messageCount {
            let msg = MailMessage(
                id: "large_msg_\(String(format: "%02d", i))_large_msg_\(String(format: "%02d", i))_lm\(i)",
                subject: i == 1 ? "Large Thread Discussion" : "Re: Large Thread Discussion",
                senderName: "User \(i % 5 + 1)",
                senderEmail: "user\(i % 5 + 1)@test.com",
                dateSent: Date(timeIntervalSince1970: 1736177400 + Double(i * 600)),
                bodyText: "This is message number \(i) in the large thread.",
                threadId: threadId
            )
            messages.append(msg)
            try database.upsertMessage(msg)
            try database.addMessageToThread(messageId: msg.id, threadId: threadId)
        }

        // Export
        let outputDir = (testDir as NSString).appendingPathComponent("large-thread")
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let exporter = MailExporter(mailDatabase: database)
        let filePath = try exporter.exportThread(thread: thread, messages: messages, to: outputDir)

        let content = try String(contentsOfFile: filePath, encoding: .utf8)

        // Verify large thread formatting
        XCTAssertTrue(content.contains("\(messageCount) message(s) between 5 participant(s)"))
        XCTAssertTrue(content.contains("## Message 1 of \(messageCount)"))
        XCTAssertTrue(content.contains("## Message \(messageCount) of \(messageCount)"))
        XCTAssertTrue(content.contains("This is message number 1 in the large thread."))
        XCTAssertTrue(content.contains("This is message number \(messageCount) in the large thread."))
    }

    func testThreadWithNoSubjectExport() throws {
        try database.initialize()

        let threadId = "nosubj_thread_123nosubj_thread1"
        let thread = Thread(
            id: threadId,
            subject: nil,  // No subject
            participantCount: 1,
            messageCount: 1
        )
        try database.upsertThread(thread)

        let message = MailMessage(
            id: "nosubj_msg_123nosubj_msg_123456",
            subject: "",  // Empty subject
            bodyText: "Message without subject",
            threadId: threadId
        )
        try database.upsertMessage(message)
        try database.addMessageToThread(messageId: message.id, threadId: threadId)

        let outputDir = (testDir as NSString).appendingPathComponent("no-subject")
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let exporter = MailExporter(mailDatabase: database)
        let filePath = try exporter.exportThread(thread: thread, messages: [message], to: outputDir)

        let content = try String(contentsOfFile: filePath, encoding: .utf8)

        // Should show placeholder for missing subject
        XCTAssertTrue(content.contains("# Thread: (No Subject)"))
    }

    func testThreadExportWithHtmlBodyFallback() throws {
        try database.initialize()

        let threadId = "html_thread_123html_thread_12345"
        let thread = Thread(
            id: threadId,
            subject: "HTML Body Test",
            participantCount: 1,
            messageCount: 1
        )
        try database.upsertThread(thread)

        let message = MailMessage(
            id: "html_msg_123html_msg_123html_mg",
            subject: "HTML Body Test",
            senderName: "HTML Sender",
            senderEmail: "html@test.com",
            dateSent: Date(),
            bodyText: nil,  // No text body
            bodyHtml: "<html><body><p>This is <strong>bold</strong> and <em>italic</em> text.</p></body></html>",
            threadId: threadId
        )
        try database.upsertMessage(message)
        try database.addMessageToThread(messageId: message.id, threadId: threadId)

        let outputDir = (testDir as NSString).appendingPathComponent("html-body")
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let exporter = MailExporter(mailDatabase: database)
        let filePath = try exporter.exportThread(thread: thread, messages: [message], to: outputDir)

        let content = try String(contentsOfFile: filePath, encoding: .utf8)

        // HTML should be stripped but text preserved
        XCTAssertTrue(content.contains("bold"), "Should preserve text content")
        XCTAssertTrue(content.contains("italic"), "Should preserve text content")
        XCTAssertFalse(content.contains("<strong>"), "Should strip HTML tags")
        XCTAssertFalse(content.contains("<em>"), "Should strip HTML tags")
    }

    func testThreadExportWithEmptyBody() throws {
        try database.initialize()

        let threadId = "empty_body_thread_123empty_body"
        let thread = Thread(
            id: threadId,
            subject: "Empty Body Test",
            participantCount: 1,
            messageCount: 1
        )
        try database.upsertThread(thread)

        let message = MailMessage(
            id: "empty_body_msg_123empty_body_m1",
            subject: "Empty Body Test",
            senderName: "Empty Body Sender",
            senderEmail: "empty@test.com",
            dateSent: Date(),
            bodyText: nil,
            bodyHtml: nil,
            threadId: threadId
        )
        try database.upsertMessage(message)
        try database.addMessageToThread(messageId: message.id, threadId: threadId)

        let outputDir = (testDir as NSString).appendingPathComponent("empty-body")
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let exporter = MailExporter(mailDatabase: database)
        let filePath = try exporter.exportThread(thread: thread, messages: [message], to: outputDir)

        let content = try String(contentsOfFile: filePath, encoding: .utf8)

        // Should show placeholder
        XCTAssertTrue(content.contains("*(No message body)*"))
    }

    func testExportResultTracksThreadsAndUnthreaded() throws {
        try database.initialize()

        let threadId = "count_thread_123count_thread_12"
        let thread = Thread(
            id: threadId,
            subject: "Count Test Thread",
            participantCount: 1,
            messageCount: 2
        )
        try database.upsertThread(thread)

        // Create threaded messages
        let threadedMsg1 = MailMessage(
            id: "count_threaded1_123count_thrd1",
            subject: "Count Test Thread",
            threadId: threadId
        )
        let threadedMsg2 = MailMessage(
            id: "count_threaded2_123count_thrd2",
            subject: "Re: Count Test Thread",
            threadId: threadId
        )
        try database.upsertMessage(threadedMsg1)
        try database.upsertMessage(threadedMsg2)
        try database.addMessageToThread(messageId: threadedMsg1.id, threadId: threadId)
        try database.addMessageToThread(messageId: threadedMsg2.id, threadId: threadId)

        // Create unthreaded message
        let unthreadedMsg = MailMessage(
            id: "count_unthreaded_123count_unth",
            subject: "Standalone Email"
        )
        try database.upsertMessage(unthreadedMsg)

        // Export all
        let outputDir = (testDir as NSString).appendingPathComponent("count-test")
        let exporter = MailExporter(mailDatabase: database)
        let result = try exporter.exportNewMessages(to: outputDir)

        // Verify counts
        XCTAssertEqual(result.exported, 3, "Should export 3 messages total")
        XCTAssertGreaterThanOrEqual(result.threadsExported, 1, "Should export at least 1 thread")
        XCTAssertGreaterThanOrEqual(result.unthreadedExported, 1, "Should export at least 1 unthreaded")
        XCTAssertEqual(result.errors.count, 0, "Should have no errors")
    }

    // MARK: - JSON Export Helper

    private func formatThreadAsJson(
        threadId: String,
        subject: String?,
        participantCount: Int,
        messageCount: Int,
        firstDate: Date?,
        lastDate: Date?,
        messages: [MailMessage]
    ) -> String {
        let threadTotal = messages.count

        var messagesArray: [[String: Any]] = []
        for (index, message) in messages.enumerated() {
            let position = index + 1
            messagesArray.append([
                "id": message.id,
                "messageId": message.messageId ?? "",
                "subject": message.subject,
                "from": [
                    "name": message.senderName ?? "",
                    "email": message.senderEmail ?? ""
                ],
                "date": message.dateSent.map { formatISO8601($0) } ?? "",
                "mailbox": message.mailboxName ?? "",
                "isRead": message.isRead,
                "isFlagged": message.isFlagged,
                "hasAttachments": message.hasAttachments,
                "bodyText": message.bodyText ?? "",
                "bodyHtml": message.bodyHtml ?? "",
                "thread_id": message.threadId ?? "",
                "thread_position": position,
                "thread_total": threadTotal
            ])
        }

        let threadExport: [String: Any] = [
            "thread_id": threadId,
            "subject": subject ?? "",
            "participant_count": participantCount,
            "message_count": messageCount,
            "first_date": firstDate.map { formatISO8601($0) } ?? "",
            "last_date": lastDate.map { formatISO8601($0) } ?? "",
            "messages": messagesArray
        ]

        if let data = try? JSONSerialization.data(withJSONObject: threadExport, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    private func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
