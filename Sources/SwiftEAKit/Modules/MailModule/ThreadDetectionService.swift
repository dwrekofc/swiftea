// ThreadDetectionService - Detect and assign threads to incoming email messages

import Foundation

/// Service for detecting and managing email thread assignments.
///
/// This service orchestrates the threading process for incoming emails:
/// 1. Parses threading headers (Message-ID, In-Reply-To, References)
/// 2. Generates deterministic thread IDs
/// 3. Matches messages to existing threads or creates new ones
/// 4. Updates thread metadata (participant count, message count, dates)
public final class ThreadDetectionService: Sendable {

    private let headerParser: ThreadingHeaderParser
    private let idGenerator: ThreadIDGenerator

    /// Creates a new ThreadDetectionService with default dependencies
    public init() {
        self.headerParser = ThreadingHeaderParser()
        self.idGenerator = ThreadIDGenerator()
    }

    /// Creates a new ThreadDetectionService with custom dependencies (for testing)
    public init(headerParser: ThreadingHeaderParser, idGenerator: ThreadIDGenerator) {
        self.headerParser = headerParser
        self.idGenerator = idGenerator
    }

    // MARK: - Thread Detection Result

    /// Result of thread detection for a message
    public struct ThreadDetectionResult: Sendable, Equatable {
        /// The assigned thread ID
        public let threadId: String
        /// Whether a new thread was created
        public let isNewThread: Bool
        /// The parsed threading headers
        public let headers: ThreadingHeaderParser.ThreadingHeaders

        public init(threadId: String, isNewThread: Bool, headers: ThreadingHeaderParser.ThreadingHeaders) {
            self.threadId = threadId
            self.isNewThread = isNewThread
            self.headers = headers
        }
    }

    // MARK: - Thread Detection

    /// Detect the thread for a message based on its headers.
    ///
    /// This method parses the threading headers and generates a thread ID,
    /// but does not interact with the database. Use this when you need
    /// the thread ID without database operations.
    ///
    /// - Parameters:
    ///   - messageId: The RFC822 Message-ID header
    ///   - inReplyTo: The In-Reply-To header
    ///   - references: The References header (raw string)
    ///   - subject: The message subject (fallback for threading)
    /// - Returns: The generated thread ID
    public func detectThreadId(
        messageId: String?,
        inReplyTo: String?,
        references: String?,
        subject: String?
    ) -> String {
        let headers = headerParser.parseThreadingHeaders(
            messageId: messageId,
            inReplyTo: inReplyTo,
            references: references
        )

        return idGenerator.generateThreadId(
            messageId: headers.messageId,
            inReplyTo: headers.inReplyTo,
            references: headers.references,
            subject: subject
        )
    }

    /// Detect the thread for a message using parsed threading headers.
    ///
    /// - Parameters:
    ///   - headers: Pre-parsed threading headers
    ///   - subject: The message subject (fallback for threading)
    /// - Returns: The generated thread ID
    public func detectThreadId(
        from headers: ThreadingHeaderParser.ThreadingHeaders,
        subject: String?
    ) -> String {
        return idGenerator.generateThreadId(
            messageId: headers.messageId,
            inReplyTo: headers.inReplyTo,
            references: headers.references,
            subject: subject
        )
    }

    /// Detect the thread for a MailMessage.
    ///
    /// - Parameter message: The mail message
    /// - Returns: The generated thread ID
    public func detectThreadId(from message: MailMessage) -> String {
        return idGenerator.generateThreadId(from: message)
    }

    // MARK: - Full Thread Processing

    /// Process a message for threading - detect thread, create if needed, and update metadata.
    ///
    /// This is the main entry point for thread detection. It:
    /// 1. Parses the message's threading headers
    /// 2. Generates the thread ID
    /// 3. Creates or updates the thread in the database
    /// 4. Assigns the message to the thread
    /// 5. Updates thread metadata
    ///
    /// - Parameters:
    ///   - message: The message to process
    ///   - database: The mail database instance
    /// - Returns: The thread detection result
    /// - Throws: Database errors
    public func processMessageForThreading(
        _ message: MailMessage,
        database: MailDatabase
    ) throws -> ThreadDetectionResult {
        // Parse threading headers
        let headers = ThreadingHeaderParser.ThreadingHeaders(
            messageId: message.messageId,
            inReplyTo: message.inReplyTo,
            references: message.references
        )

        // Generate thread ID
        let threadId = idGenerator.generateThreadId(
            messageId: headers.messageId,
            inReplyTo: headers.inReplyTo,
            references: headers.references,
            subject: message.subject
        )

        // Check if thread exists
        let existingThread = try database.getThread(id: threadId)
        let isNewThread = existingThread == nil

        // Create or update thread
        let thread = try createOrUpdateThread(
            threadId: threadId,
            message: message,
            existingThread: existingThread,
            database: database
        )

        // Upsert the thread
        try database.upsertThread(thread)

        // Update the message's thread_id
        try database.updateMessageThreadId(messageId: message.id, threadId: threadId)

        // Add to junction table
        try database.addMessageToThread(messageId: message.id, threadId: threadId)

        return ThreadDetectionResult(
            threadId: threadId,
            isNewThread: isNewThread,
            headers: headers
        )
    }

