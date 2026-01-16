import XCTest
@testable import SwiftEAKit

final class ThreadDetectionServiceTests: XCTestCase {
    var service: ThreadDetectionService!
    var testDir: String!
    var database: MailDatabase!

    override func setUp() {
        super.setUp()
        service = ThreadDetectionService()

        // Setup test database
        testDir = NSTemporaryDirectory() + "swiftea-thread-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        let dbPath = (testDir as NSString).appendingPathComponent("mail.db")
        database = MailDatabase(databasePath: dbPath)
    }

    override func tearDown() {
        service = nil
        database?.close()
        try? FileManager.default.removeItem(atPath: testDir)
        database = nil
        super.tearDown()
    }

    // MARK: - Thread ID Detection (No Database)

    func testDetectThreadIdForStandaloneMessage() {
        let threadId = service.detectThreadId(
            messageId: "<standalone@example.com>",
            inReplyTo: nil,
            references: nil,
            subject: "Hello World"
        )

        XCTAssertEqual(threadId.count, 32)
    }

    func testDetectThreadIdForReplyWithReferences() {
        let threadId = service.detectThreadId(
            messageId: "<reply@example.com>",
            inReplyTo: "<parent@example.com>",
            references: "<root@example.com> <parent@example.com>",
            subject: "Re: Hello World"
        )

        XCTAssertEqual(threadId.count, 32)
    }

    func testDetectThreadIdForReplyWithInReplyToOnly() {
        let threadId = service.detectThreadId(
            messageId: "<reply@example.com>",
            inReplyTo: "<parent@example.com>",
            references: nil,
            subject: "Re: Hello World"
        )

        XCTAssertEqual(threadId.count, 32)
    }

    func testDetectThreadIdWithSubjectFallback() {
        // Message with no threading headers falls back to subject
        let threadId = service.detectThreadId(
            messageId: nil,
            inReplyTo: nil,
            references: nil,
            subject: "Important Topic"
        )

        XCTAssertEqual(threadId.count, 32)
    }

    func testDetectThreadIdIsDeterministic() {
        let id1 = service.detectThreadId(
            messageId: "<test@example.com>",
            inReplyTo: nil,
            references: nil,
            subject: "Test"
        )

        let id2 = service.detectThreadId(
            messageId: "<test@example.com>",
            inReplyTo: nil,
            references: nil,
            subject: "Test"
        )

        XCTAssertEqual(id1, id2)
    }

    func testDetectThreadIdFromParsedHeaders() {
        let headers = ThreadingHeaderParser.ThreadingHeaders(
            messageId: "<msg@example.com>",
            inReplyTo: "<parent@example.com>",
            references: ["<root@example.com>"]
        )

        let threadId = service.detectThreadId(from: headers, subject: "Test")

        XCTAssertEqual(threadId.count, 32)
    }

    func testDetectThreadIdFromMailMessage() {
        let message = MailMessage(
            id: "internal-id",
            messageId: "<msg@example.com>",
            subject: "Test",
            inReplyTo: "<parent@example.com>",
            references: ["<root@example.com>"]
        )

        let threadId = service.detectThreadId(from: message)

        XCTAssertEqual(threadId.count, 32)
    }

    // MARK: - Same Thread Grouping

    func testAllMessagesInThreadGetSameId() {
        // Root message
        let rootId = service.detectThreadId(
            messageId: "<root@example.com>",
            inReplyTo: nil,
            references: nil,
            subject: "Discussion"
        )

        // First reply
        let reply1Id = service.detectThreadId(
            messageId: "<reply1@example.com>",
            inReplyTo: "<root@example.com>",
            references: "<root@example.com>",
            subject: "Re: Discussion"
        )

        // Second reply (to first reply)
        let reply2Id = service.detectThreadId(
            messageId: "<reply2@example.com>",
            inReplyTo: "<reply1@example.com>",
            references: "<root@example.com> <reply1@example.com>",
            subject: "Re: Re: Discussion"
        )

        XCTAssertEqual(rootId, reply1Id)
        XCTAssertEqual(rootId, reply2Id)
    }

    func testDifferentThreadsGetDifferentIds() {
        let thread1 = service.detectThreadId(
            messageId: "<thread1@example.com>",
            inReplyTo: nil,
            references: nil,
            subject: "First Thread"
        )

        let thread2 = service.detectThreadId(
            messageId: "<thread2@example.com>",
            inReplyTo: nil,
            references: nil,
            subject: "Second Thread"
        )

        XCTAssertNotEqual(thread1, thread2)
    }

    // MARK: - Full Thread Processing with Database

    func testProcessMessageCreatesNewThread() throws {
        try database.initialize()

        let message = MailMessage(
            id: "msg-1",
            messageId: "<test@example.com>",
            subject: "New Thread",
            senderEmail: "sender@example.com",
            dateReceived: Date()
        )
        try database.upsertMessage(message)

        let result = try service.processMessageForThreading(message, database: database)

        XCTAssertTrue(result.isNewThread)
        XCTAssertEqual(result.threadId.count, 32)

        // Verify thread was created
        let thread = try database.getThread(id: result.threadId)
        XCTAssertNotNil(thread)
        XCTAssertEqual(thread?.subject, "New Thread")
        XCTAssertEqual(thread?.messageCount, 1)
        XCTAssertEqual(thread?.participantCount, 1)
    }

