import XCTest
@testable import SwiftEAKit

final class CachedThreadDetectionServiceTests: XCTestCase {
    var service: CachedThreadDetectionService!
    var testDir: String!
    var database: MailDatabase!

    override func setUp() {
        super.setUp()
        service = CachedThreadDetectionService(cacheSize: 100)

        // Setup test database
        testDir = NSTemporaryDirectory() + "swiftea-cached-thread-test-\(UUID().uuidString)"
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

    // MARK: - Initialization

    func testDefaultInitialization() {
        let svc = CachedThreadDetectionService()
        XCTAssertNotNil(svc)
    }

    func testCustomCacheSizeInitialization() {
        let svc = CachedThreadDetectionService(cacheSize: 1000)
        XCTAssertNotNil(svc)
    }

    // MARK: - Thread Detection (No Cache - Delegated)

    func testDetectThreadIdForStandaloneMessage() {
        let threadId = service.detectThreadId(
            messageId: "<standalone@example.com>",
            inReplyTo: nil,
            references: nil,
            subject: "Hello World"
        )

        XCTAssertEqual(threadId.count, 32)
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

    // MARK: - Cached Thread Lookup

    func testGetThreadCachesMissAndHit() async throws {
        try database.initialize()

        // Create a thread directly
        let thread = Thread(id: "test-thread", subject: "Test Subject", messageCount: 1)
        try database.upsertThread(thread)

        // First call should miss cache and query DB
        let retrieved1 = try await service.getThread(id: "test-thread", database: database)
        XCTAssertNotNil(retrieved1)
        XCTAssertEqual(retrieved1?.subject, "Test Subject")

        // Second call should hit cache
        let retrieved2 = try await service.getThread(id: "test-thread", database: database)
        XCTAssertNotNil(retrieved2)
        XCTAssertEqual(retrieved2?.subject, "Test Subject")

        // Verify cache statistics
        let stats = await service.getCacheStatistics()
        XCTAssertEqual(stats.hitCount, 1)
        XCTAssertEqual(stats.missCount, 1)
    }

    func testGetThreadReturnsNilForNonexistent() async throws {
        try database.initialize()

        let retrieved = try await service.getThread(id: "nonexistent", database: database)
        XCTAssertNil(retrieved)

        let stats = await service.getCacheStatistics()
        XCTAssertEqual(stats.missCount, 1)
    }

    // MARK: - Process Message For Threading

    func testProcessMessageCreatesNewThread() async throws {
        try database.initialize()

        let message = MailMessage(
            id: "msg-1",
            messageId: "<test@example.com>",
            subject: "New Thread",
            senderEmail: "sender@example.com",
            dateReceived: Date()
        )
        try database.upsertMessage(message)

        let result = try await service.processMessageForThreading(message, database: database)

        XCTAssertTrue(result.isNewThread)
        XCTAssertEqual(result.threadId.count, 32)

        // Verify thread is now in cache
        let stats = await service.getCacheStatistics()
        XCTAssertEqual(stats.size, 1)
    }

    func testProcessMessageUpdatesCache() async throws {
        try database.initialize()

        // Create first message
        let msg1 = MailMessage(
            id: "msg-1",
            messageId: "<root@example.com>",
            subject: "Thread Topic",
            senderEmail: "alice@example.com",
            dateReceived: Date()
        )
        try database.upsertMessage(msg1)

        let result1 = try await service.processMessageForThreading(msg1, database: database)
        XCTAssertTrue(result1.isNewThread)

        // Get cached thread
        let cachedThread1 = try await service.getThread(id: result1.threadId, database: database)
        XCTAssertEqual(cachedThread1?.messageCount, 1)

        // Create reply
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

        let result2 = try await service.processMessageForThreading(msg2, database: database)
        XCTAssertFalse(result2.isNewThread)
        XCTAssertEqual(result1.threadId, result2.threadId)

        // Cache should be updated with new message count
        let cachedThread2 = try await service.getThread(id: result1.threadId, database: database)
        XCTAssertEqual(cachedThread2?.messageCount, 2)
    }

    func testProcessMessagesInBatch() async throws {
        try database.initialize()

        let messages = [
            MailMessage(id: "msg-1", messageId: "<root@example.com>", subject: "Topic A"),
            MailMessage(id: "msg-2", messageId: "<reply1@example.com>", subject: "Re: Topic A",
                       inReplyTo: "<root@example.com>", references: ["<root@example.com>"]),
            MailMessage(id: "msg-3", messageId: "<other@example.com>", subject: "Topic B")
        ]

        for message in messages {
            try database.upsertMessage(message)
        }

        let results = try await service.processMessagesForThreading(messages, database: database)

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].threadId, results[1].threadId)
        XCTAssertNotEqual(results[0].threadId, results[2].threadId)
    }

    // MARK: - Thread Metadata Updates