    /// Process multiple messages for threading in batch.
    ///
    /// - Parameters:
    ///   - messages: The messages to process
    ///   - database: The mail database instance
    /// - Returns: Array of thread detection results (in same order as input)
    /// - Throws: Database errors
    public func processMessagesForThreading(
        _ messages: [MailMessage],
        database: MailDatabase
    ) throws -> [ThreadDetectionResult] {
        var results: [ThreadDetectionResult] = []
        results.reserveCapacity(messages.count)

        for message in messages {
            let result = try processMessageForThreading(message, database: database)
            results.append(result)
        }

        return results
    }

    // MARK: - Thread Metadata Update

    /// Update thread metadata based on its current messages.
    ///
    /// Call this after adding or removing messages from a thread to ensure
    /// the metadata (participant count, message count, dates) is accurate.
    ///
    /// - Parameters:
    ///   - threadId: The thread ID to update
    ///   - database: The mail database instance
    /// - Throws: Database errors
    public func updateThreadMetadata(
        threadId: String,
        database: MailDatabase
    ) throws {
        // Get all messages in the thread
        let messages = try database.getMessagesInThreadViaJunction(threadId: threadId, limit: 10000)

        guard !messages.isEmpty else {
            // Thread has no messages - could delete it or leave it empty
            return
        }

        // Calculate metadata
        let (participantCount, firstDate, lastDate) = calculateThreadMetadata(messages: messages)

        // Get current thread to preserve subject
        let existingThread = try database.getThread(id: threadId)
        let subject = existingThread?.subject ?? messages.first?.subject

        // Create updated thread
        let updatedThread = Thread(
            id: threadId,
            subject: subject,
            participantCount: participantCount,
            messageCount: messages.count,
            firstDate: firstDate,
            lastDate: lastDate
        )

        try database.upsertThread(updatedThread)
    }

    // MARK: - Private Helpers

    /// Create or update a thread based on the message being added.
    private func createOrUpdateThread(
        threadId: String,
        message: MailMessage,
        existingThread: Thread?,
        database: MailDatabase
    ) throws -> Thread {
        let messageDate = message.dateReceived ?? message.dateSent

        if let existing = existingThread {
            // Update existing thread
            let firstDate = minDate(existing.firstDate, messageDate)
            let lastDate = maxDate(existing.lastDate, messageDate)

            // Count unique participants
            let currentMessages = try database.getMessagesInThreadViaJunction(threadId: threadId, limit: 10000)
            let allMessages = currentMessages + [message]
            let participantCount = countParticipants(allMessages)

            return Thread(
                id: threadId,
                subject: existing.subject ?? message.subject,
                participantCount: participantCount,
                messageCount: existing.messageCount + 1,
                firstDate: firstDate,
                lastDate: lastDate
            )
        } else {
            // Create new thread
            return Thread(
                id: threadId,
                subject: message.subject,
                participantCount: countParticipants([message]),
                messageCount: 1,
                firstDate: messageDate,
                lastDate: messageDate
            )
        }
    }

    /// Calculate thread metadata from a list of messages.
    private func calculateThreadMetadata(messages: [MailMessage]) -> (participantCount: Int, firstDate: Date?, lastDate: Date?) {
        let participantCount = countParticipants(messages)

        var firstDate: Date?
        var lastDate: Date?

        for message in messages {
            let date = message.dateReceived ?? message.dateSent
            if let d = date {
                if firstDate == nil || d < firstDate! {
                    firstDate = d
                }
                if lastDate == nil || d > lastDate! {
                    lastDate = d
                }
            }
        }

        return (participantCount, firstDate, lastDate)
    }

    /// Count unique participants (email addresses) in a set of messages.
    private func countParticipants(_ messages: [MailMessage]) -> Int {
        var emails = Set<String>()

        for message in messages {
            if let senderEmail = message.senderEmail {
                emails.insert(senderEmail.lowercased())
            }
        }

        // Note: For full participant counting, we'd also need to count
        // recipients (To, Cc, Bcc). This would require loading recipients
        // from the database. For now, we count unique senders.
        return max(1, emails.count)
    }

    /// Return the minimum of two optional dates.
    private func minDate(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case (nil, nil): return nil
        case (let date, nil): return date
        case (nil, let date): return date
        case (let d1?, let d2?): return d1 < d2 ? d1 : d2
        }
    }

    /// Return the maximum of two optional dates.
    private func maxDate(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case (nil, nil): return nil
        case (let date, nil): return date
        case (nil, let date): return date
        case (let d1?, let d2?): return d1 > d2 ? d1 : d2
        }
    }
}

// MARK: - Convenience Extensions

extension ThreadDetectionService {

    /// Check if a message appears to be part of an existing thread.
    ///
    /// - Parameter message: The message to check
    /// - Returns: true if the message has reply indicators
    public func isReply(_ message: MailMessage) -> Bool {
        return idGenerator.isReply(inReplyTo: message.inReplyTo, references: message.references)
    }

    /// Check if a message appears to be forwarded.
    ///
    /// - Parameter message: The message to check
    /// - Returns: true if the subject indicates a forwarded message
    public func isForwarded(_ message: MailMessage) -> Bool {
        return idGenerator.isForwarded(subject: message.subject)
    }

    /// Get the normalized subject for threading (strips Re:, Fwd:, etc.).
    ///
    /// - Parameter subject: The raw email subject
    /// - Returns: Normalized subject for comparison
    public func normalizeSubject(_ subject: String) -> String {
        return idGenerator.normalizeSubject(subject)
    }
}