    func testProcessMessageJoinsExistingThread() throws {
        try database.initialize()

        // Create first message (thread root)
        let msg1 = MailMessage(
            id: "msg-1",
            messageId: "<root@example.com>",
            subject: "Thread Topic",
            senderEmail: "alice@example.com",
            dateReceived: Date(timeIntervalSinceNow: -3600) // 1 hour ago
        )
        try database.upsertMessage(msg1)

        let result1 = try service.processMessageForThreading(msg1, database: database)
        XCTAssertTrue(result1.isNewThread)

        // Create reply message
        let msg2 = MailMessage(
            id: "msg-2",
            messageId: "<reply@example.com>",
            subject: "Re: Thread Topic",
            senderEmail: "bob@example.com",
            dateReceived: Date(),
            inReplyTo: "<root@example.com>",
            references: ["<root@example.com>"]
        )
        try database.upsertMessage(msg2)

        let result2 = try service.processMessageForThreading(msg2, database: database)

        XCTAssertFalse(result2.isNewThread)
        XCTAssertEqual(result1.threadId, result2.threadId)

        // Verify thread was updated
        let thread = try database.getThread(id: result1.threadId)
        XCTAssertEqual(thread?.messageCount, 2)
        XCTAssertEqual(thread?.participantCount, 2)
    }

    func testProcessMessageUpdatesMessageThreadId() throws {
        try database.initialize()

        let message = MailMessage(
            id: "msg-1",
            messageId: "<test@example.com>",
            subject: "Test Message"
        )
        try database.upsertMessage(message)

        let result = try service.processMessageForThreading(message, database: database)

        // Fetch the updated message
        let updatedMessage = try database.getMessage(id: "msg-1")

        XCTAssertEqual(updatedMessage?.threadId, result.threadId)
    }

    func testProcessMessageAddsToJunctionTable() throws {
        try database.initialize()

        let message = MailMessage(
            id: "msg-1",
            messageId: "<test@example.com>",
            subject: "Test Message"
        )
        try database.upsertMessage(message)

        let result = try service.processMessageForThreading(message, database: database)

        // Verify junction table entry
        let messageIds = try database.getMessageIdsInThread(threadId: result.threadId)
        XCTAssertTrue(messageIds.contains("msg-1"))
    }

    func testProcessMessagesInBatch() throws {
        try database.initialize()

        // Create multiple messages
        let messages = [
            MailMessage(id: "msg-1", messageId: "<root@example.com>", subject: "Topic A"),
            MailMessage(id: "msg-2", messageId: "<reply1@example.com>", subject: "Re: Topic A",
                       inReplyTo: "<root@example.com>", references: ["<root@example.com>"]),
            MailMessage(id: "msg-3", messageId: "<other@example.com>", subject: "Topic B")
        ]

        for message in messages {
            try database.upsertMessage(message)
        }

        let results = try service.processMessagesForThreading(messages, database: database)

        XCTAssertEqual(results.count, 3)
        // First two should be same thread
        XCTAssertEqual(results[0].threadId, results[1].threadId)
        // Third should be different
        XCTAssertNotEqual(results[0].threadId, results[2].threadId)
    }

    // MARK: - Thread Metadata Updates

    func testUpdateThreadMetadata() throws {
        try database.initialize()

        // Create a thread and messages manually
        let thread = Thread(id: "test-thread", subject: "Test")
        try database.upsertThread(thread)

        let messages = [
            MailMessage(id: "msg-1", subject: "Msg 1", senderEmail: "alice@example.com",
                       dateReceived: Date(timeIntervalSince1970: 1000)),
            MailMessage(id: "msg-2", subject: "Msg 2", senderEmail: "bob@example.com",
                       dateReceived: Date(timeIntervalSince1970: 2000)),
            MailMessage(id: "msg-3", subject: "Msg 3", senderEmail: "alice@example.com",
                       dateReceived: Date(timeIntervalSince1970: 3000))
        ]

        for msg in messages {
            try database.upsertMessage(msg)
            try database.addMessageToThread(messageId: msg.id, threadId: "test-thread")
        }

        // Update metadata
        try service.updateThreadMetadata(threadId: "test-thread", database: database)

        let updatedThread = try database.getThread(id: "test-thread")
        XCTAssertEqual(updatedThread?.messageCount, 3)
        XCTAssertEqual(updatedThread?.participantCount, 2) // alice and bob
        XCTAssertEqual(updatedThread?.firstDate?.timeIntervalSince1970, 1000)
        XCTAssertEqual(updatedThread?.lastDate?.timeIntervalSince1970, 3000)
    }

    func testUpdateThreadMetadataPreservesSubject() throws {
        try database.initialize()

        let thread = Thread(id: "preserve-subject", subject: "Original Subject")
        try database.upsertThread(thread)

        let message = MailMessage(id: "msg-1", subject: "Re: Different Subject")
        try database.upsertMessage(message)
        try database.addMessageToThread(messageId: "msg-1", threadId: "preserve-subject")

        try service.updateThreadMetadata(threadId: "preserve-subject", database: database)

        let updatedThread = try database.getThread(id: "preserve-subject")
        XCTAssertEqual(updatedThread?.subject, "Original Subject")
    }

    func testUpdateEmptyThreadDoesNotCrash() throws {
        try database.initialize()

        // Should not throw for nonexistent thread
        try service.updateThreadMetadata(threadId: "nonexistent", database: database)
    }

    // MARK: - Thread Date Tracking

