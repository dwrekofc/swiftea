import XCTest
@testable import SwiftEAKit

/// Performance benchmarks for thread operations.
/// These tests measure and track the performance of:
/// - Thread listing operations
/// - Thread detection operations
/// - Sync performance with threading enabled
///
/// Run with: swift test --filter PerformanceBenchmarkTests
/// For CI tracking, use: swift test --filter PerformanceBenchmarkTests 2>&1 | tee benchmark-results.txt
final class PerformanceBenchmarkTests: XCTestCase {
    var testDir: String!
    var database: MailDatabase!
    var threadService: ThreadDetectionService!

    override func setUp() {
        super.setUp()
        testDir = NSTemporaryDirectory() + "swiftea-benchmark-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        let dbPath = (testDir as NSString).appendingPathComponent("mail.db")
        database = MailDatabase(databasePath: dbPath)
        try? database.initialize()
        threadService = ThreadDetectionService()
    }

    override func tearDown() {
        database?.close()
        try? FileManager.default.removeItem(atPath: testDir)
        database = nil
        threadService = nil
        super.tearDown()
    }

    // MARK: - Test Data Generation

    /// Generate test messages in bulk for benchmarking
    private func generateTestMessages(count: Int, threadsCount: Int) throws -> [MailMessage] {
        var messages: [MailMessage] = []
        messages.reserveCapacity(count)

        let messagesPerThread = count / threadsCount
        var threadRoots: [String] = []

        for threadIndex in 0..<threadsCount {
            let rootMessageId = "<root-\(threadIndex)@benchmark.test>"
            threadRoots.append(rootMessageId)

            // Create root message
            let rootMessage = MailMessage(
                id: "msg-\(threadIndex)-0",
                messageId: rootMessageId,
                subject: "Thread \(threadIndex): Performance Test Subject",
                senderName: "Sender \(threadIndex % 10)",
                senderEmail: "sender\(threadIndex % 10)@example.com",
                dateReceived: Date(timeIntervalSince1970: Double(1000000 + threadIndex * 1000))
            )
            messages.append(rootMessage)
            try database.upsertMessage(rootMessage)

            // Create replies in this thread
            var previousMessageId = rootMessageId
            for replyIndex in 1..<messagesPerThread {
                let globalIndex = threadIndex * messagesPerThread + replyIndex
                let messageId = "<reply-\(threadIndex)-\(replyIndex)@benchmark.test>"

                // Build references chain
                var references: [String] = [rootMessageId]
                if previousMessageId != rootMessageId {
                    references.append(previousMessageId)
                }

                let message = MailMessage(
                    id: "msg-\(globalIndex)",
                    messageId: messageId,
                    subject: "Re: Thread \(threadIndex): Performance Test Subject",
                    senderName: "Sender \((globalIndex + replyIndex) % 10)",
                    senderEmail: "sender\((globalIndex + replyIndex) % 10)@example.com",
                    dateReceived: Date(timeIntervalSince1970: Double(1000000 + globalIndex * 1000 + replyIndex)),
                    inReplyTo: previousMessageId,
                    references: references
                )
                messages.append(message)
                try database.upsertMessage(message)

                previousMessageId = messageId
            }
        }

        return messages
    }

    /// Generate threads in the database for listing benchmarks
    private func generateThreadsForListing(count: Int, messagesPerThread: Int = 5) throws {
        for threadIndex in 0..<count {
            let threadId = "thread-\(threadIndex)"
            let thread = Thread(
                id: threadId,
                subject: "Thread \(threadIndex): Performance Test Subject",
                participantCount: min(messagesPerThread, 5),
                messageCount: messagesPerThread,
                firstDate: Date(timeIntervalSince1970: Double(1000000 + threadIndex * 10000)),
                lastDate: Date(timeIntervalSince1970: Double(1000000 + threadIndex * 10000 + messagesPerThread * 1000))
            )
            try database.upsertThread(thread)

            // Create messages for this thread
            for msgIndex in 0..<messagesPerThread {
                let messageId = "msg-\(threadIndex)-\(msgIndex)"
                let message = MailMessage(
                    id: messageId,
                    messageId: "<\(messageId)@benchmark.test>",
                    subject: msgIndex == 0 ? "Thread \(threadIndex): Performance Test Subject" : "Re: Thread \(threadIndex): Performance Test Subject",
                    senderEmail: "sender\(msgIndex % 5)@example.com",
                    dateReceived: Date(timeIntervalSince1970: Double(1000000 + threadIndex * 10000 + msgIndex * 1000)),
                    threadId: threadId
                )
                try database.upsertMessage(message)
                try database.addMessageToThread(messageId: messageId, threadId: threadId)
            }
        }
    }

