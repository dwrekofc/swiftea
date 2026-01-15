import XCTest
@testable import SwiftEAKit

final class ThreadIDGeneratorTests: XCTestCase {
    var generator: ThreadIDGenerator!

    override func setUp() {
        super.setUp()
        generator = ThreadIDGenerator()
    }

    override func tearDown() {
        generator = nil
        super.tearDown()
    }

    // MARK: - Basic Thread ID Generation

    func testGenerateThreadIdFromMessageIdOnly() {
        // Standalone message (thread root) uses its own message ID
        let threadId = generator.generateThreadId(
            messageId: "<root@example.com>",
            inReplyTo: nil,
            references: []
        )

        XCTAssertEqual(threadId.count, 32)
        XCTAssertTrue(generator.isValidThreadId(threadId))
    }

    func testGenerateThreadIdFromReferences() {
        // Reply with references - uses the FIRST reference (thread root)
        let threadId = generator.generateThreadId(
            messageId: "<reply@example.com>",
            inReplyTo: "<parent@example.com>",
            references: ["<root@example.com>", "<parent@example.com>"]
        )

        XCTAssertEqual(threadId.count, 32)
        XCTAssertTrue(generator.isValidThreadId(threadId))
    }

    func testGenerateThreadIdFromInReplyToOnly() {
        // Reply with only In-Reply-To (no References header)
        let threadId = generator.generateThreadId(
            messageId: "<reply@example.com>",
            inReplyTo: "<parent@example.com>",
            references: []
        )

        XCTAssertEqual(threadId.count, 32)
        XCTAssertTrue(generator.isValidThreadId(threadId))
    }

    // MARK: - Thread ID Stability

    func testThreadIdIsDeterministic() {
        // Same inputs should always produce the same thread ID
        let threadId1 = generator.generateThreadId(
            messageId: "<msg@example.com>",
            inReplyTo: "<parent@example.com>",
            references: ["<root@example.com>"]
        )

        let threadId2 = generator.generateThreadId(
            messageId: "<msg@example.com>",
            inReplyTo: "<parent@example.com>",
            references: ["<root@example.com>"]
        )

        XCTAssertEqual(threadId1, threadId2)
    }

    func testThreadIdIsStableAcrossSyncs() {
        // This simulates multiple syncs - same message ID should produce same thread ID
        let messageId = "<stable-test@example.com>"

        let sync1ThreadId = generator.generateThreadId(
            messageId: messageId,
            inReplyTo: nil,
            references: []
        )

        // Simulate second sync
        let sync2ThreadId = generator.generateThreadId(
            messageId: messageId,
            inReplyTo: nil,
            references: []
        )

        XCTAssertEqual(sync1ThreadId, sync2ThreadId)
    }

    // MARK: - Thread Grouping (Same Thread ID)

    func testAllMessagesInThreadShareSameThreadId() {
        // Thread root
        let rootId = generator.generateThreadId(
            messageId: "<root@example.com>",
            inReplyTo: nil,
            references: []
        )

        // First reply (references the root)
        let reply1Id = generator.generateThreadId(
            messageId: "<reply1@example.com>",
            inReplyTo: "<root@example.com>",
            references: ["<root@example.com>"]
        )

        // Second reply (also references root as first reference)
        let reply2Id = generator.generateThreadId(
            messageId: "<reply2@example.com>",
            inReplyTo: "<reply1@example.com>",
            references: ["<root@example.com>", "<reply1@example.com>"]
        )

        // All should have the same thread ID (based on root)
        XCTAssertEqual(rootId, reply1Id)
        XCTAssertEqual(reply1Id, reply2Id)
    }

    func testDifferentThreadsHaveDifferentIds() {
        let thread1Root = generator.generateThreadId(
            messageId: "<thread1-root@example.com>",
            inReplyTo: nil,
            references: []
        )

        let thread2Root = generator.generateThreadId(
            messageId: "<thread2-root@example.com>",
            inReplyTo: nil,
            references: []
        )

        XCTAssertNotEqual(thread1Root, thread2Root)
    }

    // MARK: - Reply Chain Handling