    func testThreadDateRangeIsCorrect() throws {
        try database.initialize()

        let earlyDate = Date(timeIntervalSince1970: 1000)
        let middleDate = Date(timeIntervalSince1970: 2000)
        let lateDate = Date(timeIntervalSince1970: 3000)

        // Create messages in non-chronological order - all part of the same thread
        // Thread root is early, middle replies to early, late replies to middle
        let messages = [
            MailMessage(id: "msg-middle", messageId: "<middle@example.com>", subject: "Re: Thread",
                       dateReceived: middleDate,
                       inReplyTo: "<early@example.com>", references: ["<early@example.com>"]),
            MailMessage(id: "msg-late", messageId: "<late@example.com>", subject: "Re: Thread",
                       dateReceived: lateDate,
                       inReplyTo: "<middle@example.com>", references: ["<early@example.com>", "<middle@example.com>"]),
            MailMessage(id: "msg-early", messageId: "<early@example.com>", subject: "Thread",
                       dateReceived: earlyDate)
        ]

        for msg in messages {
            try database.upsertMessage(msg)
        }

        // Process all messages - order shouldn't matter for final result
        let result1 = try service.processMessageForThreading(messages[0], database: database)
        let result2 = try service.processMessageForThreading(messages[1], database: database)
        let result3 = try service.processMessageForThreading(messages[2], database: database)

        // All should be in the same thread
        XCTAssertEqual(result1.threadId, result2.threadId)
        XCTAssertEqual(result1.threadId, result3.threadId)

        let thread = try database.getThread(id: result1.threadId)
        XCTAssertEqual(thread?.firstDate?.timeIntervalSince1970, 1000)
        XCTAssertEqual(thread?.lastDate?.timeIntervalSince1970, 3000)
        XCTAssertEqual(thread?.messageCount, 3)
    }

    // MARK: - Convenience Methods

    func testIsReply() {
        let reply = MailMessage(id: "msg-1", subject: "Re: Test",
                               inReplyTo: "<parent@example.com>", references: [])
        XCTAssertTrue(service.isReply(reply))

        let standalone = MailMessage(id: "msg-2", subject: "Test")
        XCTAssertFalse(service.isReply(standalone))

        let withReferences = MailMessage(id: "msg-3", subject: "Test",
                                        references: ["<root@example.com>"])
        XCTAssertTrue(service.isReply(withReferences))
    }

    func testIsForwarded() {
        let forwarded = MailMessage(id: "msg-1", subject: "Fwd: Test")
        XCTAssertTrue(service.isForwarded(forwarded))

        let notForwarded = MailMessage(id: "msg-2", subject: "Test")
        XCTAssertFalse(service.isForwarded(notForwarded))

        let fwVariant = MailMessage(id: "msg-3", subject: "Fw: Test")
        XCTAssertTrue(service.isForwarded(fwVariant))
    }

    func testNormalizeSubject() {
        XCTAssertEqual(service.normalizeSubject("Re: Test Subject"), "test subject")
        XCTAssertEqual(service.normalizeSubject("Fwd: Test Subject"), "test subject")
        XCTAssertEqual(service.normalizeSubject("RE: RE: Test"), "test")
        XCTAssertEqual(service.normalizeSubject("Test Subject"), "test subject")
    }

    // MARK: - Result Equatable

    func testThreadDetectionResultEquatable() {
        let headers = ThreadingHeaderParser.ThreadingHeaders(
            messageId: "<test@example.com>",
            inReplyTo: nil,
            references: []
        )

        let result1 = ThreadDetectionService.ThreadDetectionResult(
            threadId: "abc123",
            isNewThread: true,
            headers: headers
        )

        let result2 = ThreadDetectionService.ThreadDetectionResult(
            threadId: "abc123",
            isNewThread: true,
            headers: headers
        )

        XCTAssertEqual(result1, result2)
    }

    // MARK: - Edge Cases

    func testProcessSameMessageTwice() throws {
        try database.initialize()

        let message = MailMessage(
            id: "msg-1",
            messageId: "<test@example.com>",
            subject: "Test"
        )
        try database.upsertMessage(message)

        let result1 = try service.processMessageForThreading(message, database: database)
        XCTAssertTrue(result1.isNewThread)

        // Processing same message again should not create new thread
        let result2 = try service.processMessageForThreading(message, database: database)
        XCTAssertFalse(result2.isNewThread)
        XCTAssertEqual(result1.threadId, result2.threadId)
    }

    func testProcessMessageWithNoHeaders() throws {
        try database.initialize()

        let message = MailMessage(
            id: "msg-no-headers",
            subject: "No Threading Headers"
        )
        try database.upsertMessage(message)

        // Should still work using subject fallback
        let result = try service.processMessageForThreading(message, database: database)

        XCTAssertTrue(result.isNewThread)
        XCTAssertEqual(result.threadId.count, 32)
    }

    func testProcessMessageWithEmptySubject() throws {
        try database.initialize()

        let message = MailMessage(
            id: "msg-empty-subject",
            messageId: "<test@example.com>",
            subject: ""
        )
        try database.upsertMessage(message)

        let result = try service.processMessageForThreading(message, database: database)

        XCTAssertTrue(result.isNewThread)
        XCTAssertEqual(result.threadId.count, 32)
    }

    // MARK: - Thread Metadata Extraction