    // MARK: - Thread Listing Performance Benchmarks

    /// Benchmark: List 100 threads (typical use case)
    func testThreadListingPerformance_100Threads() throws {
        try generateThreadsForListing(count: 100)

        measure {
            do {
                let threads = try database.getThreads(limit: 100, offset: 0)
                XCTAssertEqual(threads.count, 100)
            } catch {
                XCTFail("Thread listing failed: \(error)")
            }
        }
    }

    /// Benchmark: List 1000 threads (larger inbox)
    func testThreadListingPerformance_1000Threads() throws {
        try generateThreadsForListing(count: 1000)

        measure {
            do {
                let threads = try database.getThreads(limit: 100, offset: 0)
                XCTAssertEqual(threads.count, 100)
            } catch {
                XCTFail("Thread listing failed: \(error)")
            }
        }
    }

    /// Benchmark: List threads with sorting by date
    func testThreadListingPerformance_SortByDate() throws {
        try generateThreadsForListing(count: 500)

        measure {
            do {
                let threads = try database.getThreads(limit: 100, offset: 0, sortBy: .date)
                XCTAssertEqual(threads.count, 100)
            } catch {
                XCTFail("Thread listing failed: \(error)")
            }
        }
    }

    /// Benchmark: List threads with sorting by subject
    func testThreadListingPerformance_SortBySubject() throws {
        try generateThreadsForListing(count: 500)

        measure {
            do {
                let threads = try database.getThreads(limit: 100, offset: 0, sortBy: .subject)
                XCTAssertEqual(threads.count, 100)
            } catch {
                XCTFail("Thread listing failed: \(error)")
            }
        }
    }

    /// Benchmark: List threads with sorting by message count
    func testThreadListingPerformance_SortByMessageCount() throws {
        try generateThreadsForListing(count: 500)

        measure {
            do {
                let threads = try database.getThreads(limit: 100, offset: 0, sortBy: .messageCount)
                XCTAssertEqual(threads.count, 100)
            } catch {
                XCTFail("Thread listing failed: \(error)")
            }
        }
    }

    /// Benchmark: List threads filtered by participant
    func testThreadListingPerformance_FilterByParticipant() throws {
        try generateThreadsForListing(count: 500)

        measure {
            do {
                let threads = try database.getThreads(limit: 100, offset: 0, participant: "sender0@example.com")
                XCTAssertGreaterThan(threads.count, 0)
            } catch {
                XCTFail("Thread listing with participant filter failed: \(error)")
            }
        }
    }

    /// Benchmark: Paginated thread listing (offset performance)
    func testThreadListingPerformance_Pagination() throws {
        try generateThreadsForListing(count: 1000)

        measure {
            do {
                // Simulate pagination through results
                var totalFetched = 0
                for page in 0..<5 {
                    let threads = try database.getThreads(limit: 100, offset: page * 100)
                    totalFetched += threads.count
                }
                XCTAssertEqual(totalFetched, 500)
            } catch {
                XCTFail("Paginated thread listing failed: \(error)")
            }
        }
    }

    /// Benchmark: Get thread count
    func testThreadCountPerformance() throws {
        try generateThreadsForListing(count: 1000)

        measure {
            do {
                let count = try database.getThreadCount()
                XCTAssertEqual(count, 1000)
            } catch {
                XCTFail("Thread count failed: \(error)")
            }
        }
    }

    /// Benchmark: Get thread count with participant filter
    func testThreadCountPerformance_WithParticipant() throws {
        try generateThreadsForListing(count: 500)

        measure {
            do {
                let count = try database.getThreadCount(participant: "sender0@example.com")
                XCTAssertGreaterThan(count, 0)
            } catch {
                XCTFail("Thread count with participant failed: \(error)")
            }
        }
    }

    // MARK: - Thread Detection Performance Benchmarks