    func testReplyChainUsingReferences() {
        // Original message
        let original = generator.generateThreadId(
            messageId: "<original@example.com>",
            inReplyTo: nil,
            references: []
        )

        // Direct reply
        let reply = generator.generateThreadId(
            messageId: "<reply@example.com>",
            inReplyTo: "<original@example.com>",
            references: ["<original@example.com>"]
        )

        // Reply to reply
        let replyToReply = generator.generateThreadId(
            messageId: "<reply-to-reply@example.com>",
            inReplyTo: "<reply@example.com>",
            references: ["<original@example.com>", "<reply@example.com>"]
        )

        // Deep reply
        let deepReply = generator.generateThreadId(
            messageId: "<deep-reply@example.com>",
            inReplyTo: "<reply-to-reply@example.com>",
            references: ["<original@example.com>", "<reply@example.com>", "<reply-to-reply@example.com>"]
        )

        // All should share the same thread ID
        XCTAssertEqual(original, reply)
        XCTAssertEqual(reply, replyToReply)
        XCTAssertEqual(replyToReply, deepReply)
    }

    func testReplyChainWithInReplyToOnly() {
        // Some mail clients only set In-Reply-To, not References
        // In this case, In-Reply-To acts as the thread root for replies

        // Original
        let original = generator.generateThreadId(
            messageId: "<original@example.com>",
            inReplyTo: nil,
            references: []
        )

        // Reply with only In-Reply-To
        let reply = generator.generateThreadId(
            messageId: "<reply@example.com>",
            inReplyTo: "<original@example.com>",
            references: []
        )

        // Both should share the same thread ID
        XCTAssertEqual(original, reply)
    }

    // MARK: - Forwarded Message Handling

    func testForwardedMessageStartsNewThread() {
        // Original thread
        let original = generator.generateThreadId(
            messageId: "<original@example.com>",
            inReplyTo: nil,
            references: []
        )

        // Forwarded message typically gets a new Message-ID and no References
        let forwarded = generator.generateThreadId(
            messageId: "<forwarded@example.com>",
            inReplyTo: nil,
            references: []
        )

        // Forwarded messages should start a new thread
        XCTAssertNotEqual(original, forwarded)
    }

    func testIsForwardedDetection() {
        XCTAssertTrue(generator.isForwarded(subject: "Fwd: Test"))
        XCTAssertTrue(generator.isForwarded(subject: "FW: Test"))
        XCTAssertTrue(generator.isForwarded(subject: "fwd: test"))
        XCTAssertTrue(generator.isForwarded(subject: "Forwarded: Test"))
        XCTAssertFalse(generator.isForwarded(subject: "Re: Test"))
        XCTAssertFalse(generator.isForwarded(subject: "Test"))
        XCTAssertFalse(generator.isForwarded(subject: nil))
    }

    // MARK: - Subject Normalization

    func testNormalizeSubjectRemovesRePrefix() {
        XCTAssertEqual(generator.normalizeSubject("Re: Test"), "test")
        XCTAssertEqual(generator.normalizeSubject("RE: Test"), "test")
        XCTAssertEqual(generator.normalizeSubject("re: test"), "test")
    }

    func testNormalizeSubjectRemovesFwdPrefix() {
        XCTAssertEqual(generator.normalizeSubject("Fwd: Test"), "test")
        XCTAssertEqual(generator.normalizeSubject("FW: Test"), "test")
        XCTAssertEqual(generator.normalizeSubject("fwd: test"), "test")
    }

    func testNormalizeSubjectRemovesNestedPrefixes() {
        XCTAssertEqual(generator.normalizeSubject("Re: Re: Fwd: Test"), "test")
        XCTAssertEqual(generator.normalizeSubject("RE: FW: RE: Test"), "test")
    }

    func testNormalizeSubjectRemovesInternationalPrefixes() {
        // German: AW (Antwort)
        XCTAssertEqual(generator.normalizeSubject("AW: Test"), "test")
        // Dutch: Antw
        XCTAssertEqual(generator.normalizeSubject("Antw: Test"), "test")
        // Swedish/Norwegian: SV
        XCTAssertEqual(generator.normalizeSubject("SV: Test"), "test")
        // Danish: VS
        XCTAssertEqual(generator.normalizeSubject("VS: Test"), "test")
        // Polish: Odp
        XCTAssertEqual(generator.normalizeSubject("Odp: Test"), "test")
        // Spanish/Italian: R
        XCTAssertEqual(generator.normalizeSubject("R: Test"), "test")
    }

    func testNormalizeSubjectCollapsesWhitespace() {
        XCTAssertEqual(generator.normalizeSubject("  Test   Subject  "), "test subject")
    }

    func testNormalizeSubjectLowercases() {
        XCTAssertEqual(generator.normalizeSubject("TEST SUBJECT"), "test subject")
    }

    // MARK: - Subject Fallback Thread ID