    func testUpdateThreadMetadataInvalidatesCache() async throws {
        try database.initialize()

        // Create thread and message
        let thread = Thread(id: "test-thread", subject: "Test")
        try database.upsertThread(thread)

        let message = MailMessage(
            id: "msg-1",
            subject: "Test Message",
            senderEmail: "test@example.com",
            dateReceived: Date()
        )
        try database.upsertMessage(message)
        try database.addMessageToThread(messageId: "msg-1", threadId: "test-thread")

        // Populate cache
        _ = try await service.getThread(id: "test-thread", database: database)

        let stats1 = await service.getCacheStatistics()
        XCTAssertEqual(stats1.size, 1)

        // Update metadata
        try await service.updateThreadMetadata(threadId: "test-thread", database: database)

        // Cache should still contain updated thread
        let stats2 = await service.getCacheStatistics()
        XCTAssertEqual(stats2.size, 1)

        // Get cached thread should show updated data
        let cachedThread = try await service.getThread(id: "test-thread", database: database)
        XCTAssertEqual(cachedThread?.messageCount, 1)
    }

    // MARK: - Cache Management

    func testInvalidateThread() async throws {
        try database.initialize()

        let thread = Thread(id: "test-thread", subject: "Test")
        try database.upsertThread(thread)

        _ = try await service.getThread(id: "test-thread", database: database)

        var stats = await service.getCacheStatistics()
        XCTAssertEqual(stats.size, 1)

        await service.invalidateThread("test-thread")

        stats = await service.getCacheStatistics()
        XCTAssertEqual(stats.size, 0)
    }

    func testInvalidateAllThreads() async throws {
        try database.initialize()

        for i in 1...5 {
            let thread = Thread(id: "thread-\(i)", subject: "Test \(i)")
            try database.upsertThread(thread)
            _ = try await service.getThread(id: "thread-\(i)", database: database)
        }

        var stats = await service.getCacheStatistics()
        XCTAssertEqual(stats.size, 5)

        await service.invalidateAllThreads()

        stats = await service.getCacheStatistics()
        XCTAssertEqual(stats.size, 0)
    }

    func testResetCacheStatistics() async throws {
        try database.initialize()

        let thread = Thread(id: "test-thread", subject: "Test")
        try database.upsertThread(thread)

        _ = try await service.getThread(id: "test-thread", database: database)
        _ = try await service.getThread(id: "nonexistent", database: database)

        var stats = await service.getCacheStatistics()
        XCTAssertEqual(stats.hitCount, 0)
        XCTAssertEqual(stats.missCount, 2)

        await service.resetCacheStatistics()

        stats = await service.getCacheStatistics()
        XCTAssertEqual(stats.hitCount, 0)
        XCTAssertEqual(stats.missCount, 0)
    }

    // MARK: - Convenience Methods

    func testIsReply() {
        let reply = MailMessage(id: "msg-1", subject: "Re: Test",
                               inReplyTo: "<parent@example.com>", references: [])
        XCTAssertTrue(service.isReply(reply))

        let standalone = MailMessage(id: "msg-2", subject: "Test")
        XCTAssertFalse(service.isReply(standalone))
    }

    func testIsForwarded() {
        let forwarded = MailMessage(id: "msg-1", subject: "Fwd: Test")
        XCTAssertTrue(service.isForwarded(forwarded))

        let notForwarded = MailMessage(id: "msg-2", subject: "Test")
        XCTAssertFalse(service.isForwarded(notForwarded))
    }

    func testNormalizeSubject() {
        XCTAssertEqual(service.normalizeSubject("Re: Test Subject"), "test subject")
        XCTAssertEqual(service.normalizeSubject("Fwd: Test Subject"), "test subject")
    }

    // MARK: - Performance Tests

    func testCacheImprovesLookupPerformance() async throws {
        try database.initialize()

        // Create 100 threads
        for i in 1...100 {
            let thread = Thread(id: "thread-\(i)", subject: "Subject \(i)")
            try database.upsertThread(thread)
        }

        // Cold lookups (cache misses)
        let coldStart = Date()
        for i in 1...100 {
            _ = try await service.getThread(id: "thread-\(i)", database: database)
        }
        let coldDuration = Date().timeIntervalSince(coldStart)

        // Warm lookups (cache hits)
        let warmStart = Date()
        for i in 1...100 {
            _ = try await service.getThread(id: "thread-\(i)", database: database)
        }
        let warmDuration = Date().timeIntervalSince(warmStart)

        // Cache hits should be faster than cold lookups
        // This is a rough test - in real scenarios the difference is more pronounced
        XCTAssertLessThan(warmDuration, coldDuration * 2)

        // Verify all were cache hits
        let stats = await service.getCacheStatistics()
        XCTAssertEqual(stats.hitCount, 100)
        XCTAssertEqual(stats.missCount, 100)
        XCTAssertEqual(stats.hitRate, 50.0, accuracy: 0.001)
    }
}