    /// Benchmark: Thread ID detection (no database)
    func testThreadIdDetection_1000Messages() throws {
        var messages: [(messageId: String, inReplyTo: String?, references: String?, subject: String)] = []

        // Generate 1000 test message data
        for i in 0..<1000 {
            let threadRoot = "<root-\(i / 10)@test.com>"
            if i % 10 == 0 {
                // Root message
                messages.append((
                    messageId: threadRoot,
                    inReplyTo: nil,
                    references: nil,
                    subject: "Thread \(i / 10)"
                ))
            } else {
                // Reply
                messages.append((
                    messageId: "<reply-\(i)@test.com>",
                    inReplyTo: threadRoot,
                    references: threadRoot,
                    subject: "Re: Thread \(i / 10)"
                ))
            }
        }

        measure {
            for msg in messages {
                _ = threadService.detectThreadId(
                    messageId: msg.messageId,
                    inReplyTo: msg.inReplyTo,
                    references: msg.references,
                    subject: msg.subject
                )
            }
        }
    }

    /// Benchmark: Full thread processing with database (100 messages)
    func testThreadProcessing_100Messages() throws {
        let messages = try generateTestMessages(count: 100, threadsCount: 10)

        measure {
            do {
                for message in messages {
                    _ = try threadService.processMessageForThreading(message, database: database)
                }
            } catch {
                XCTFail("Thread processing failed: \(error)")
            }
        }
    }

    /// Benchmark: Batch thread processing (100 messages)
    func testBatchThreadProcessing_100Messages() throws {
        let messages = try generateTestMessages(count: 100, threadsCount: 10)

        measure {
            do {
                _ = try threadService.processMessagesForThreading(messages, database: database)
            } catch {
                XCTFail("Batch thread processing failed: \(error)")
            }
        }
    }

    /// Benchmark: Thread metadata extraction
    func testThreadMetadataExtraction() throws {
        try generateThreadsForListing(count: 100, messagesPerThread: 10)

        // Get thread IDs for extraction
        let threads = try database.getThreads(limit: 100)
        let threadIds = threads.map { $0.id }

        measure {
            do {
                _ = try threadService.extractThreadMetadata(threadIds: threadIds, database: database)
            } catch {
                XCTFail("Thread metadata extraction failed: \(error)")
            }
        }
    }

    /// Benchmark: Get messages in thread
    func testGetMessagesInThread() throws {
        try generateThreadsForListing(count: 10, messagesPerThread: 50)

        // Get first thread ID
        let threads = try database.getThreads(limit: 1)
        guard let thread = threads.first else {
            XCTFail("No threads found")
            return
        }

        measure {
            do {
                let messages = try database.getMessagesInThreadViaJunction(threadId: thread.id, limit: 100)
                XCTAssertGreaterThan(messages.count, 0)
            } catch {
                XCTFail("Get messages in thread failed: \(error)")
            }
        }
    }

    /// Benchmark: Update thread positions
    func testUpdateThreadPositions() throws {
        try generateThreadsForListing(count: 10, messagesPerThread: 20)

        let threads = try database.getThreads(limit: 10)

        measure {
            do {
                for thread in threads {
                    try database.updateThreadPositions(threadId: thread.id)
                }
            } catch {
                XCTFail("Update thread positions failed: \(error)")
            }
        }
    }

    // MARK: - Sync Performance with Threading Benchmarks

    /// Benchmark: Thread detection during simulated sync (500 messages)
    func testSyncWithThreading_500Messages() throws {
        // Generate messages without threading (simulating initial import)
        var messages: [MailMessage] = []
        let threadsCount = 50
        let messagesPerThread = 10

        for threadIndex in 0..<threadsCount {
            let rootMessageId = "<sync-root-\(threadIndex)@benchmark.test>"

            let rootMessage = MailMessage(
                id: "sync-msg-\(threadIndex)-0",
                messageId: rootMessageId,
                subject: "Sync Thread \(threadIndex)",
                senderEmail: "sender\(threadIndex % 10)@example.com",
                dateReceived: Date(timeIntervalSince1970: Double(1000000 + threadIndex * 10000))
            )
            messages.append(rootMessage)

            var previousMessageId = rootMessageId
            for replyIndex in 1..<messagesPerThread {
                let globalIndex = threadIndex * messagesPerThread + replyIndex
                let messageId = "<sync-reply-\(threadIndex)-\(replyIndex)@benchmark.test>"

                var references: [String] = [rootMessageId]
                if previousMessageId != rootMessageId {
                    references.append(previousMessageId)
                }

                let message = MailMessage(
                    id: "sync-msg-\(globalIndex)",
                    messageId: messageId,
                    subject: "Re: Sync Thread \(threadIndex)",
                    senderEmail: "sender\((globalIndex + replyIndex) % 10)@example.com",
                    dateReceived: Date(timeIntervalSince1970: Double(1000000 + globalIndex * 1000 + replyIndex)),
                    inReplyTo: previousMessageId,
                    references: references
                )
                messages.append(message)
                previousMessageId = messageId
            }
        }

        // Upsert all messages first
        for message in messages {
            try database.upsertMessage(message)
        }

        // Measure threading phase of sync
        measure {
            do {
                _ = try threadService.processMessagesForThreading(messages, database: database)
            } catch {
                XCTFail("Sync threading failed: \(error)")
            }
        }
    }