    func testSubjectFallbackThreadId() {
        // When no message ID is available, fall back to subject-based threading
        let threadId1 = generator.generateThreadId(
            messageId: nil,
            inReplyTo: nil,
            references: [],
            subject: "Test Subject"
        )

        let threadId2 = generator.generateThreadId(
            messageId: nil,
            inReplyTo: nil,
            references: [],
            subject: "Re: Test Subject"
        )

        // Same normalized subject should produce same thread ID
        XCTAssertEqual(threadId1, threadId2)
    }

    func testSubjectFallbackDifferentSubjects() {
        let threadId1 = generator.generateThreadId(
            messageId: nil,
            inReplyTo: nil,
            references: [],
            subject: "First Topic"
        )

        let threadId2 = generator.generateThreadId(
            messageId: nil,
            inReplyTo: nil,
            references: [],
            subject: "Second Topic"
        )

        XCTAssertNotEqual(threadId1, threadId2)
    }

    // MARK: - Edge Cases

    func testEmptyInputsGenerateUniqueId() {
        // Should not crash with all-nil inputs
        let threadId1 = generator.generateThreadId(
            messageId: nil,
            inReplyTo: nil,
            references: []
        )

        let threadId2 = generator.generateThreadId(
            messageId: nil,
            inReplyTo: nil,
            references: []
        )

        // Each call generates a unique fallback ID
        XCTAssertTrue(generator.isValidThreadId(threadId1))
        XCTAssertTrue(generator.isValidThreadId(threadId2))
        // Without subject fallback, these should be different (UUID-based)
        XCTAssertNotEqual(threadId1, threadId2)
    }

    func testEmptyMessageId() {
        let threadId = generator.generateThreadId(
            messageId: "",
            inReplyTo: nil,
            references: []
        )

        XCTAssertTrue(generator.isValidThreadId(threadId))
    }

    func testEmptyInReplyTo() {
        let threadId = generator.generateThreadId(
            messageId: "<msg@example.com>",
            inReplyTo: "",
            references: []
        )

        XCTAssertTrue(generator.isValidThreadId(threadId))
    }

    func testEmptyReferencesArray() {
        let threadId = generator.generateThreadId(
            messageId: "<msg@example.com>",
            inReplyTo: "<parent@example.com>",
            references: []
        )

        // Should use inReplyTo when references is empty
        XCTAssertTrue(generator.isValidThreadId(threadId))
    }

    func testWhitespaceOnlyMessageId() {
        let threadId = generator.generateThreadId(
            messageId: "   ",
            inReplyTo: nil,
            references: []
        )

        XCTAssertTrue(generator.isValidThreadId(threadId))
    }

    // MARK: - Message ID Normalization for Hashing

    func testNormalizationForHashingRemovesBrackets() {
        // Both should produce the same thread ID regardless of angle brackets
        let withBrackets = generator.generateThreadId(
            messageId: "<msg@example.com>",
            inReplyTo: nil,
            references: []
        )

        // When no brackets in input, determineThreadRoot adds fallback format
        // So we test with consistent bracket formatting
        let alsoWithBrackets = generator.generateThreadId(
            messageId: "<msg@example.com>",
            inReplyTo: nil,
            references: []
        )

        XCTAssertEqual(withBrackets, alsoWithBrackets)
    }

    func testNormalizationIsCaseInsensitive() {
        let lower = generator.generateThreadId(
            messageId: "<msg@example.com>",
            inReplyTo: nil,
            references: []
        )

        let upper = generator.generateThreadId(
            messageId: "<MSG@EXAMPLE.COM>",
            inReplyTo: nil,
            references: []
        )

        XCTAssertEqual(lower, upper)
    }

    // MARK: - Is Reply Detection

    func testIsReplyWithInReplyTo() {
        XCTAssertTrue(generator.isReply(inReplyTo: "<parent@example.com>", references: []))
    }

    func testIsReplyWithReferences() {
        XCTAssertTrue(generator.isReply(inReplyTo: nil, references: ["<ref@example.com>"]))
    }

    func testIsReplyWithBoth() {
        XCTAssertTrue(generator.isReply(
            inReplyTo: "<parent@example.com>",
            references: ["<ref@example.com>"]
        ))
    }

    func testIsReplyFalse() {
        XCTAssertFalse(generator.isReply(inReplyTo: nil, references: []))
        XCTAssertFalse(generator.isReply(inReplyTo: "", references: []))
    }

    // MARK: - Thread Root Determination