    func testExtractThreadMetadataSubjectFromFirstMessage() throws {
        try database.initialize()

        // Create messages with different dates - first message has original subject
        let firstDate = Date(timeIntervalSince1970: 1000)
        let secondDate = Date(timeIntervalSince1970: 2000)

        let msg1 = MailMessage(
            id: "msg-1",
            messageId: "<first@example.com>",
            subject: "Original Subject",
            senderEmail: "alice@example.com",
            dateReceived: firstDate
        )
        let msg2 = MailMessage(
            id: "msg-2",
            messageId: "<second@example.com>",
            subject: "Re: Original Subject",
            senderEmail: "bob@example.com",
            dateReceived: secondDate,
            inReplyTo: "<first@example.com>",
            references: ["<first@example.com>"]
        )

        try database.upsertMessage(msg1)
        try database.upsertMessage(msg2)

        // Process both messages to create thread
        let result1 = try service.processMessageForThreading(msg1, database: database)
        _ = try service.processMessageForThreading(msg2, database: database)

        // Extract metadata
        let metadata = try service.extractThreadMetadata(threadId: result1.threadId, database: database)

        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.subject, "Original Subject")
    }

    func testExtractThreadMetadataParticipantList() throws {
        try database.initialize()

        let thread = Thread(id: "test-participants", subject: "Participants Test")
        try database.upsertThread(thread)

        // Create messages from multiple senders
        let messages = [
            MailMessage(id: "msg-1", subject: "Test",
                       senderName: "Alice Smith", senderEmail: "alice@example.com",
                       dateReceived: Date(timeIntervalSince1970: 1000)),
            MailMessage(id: "msg-2", subject: "Re: Test",
                       senderName: "Bob Jones", senderEmail: "bob@example.com",
                       dateReceived: Date(timeIntervalSince1970: 2000)),
            MailMessage(id: "msg-3", subject: "Re: Test",
                       senderEmail: "alice@example.com",
                       dateReceived: Date(timeIntervalSince1970: 3000)),
            MailMessage(id: "msg-4", subject: "Re: Test",
                       senderName: "Charlie Brown", senderEmail: "CHARLIE@example.com",
                       dateReceived: Date(timeIntervalSince1970: 4000))
        ]

        for msg in messages {
            try database.upsertMessage(msg)
            try database.addMessageToThread(messageId: msg.id, threadId: "test-participants")
        }

        // Extract metadata
        let metadata = try service.extractThreadMetadata(threadId: "test-participants", database: database)

        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.participants.count, 3) // alice, bob, charlie (alice is deduplicated)

        // Verify participant details (sorted by email)
        let participants = metadata!.participants
        XCTAssertEqual(participants[0].email, "alice@example.com")
        XCTAssertEqual(participants[0].name, "Alice Smith")
        XCTAssertEqual(participants[1].email, "bob@example.com")
        XCTAssertEqual(participants[1].name, "Bob Jones")
        XCTAssertEqual(participants[2].email, "charlie@example.com") // lowercased
        XCTAssertEqual(participants[2].name, "Charlie Brown")
    }

    func testExtractThreadMetadataDateRange() throws {
        try database.initialize()

        let thread = Thread(id: "test-dates", subject: "Date Test")
        try database.upsertThread(thread)

        let earlyDate = Date(timeIntervalSince1970: 1000)
        let middleDate = Date(timeIntervalSince1970: 2000)
        let lateDate = Date(timeIntervalSince1970: 3000)

        // Create messages in non-chronological order
        let messages = [
            MailMessage(id: "msg-middle", subject: "Middle", dateReceived: middleDate),
            MailMessage(id: "msg-late", subject: "Late", dateReceived: lateDate),
            MailMessage(id: "msg-early", subject: "Early", dateReceived: earlyDate)
        ]

        for msg in messages {
            try database.upsertMessage(msg)
            try database.addMessageToThread(messageId: msg.id, threadId: "test-dates")
        }

        let metadata = try service.extractThreadMetadata(threadId: "test-dates", database: database)

        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.firstMessageDate?.timeIntervalSince1970, 1000)
        XCTAssertEqual(metadata?.lastMessageDate?.timeIntervalSince1970, 3000)
        XCTAssertEqual(metadata?.messageCount, 3)
    }

    func testExtractThreadMetadataEmptyThread() throws {
        try database.initialize()

        // No thread exists
        let metadata = try service.extractThreadMetadata(threadId: "nonexistent", database: database)

        XCTAssertNil(metadata)
    }

    func testExtractThreadMetadataSingleMessage() throws {
        try database.initialize()

        let message = MailMessage(
            id: "single-msg",
            messageId: "<single@example.com>",
            subject: "Single Message Thread",
            senderName: "Solo Sender",
            senderEmail: "solo@example.com",
            dateReceived: Date(timeIntervalSince1970: 5000)
        )
        try database.upsertMessage(message)

        let result = try service.processMessageForThreading(message, database: database)

        let metadata = try service.extractThreadMetadata(threadId: result.threadId, database: database)

        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.subject, "Single Message Thread")
        XCTAssertEqual(metadata?.participants.count, 1)
        XCTAssertEqual(metadata?.participants.first?.email, "solo@example.com")
        XCTAssertEqual(metadata?.participants.first?.name, "Solo Sender")
        XCTAssertEqual(metadata?.firstMessageDate, metadata?.lastMessageDate)
        XCTAssertEqual(metadata?.messageCount, 1)
    }

    func testExtractThreadMetadataMultipleThreads() throws {
        try database.initialize()

        // Create two separate threads
        let msg1 = MailMessage(
            id: "thread1-msg",
            messageId: "<thread1@example.com>",
            subject: "Thread One",
            senderEmail: "alice@example.com",
            dateReceived: Date(timeIntervalSince1970: 1000)
        )
        let msg2 = MailMessage(
            id: "thread2-msg",
            messageId: "<thread2@example.com>",
            subject: "Thread Two",
            senderEmail: "bob@example.com",
            dateReceived: Date(timeIntervalSince1970: 2000)
        )

        try database.upsertMessage(msg1)
        try database.upsertMessage(msg2)

        let result1 = try service.processMessageForThreading(msg1, database: database)
        let result2 = try service.processMessageForThreading(msg2, database: database)

        // Extract metadata for both threads
        let metadataDict = try service.extractThreadMetadata(
            threadIds: [result1.threadId, result2.threadId],
            database: database
        )

        XCTAssertEqual(metadataDict.count, 2)
        XCTAssertEqual(metadataDict[result1.threadId]?.subject, "Thread One")
        XCTAssertEqual(metadataDict[result2.threadId]?.subject, "Thread Two")
    }

    func testExtractThreadMetadataParticipantNameUpdate() throws {
        try database.initialize()

        let thread = Thread(id: "test-name-update", subject: "Name Update Test")
        try database.upsertThread(thread)

        // First message from alice without name
        let msg1 = MailMessage(
            id: "msg-no-name",
            subject: "Test",
            senderEmail: "alice@example.com",
            dateReceived: Date(timeIntervalSince1970: 1000)
        )
        // Second message from alice with name
        let msg2 = MailMessage(
            id: "msg-with-name",
            subject: "Re: Test",
            senderName: "Alice Wonderland",
            senderEmail: "alice@example.com",
            dateReceived: Date(timeIntervalSince1970: 2000)
        )

        for msg in [msg1, msg2] {
            try database.upsertMessage(msg)
            try database.addMessageToThread(messageId: msg.id, threadId: "test-name-update")
        }

        let metadata = try service.extractThreadMetadata(threadId: "test-name-update", database: database)

        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.participants.count, 1)
        // Should have the name from the second message
        XCTAssertEqual(metadata?.participants.first?.name, "Alice Wonderland")
    }

    // MARK: - Participant Struct Tests

    func testParticipantEquality() {
        let p1 = ThreadDetectionService.Participant(email: "test@example.com", name: "Test")
        let p2 = ThreadDetectionService.Participant(email: "TEST@example.com", name: "Test")

        // Emails should be lowercased, so they should be equal
        XCTAssertEqual(p1, p2)
    }

    func testParticipantHashable() {
        let p1 = ThreadDetectionService.Participant(email: "test@example.com", name: "Test")
        let p2 = ThreadDetectionService.Participant(email: "TEST@example.com", name: "Test")

        var set = Set<ThreadDetectionService.Participant>()
        set.insert(p1)
        set.insert(p2)

        // Both should hash to the same value since email is lowercased
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - ThreadMetadata Struct Tests

    func testThreadMetadataEquality() {
        let participants = [ThreadDetectionService.Participant(email: "test@example.com")]
        let date = Date(timeIntervalSince1970: 1000)

        let m1 = ThreadDetectionService.ThreadMetadata(
            threadId: "abc",
            subject: "Test",
            participants: participants,
            firstMessageDate: date,
            lastMessageDate: date,
            messageCount: 1
        )

        let m2 = ThreadDetectionService.ThreadMetadata(
            threadId: "abc",
            subject: "Test",
            participants: participants,
            firstMessageDate: date,
            lastMessageDate: date,
            messageCount: 1
        )

        XCTAssertEqual(m1, m2)
    }

    // MARK: - Thread Merging Scenarios

    func testThreadMergingWithLateArrivingRootMessage() throws {
        // Scenario: Reply arrives before the original message
        // Both should end up in the same thread when processed
        try database.initialize()

        // Reply arrives first (has reference to root)
        let reply = MailMessage(
            id: "msg-reply",
            messageId: "<reply@example.com>",
            subject: "Re: Important Discussion",
            senderEmail: "bob@example.com",
            dateReceived: Date(),
            inReplyTo: "<root@example.com>",
            references: ["<root@example.com>"]
        )
        try database.upsertMessage(reply)
        let replyResult = try service.processMessageForThreading(reply, database: database)

        // Original root message arrives later
        let root = MailMessage(
            id: "msg-root",
            messageId: "<root@example.com>",
            subject: "Important Discussion",
            senderEmail: "alice@example.com",
            dateReceived: Date(timeIntervalSinceNow: -3600) // Earlier time
        )
        try database.upsertMessage(root)
        let rootResult = try service.processMessageForThreading(root, database: database)

        // Both should be in the same thread
        XCTAssertEqual(replyResult.threadId, rootResult.threadId)

        let thread = try database.getThread(id: replyResult.threadId)
        XCTAssertEqual(thread?.messageCount, 2)
    }

    func testThreadMergingWithBranchingReplies() throws {
        // Scenario: Multiple people reply to the same original message (branching)
        try database.initialize()

        // Original message
        let original = MailMessage(
            id: "msg-original",
            messageId: "<original@example.com>",
            subject: "Team Meeting",
            senderEmail: "manager@example.com",
            dateReceived: Date(timeIntervalSinceNow: -7200)
        )
        try database.upsertMessage(original)
        let originalResult = try service.processMessageForThreading(original, database: database)

        // Alice replies to original
        let aliceReply = MailMessage(
            id: "msg-alice",
            messageId: "<alice-reply@example.com>",
            subject: "Re: Team Meeting",
            senderEmail: "alice@example.com",
            dateReceived: Date(timeIntervalSinceNow: -3600),
            inReplyTo: "<original@example.com>",
            references: ["<original@example.com>"]
        )
        try database.upsertMessage(aliceReply)
        let aliceResult = try service.processMessageForThreading(aliceReply, database: database)

        // Bob also replies to original (branching)
        let bobReply = MailMessage(
            id: "msg-bob",
            messageId: "<bob-reply@example.com>",
            subject: "Re: Team Meeting",
            senderEmail: "bob@example.com",
            dateReceived: Date(timeIntervalSinceNow: -1800),
            inReplyTo: "<original@example.com>",
            references: ["<original@example.com>"]
        )
        try database.upsertMessage(bobReply)
        let bobResult = try service.processMessageForThreading(bobReply, database: database)

        // Charlie replies to Alice's reply
        let charlieReply = MailMessage(
            id: "msg-charlie",
            messageId: "<charlie-reply@example.com>",
            subject: "Re: Team Meeting",
            senderEmail: "charlie@example.com",
            dateReceived: Date(),
            inReplyTo: "<alice-reply@example.com>",
            references: ["<original@example.com>", "<alice-reply@example.com>"]
        )
        try database.upsertMessage(charlieReply)
        let charlieResult = try service.processMessageForThreading(charlieReply, database: database)

        // All messages should be in the same thread
        XCTAssertEqual(originalResult.threadId, aliceResult.threadId)
        XCTAssertEqual(aliceResult.threadId, bobResult.threadId)
        XCTAssertEqual(bobResult.threadId, charlieResult.threadId)

        let thread = try database.getThread(id: originalResult.threadId)
        XCTAssertEqual(thread?.messageCount, 4)
        XCTAssertEqual(thread?.participantCount, 4)
    }

    func testThreadMergingOutOfOrderProcessing() throws {
        // Scenario: Messages from the same thread arrive and are processed out of order
        try database.initialize()

        // Create messages representing a thread (order: 3rd reply, 1st reply, original, 2nd reply)
        let thirdReply = MailMessage(
            id: "msg-3",
            messageId: "<reply3@example.com>",
            subject: "Re: Re: Re: Discussion",
            senderEmail: "dave@example.com",
            dateReceived: Date(timeIntervalSince1970: 4000),
            inReplyTo: "<reply2@example.com>",
            references: ["<original@example.com>", "<reply1@example.com>", "<reply2@example.com>"]
        )

        let firstReply = MailMessage(
            id: "msg-1",
            messageId: "<reply1@example.com>",
            subject: "Re: Discussion",
            senderEmail: "bob@example.com",
            dateReceived: Date(timeIntervalSince1970: 2000),
            inReplyTo: "<original@example.com>",
            references: ["<original@example.com>"]
        )

        let original = MailMessage(
            id: "msg-0",
            messageId: "<original@example.com>",
            subject: "Discussion",
            senderEmail: "alice@example.com",
            dateReceived: Date(timeIntervalSince1970: 1000)
        )

        let secondReply = MailMessage(
            id: "msg-2",
            messageId: "<reply2@example.com>",
            subject: "Re: Re: Discussion",
            senderEmail: "charlie@example.com",
            dateReceived: Date(timeIntervalSince1970: 3000),
            inReplyTo: "<reply1@example.com>",
            references: ["<original@example.com>", "<reply1@example.com>"]
        )

        // Process in random order
        for msg in [thirdReply, firstReply, original, secondReply] {
            try database.upsertMessage(msg)
        }

        let results = [
            try service.processMessageForThreading(thirdReply, database: database),
            try service.processMessageForThreading(firstReply, database: database),
            try service.processMessageForThreading(original, database: database),
            try service.processMessageForThreading(secondReply, database: database)
        ]

        // All should be in the same thread regardless of processing order
        let threadIds = results.map { $0.threadId }
        XCTAssertTrue(threadIds.allSatisfy { $0 == threadIds[0] })

        let thread = try database.getThread(id: results[0].threadId)
        XCTAssertEqual(thread?.messageCount, 4)
        XCTAssertEqual(thread?.firstDate?.timeIntervalSince1970, 1000)
        XCTAssertEqual(thread?.lastDate?.timeIntervalSince1970, 4000)
    }

    func testThreadMergingWithSubjectFallback() throws {
        // Scenario: Messages without proper threading headers but same subject
        try database.initialize()

        // Message 1: No message ID, just subject
        let msg1 = MailMessage(
            id: "msg-no-id-1",
            subject: "Project Update",
            senderEmail: "alice@example.com",
            dateReceived: Date(timeIntervalSince1970: 1000)
        )
        try database.upsertMessage(msg1)
        let result1 = try service.processMessageForThreading(msg1, database: database)

        // Message 2: No message ID, same normalized subject (with Re:)
        let msg2 = MailMessage(
            id: "msg-no-id-2",
            subject: "Re: Project Update",
            senderEmail: "bob@example.com",
            dateReceived: Date(timeIntervalSince1970: 2000)
        )
        try database.upsertMessage(msg2)
        let result2 = try service.processMessageForThreading(msg2, database: database)

        // Message 3: No message ID, same normalized subject (with FWD:)
        let msg3 = MailMessage(
            id: "msg-no-id-3",
            subject: "Fwd: Project Update",
            senderEmail: "charlie@example.com",
            dateReceived: Date(timeIntervalSince1970: 3000)
        )
        try database.upsertMessage(msg3)
        let result3 = try service.processMessageForThreading(msg3, database: database)

        // All should be in the same thread (subject-based fallback)
        XCTAssertEqual(result1.threadId, result2.threadId)
        XCTAssertEqual(result2.threadId, result3.threadId)
    }

    func testForwardedMessageCreatesNewThread() throws {
        // Scenario: Forwarded message should start a new thread
        try database.initialize()

        // Original thread
        let original = MailMessage(
            id: "msg-original",
            messageId: "<original@example.com>",
            subject: "Confidential Report",
            senderEmail: "alice@example.com",
            dateReceived: Date(timeIntervalSinceNow: -3600)
        )
        try database.upsertMessage(original)
        let originalResult = try service.processMessageForThreading(original, database: database)

        // Reply in original thread
        let reply = MailMessage(
            id: "msg-reply",
            messageId: "<reply@example.com>",
            subject: "Re: Confidential Report",
            senderEmail: "bob@example.com",
            dateReceived: Date(timeIntervalSinceNow: -1800),
            inReplyTo: "<original@example.com>",
            references: ["<original@example.com>"]
        )
        try database.upsertMessage(reply)
        let replyResult = try service.processMessageForThreading(reply, database: database)

        // Forward to someone else (new Message-ID, no threading headers)
        let forwarded = MailMessage(
            id: "msg-forwarded",
            messageId: "<forwarded@example.com>",
            subject: "Fwd: Confidential Report",
            senderEmail: "bob@example.com",
            dateReceived: Date()
        )
        try database.upsertMessage(forwarded)
        let forwardedResult = try service.processMessageForThreading(forwarded, database: database)

        // Original and reply should be same thread
        XCTAssertEqual(originalResult.threadId, replyResult.threadId)

        // Forwarded should be a different thread
        XCTAssertNotEqual(originalResult.threadId, forwardedResult.threadId)
    }

    func testMailingListThreadContinuity() throws {
        // Scenario: Messages through a mailing list maintain thread continuity
        try database.initialize()

        // Original message posted to list
        let listPost = MailMessage(
            id: "msg-list-post",
            messageId: "<list-msg-001@lists.example.com>",
            subject: "[dev-list] RFC: New Feature",
            senderEmail: "alice@example.com",
            dateReceived: Date(timeIntervalSince1970: 1000)
        )
        try database.upsertMessage(listPost)
        let postResult = try service.processMessageForThreading(listPost, database: database)

        // Reply through list (mailing list may rewrite Message-ID)
        let listReply = MailMessage(
            id: "msg-list-reply",
            messageId: "<list-msg-002@lists.example.com>",
            subject: "Re: [dev-list] RFC: New Feature",
            senderEmail: "bob@example.com",
            dateReceived: Date(timeIntervalSince1970: 2000),
            inReplyTo: "<list-msg-001@lists.example.com>",
            references: ["<list-msg-001@lists.example.com>"]
        )
        try database.upsertMessage(listReply)
        let replyResult = try service.processMessageForThreading(listReply, database: database)

        // Another reply
        let anotherReply = MailMessage(
            id: "msg-list-reply2",
            messageId: "<list-msg-003@lists.example.com>",
            subject: "Re: [dev-list] RFC: New Feature",
            senderEmail: "charlie@example.com",
            dateReceived: Date(timeIntervalSince1970: 3000),
            inReplyTo: "<list-msg-002@lists.example.com>",
            references: ["<list-msg-001@lists.example.com>", "<list-msg-002@lists.example.com>"]
        )
        try database.upsertMessage(anotherReply)
        let anotherResult = try service.processMessageForThreading(anotherReply, database: database)

        // All should be in the same thread
        XCTAssertEqual(postResult.threadId, replyResult.threadId)
        XCTAssertEqual(replyResult.threadId, anotherResult.threadId)

        let thread = try database.getThread(id: postResult.threadId)
        XCTAssertEqual(thread?.messageCount, 3)
    }

    func testCrossClientThreadingWithProperReferences() throws {
        // Scenario: Different email clients all maintain proper References header
        // This is the ideal case where threading works correctly
        try database.initialize()

        // Original message
        let original = MailMessage(
            id: "msg-orig",
            messageId: "<orig@gmail.com>",
            subject: "Quick Question",
            senderEmail: "alice@gmail.com",
            dateReceived: Date(timeIntervalSince1970: 1000)
        )
        try database.upsertMessage(original)
        let origResult = try service.processMessageForThreading(original, database: database)

        // Reply from Outlook (typically includes full References)
        let outlookReply = MailMessage(
            id: "msg-outlook",
            messageId: "<reply@outlook.com>",
            subject: "RE: Quick Question",
            senderEmail: "bob@outlook.com",
            dateReceived: Date(timeIntervalSince1970: 2000),
            inReplyTo: "<orig@gmail.com>",
            references: ["<orig@gmail.com>"]
        )
        try database.upsertMessage(outlookReply)
        let outlookResult = try service.processMessageForThreading(outlookReply, database: database)

        // Reply from another client (maintains References)
        let anotherReply = MailMessage(
            id: "msg-another",
            messageId: "<reply@another.com>",
            subject: "Re: Quick Question",
            senderEmail: "charlie@another.com",
            dateReceived: Date(timeIntervalSince1970: 3000),
            inReplyTo: "<reply@outlook.com>",
            references: ["<orig@gmail.com>", "<reply@outlook.com>"]
        )
        try database.upsertMessage(anotherReply)
        let anotherResult = try service.processMessageForThreading(anotherReply, database: database)

        // Reply from Apple Mail (includes References chain)
        let appleReply = MailMessage(
            id: "msg-apple",
            messageId: "<reply@icloud.com>",
            subject: "Re: Quick Question",
            senderEmail: "dave@icloud.com",
            dateReceived: Date(timeIntervalSince1970: 4000),
            inReplyTo: "<reply@another.com>",
            references: ["<orig@gmail.com>", "<reply@outlook.com>", "<reply@another.com>"]
        )
        try database.upsertMessage(appleReply)
        let appleResult = try service.processMessageForThreading(appleReply, database: database)

        // All should be in the same thread (all have References with same root)
        XCTAssertEqual(origResult.threadId, outlookResult.threadId)
        XCTAssertEqual(outlookResult.threadId, anotherResult.threadId)
        XCTAssertEqual(anotherResult.threadId, appleResult.threadId)

        let thread = try database.getThread(id: origResult.threadId)
        XCTAssertEqual(thread?.messageCount, 4)
        XCTAssertEqual(thread?.participantCount, 4)
    }

    func testCrossClientThreadingWithLegacyClient() throws {
        // Scenario: A legacy client that only sets In-Reply-To (no References)
        // causes thread fragmentation. This is a known limitation - without
        // References header, we can't determine the original thread root.
        try database.initialize()

        // Original message
        let original = MailMessage(
            id: "msg-orig",
            messageId: "<orig@gmail.com>",
            subject: "Quick Question",
            senderEmail: "alice@gmail.com",
            dateReceived: Date(timeIntervalSince1970: 1000)
        )
        try database.upsertMessage(original)
        let origResult = try service.processMessageForThreading(original, database: database)

        // Reply from modern client (includes References)
        let modernReply = MailMessage(
            id: "msg-modern",
            messageId: "<reply@modern.com>",
            subject: "RE: Quick Question",
            senderEmail: "bob@modern.com",
            dateReceived: Date(timeIntervalSince1970: 2000),
            inReplyTo: "<orig@gmail.com>",
            references: ["<orig@gmail.com>"]
        )
        try database.upsertMessage(modernReply)
        let modernResult = try service.processMessageForThreading(modernReply, database: database)

        // Reply from legacy client (only In-Reply-To, no References)
        // This breaks the thread chain as we use In-Reply-To as thread root
        let legacyReply = MailMessage(
            id: "msg-legacy",
            messageId: "<reply@legacy.com>",
            subject: "Re: Quick Question",
            senderEmail: "charlie@legacy.com",
            dateReceived: Date(timeIntervalSince1970: 3000),
            inReplyTo: "<reply@modern.com>"
            // Note: No references array - legacy client behavior
        )
        try database.upsertMessage(legacyReply)
        let legacyResult = try service.processMessageForThreading(legacyReply, database: database)

        // Original and modern reply share the same thread
        XCTAssertEqual(origResult.threadId, modernResult.threadId)

        // Legacy reply ends up in a different thread (known limitation)
        // Thread ID is based on In-Reply-To (<reply@modern.com>) not thread root
        XCTAssertNotEqual(origResult.threadId, legacyResult.threadId)
    }

    func testDeeplyNestedReplyChain() throws {
        // Scenario: Very long email thread with many replies
        try database.initialize()

        var previousMessageId = "<root@example.com>"
        var allReferences: [String] = []
        var results: [ThreadDetectionService.ThreadDetectionResult] = []

        // Create root message
        let root = MailMessage(
            id: "msg-0",
            messageId: previousMessageId,
            subject: "Long Discussion",
            senderEmail: "user0@example.com",
            dateReceived: Date(timeIntervalSince1970: 0)
        )
        try database.upsertMessage(root)
        let rootResult = try service.processMessageForThreading(root, database: database)
        results.append(rootResult)
        allReferences.append(previousMessageId)

        // Create 20 replies in chain
        for i in 1...20 {
            let newMessageId = "<reply\(i)@example.com>"
            let reply = MailMessage(
                id: "msg-\(i)",
                messageId: newMessageId,
                subject: "Re: Long Discussion",
                senderEmail: "user\(i % 5)@example.com",
                dateReceived: Date(timeIntervalSince1970: Double(i * 1000)),
                inReplyTo: previousMessageId,
                references: allReferences
            )
            try database.upsertMessage(reply)
            let result = try service.processMessageForThreading(reply, database: database)
            results.append(result)

            allReferences.append(newMessageId)
            previousMessageId = newMessageId
        }

        // All 21 messages should be in the same thread
        let firstThreadId = results[0].threadId
        XCTAssertTrue(results.allSatisfy { $0.threadId == firstThreadId })

        let thread = try database.getThread(id: firstThreadId)
        XCTAssertEqual(thread?.messageCount, 21)
        XCTAssertEqual(thread?.participantCount, 5) // user0-user4 (cycling)
    }
}