    /// Benchmark: Incremental sync thread detection (50 new messages in existing threads)
    func testIncrementalSyncThreading_50NewMessages() throws {
        // Create existing threads first
        try generateThreadsForListing(count: 100, messagesPerThread: 10)

        // Generate 50 new messages that reply to existing threads
        var newMessages: [MailMessage] = []
        let threads = try database.getThreads(limit: 50)

        for (index, thread) in threads.enumerated() {
            // Get first message in thread to build reference
            let existingMessages = try database.getMessagesInThreadViaJunction(threadId: thread.id, limit: 1)
            guard let existingMessage = existingMessages.first else { continue }

            let newMessage = MailMessage(
                id: "new-msg-\(index)",
                messageId: "<new-reply-\(index)@benchmark.test>",
                subject: "Re: \(thread.subject ?? "Thread")",
                senderEmail: "newsender@example.com",
                dateReceived: Date(),
                inReplyTo: existingMessage.messageId,
                references: existingMessage.messageId.map { [$0] } ?? []
            )
            newMessages.append(newMessage)
            try database.upsertMessage(newMessage)
        }

        measure {
            do {
                _ = try threadService.processMessagesForThreading(newMessages, database: database)
            } catch {
                XCTFail("Incremental sync threading failed: \(error)")
            }
        }
    }

    /// Benchmark: Thread update metadata recalculation
    func testThreadMetadataUpdate() throws {
        try generateThreadsForListing(count: 100, messagesPerThread: 10)

        let threads = try database.getThreads(limit: 100)

        measure {
            do {
                for thread in threads {
                    try threadService.updateThreadMetadata(threadId: thread.id, database: database)
                }
            } catch {
                XCTFail("Thread metadata update failed: \(error)")
            }
        }
    }

    // MARK: - Large Scale Benchmarks (for CI trend tracking)

    /// Benchmark: Large inbox simulation (10000 messages in 1000 threads)
    func testLargeInbox_10000Messages() throws {
        // This test is slower - useful for CI baseline tracking
        // Generate 1000 threads with 10 messages each
        let threadCount = 1000
        let messagesPerThread = 10

        for threadIndex in 0..<threadCount {
            let threadId = "large-thread-\(threadIndex)"
            let thread = Thread(
                id: threadId,
                subject: "Large Thread \(threadIndex)",
                participantCount: 5,
                messageCount: messagesPerThread,
                firstDate: Date(timeIntervalSince1970: Double(threadIndex * 10000)),
                lastDate: Date(timeIntervalSince1970: Double(threadIndex * 10000 + messagesPerThread * 1000))
            )
            try database.upsertThread(thread)

            for msgIndex in 0..<messagesPerThread {
                let messageId = "large-msg-\(threadIndex)-\(msgIndex)"
                let message = MailMessage(
                    id: messageId,
                    messageId: "<\(messageId)@benchmark.test>",
                    subject: "Large Thread \(threadIndex)",
                    senderEmail: "sender\(msgIndex % 5)@example.com",
                    dateReceived: Date(timeIntervalSince1970: Double(threadIndex * 10000 + msgIndex * 1000)),
                    threadId: threadId
                )
                try database.upsertMessage(message)
                try database.addMessageToThread(messageId: messageId, threadId: threadId)
            }
        }

        // Measure thread listing with large dataset
        measure {
            do {
                let threads = try database.getThreads(limit: 100, offset: 0)
                XCTAssertEqual(threads.count, 100)
            } catch {
                XCTFail("Large inbox thread listing failed: \(error)")
            }
        }
    }

    /// Benchmark: Thread detection scalability (1000 messages at once)
    func testThreadDetectionScalability_1000Messages() throws {
        // Generate and process 1000 messages
        let messages = try generateTestMessages(count: 1000, threadsCount: 100)

        measure {
            do {
                _ = try threadService.processMessagesForThreading(messages, database: database)
            } catch {
                XCTFail("Large batch thread processing failed: \(error)")
            }
        }
    }
}