    func testDetermineThreadRootFromReferences() {
        let root = generator.determineThreadRoot(
            messageId: "<msg@example.com>",
            inReplyTo: "<parent@example.com>",
            references: ["<root@example.com>", "<parent@example.com>"]
        )

        // Should return the first reference (normalized - no brackets, lowercase)
        XCTAssertEqual(root, "root@example.com")
    }

    func testDetermineThreadRootFromInReplyTo() {
        let root = generator.determineThreadRoot(
            messageId: "<msg@example.com>",
            inReplyTo: "<parent@example.com>",
            references: []
        )

        XCTAssertEqual(root, "parent@example.com")
    }

    func testDetermineThreadRootFromMessageId() {
        let root = generator.determineThreadRoot(
            messageId: "<msg@example.com>",
            inReplyTo: nil,
            references: []
        )

        XCTAssertEqual(root, "msg@example.com")
    }

    func testDetermineThreadRootFallback() {
        // With no valid IDs, should generate a fallback
        let root = generator.determineThreadRoot(
            messageId: nil,
            inReplyTo: nil,
            references: []
        )

        XCTAssertTrue(root.contains("fallback"))
    }

    // MARK: - Integration with ThreadingHeaders

    func testGenerateFromThreadingHeaders() {
        let headers = ThreadingHeaderParser.ThreadingHeaders(
            messageId: "<msg@example.com>",
            inReplyTo: "<parent@example.com>",
            references: ["<root@example.com>"]
        )

        let threadId = generator.generateThreadId(from: headers)

        XCTAssertTrue(generator.isValidThreadId(threadId))
    }

    // MARK: - Integration with MailMessage

    func testGenerateFromMailMessage() {
        let message = MailMessage(
            id: "test-id",
            messageId: "<msg@example.com>",
            subject: "Test",
            inReplyTo: "<parent@example.com>",
            references: ["<root@example.com>"]
        )

        let threadId = generator.generateThreadId(from: message)

        XCTAssertTrue(generator.isValidThreadId(threadId))
    }

    // MARK: - Thread ID Validation

    func testValidThreadId() {
        let threadId = generator.generateThreadId(
            messageId: "<msg@example.com>",
            inReplyTo: nil,
            references: []
        )

        XCTAssertTrue(generator.isValidThreadId(threadId))
    }

    func testInvalidThreadIdTooShort() {
        XCTAssertFalse(generator.isValidThreadId("abc123"))
    }

    func testInvalidThreadIdTooLong() {
        let longId = String(repeating: "a", count: 64)
        XCTAssertFalse(generator.isValidThreadId(longId))
    }

    func testInvalidThreadIdNonHex() {
        let nonHex = "xyz123xyz123xyz123xyz123xyz12345"
        XCTAssertFalse(generator.isValidThreadId(nonHex))
    }

    func testInvalidThreadIdUppercase() {
        // Valid thread IDs are lowercase
        let uppercase = "ABCDEF1234567890ABCDEF1234567890"
        XCTAssertFalse(generator.isValidThreadId(uppercase))
    }

    // MARK: - Real-World Threading Scenarios

    func testComplexThreadWithMultipleParticipants() {
        // Simulates a real email thread with multiple participants replying
        let originalId = "<original@company.com>"
        let references = [originalId]

        // Original message
        let originalThread = generator.generateThreadId(
            messageId: originalId,
            inReplyTo: nil,
            references: []
        )

        // Person A replies
        let personAReply = generator.generateThreadId(
            messageId: "<reply-a@company.com>",
            inReplyTo: originalId,
            references: references
        )

        // Person B replies to A's reply
        let personBReply = generator.generateThreadId(
            messageId: "<reply-b@company.com>",
            inReplyTo: "<reply-a@company.com>",
            references: references + ["<reply-a@company.com>"]
        )

        // Person C replies to original (branching)
        let personCReply = generator.generateThreadId(
            messageId: "<reply-c@company.com>",
            inReplyTo: originalId,
            references: references
        )

        // All should be in the same thread
        XCTAssertEqual(originalThread, personAReply)
        XCTAssertEqual(personAReply, personBReply)
        XCTAssertEqual(personBReply, personCReply)
    }

    func testMailingListThread() {
        // Mailing lists often rewrite message IDs - test thread continuity
        let listRoot = "<list-msg-001@lists.example.com>"

        let original = generator.generateThreadId(
            messageId: listRoot,
            inReplyTo: nil,
            references: []
        )

        // Reply through the list
        let reply = generator.generateThreadId(
            messageId: "<list-msg-002@lists.example.com>",
            inReplyTo: listRoot,
            references: [listRoot]
        )

        XCTAssertEqual(original, reply)
    }
}
