// ThreadIDGenerator - Generate deterministic thread IDs for email threading

import Foundation
import CryptoKit

/// Generates deterministic, stable thread IDs for grouping related email messages.
///
/// The algorithm works as follows:
/// 1. If the message has References, use the **first** message ID (the thread root)
/// 2. If no References but has In-Reply-To, use the In-Reply-To (direct parent, thread root for simple reply chains)
/// 3. If neither (standalone message), use the message's own Message-ID (it's the thread root)
/// 4. If no Message-ID available (malformed email), fall back to subject-based grouping
///
/// This ensures:
/// - All messages in a thread share the same thread ID
/// - Thread IDs are stable across multiple sync runs
/// - Reply chains and forwarded messages are grouped correctly
public final class ThreadIDGenerator: Sendable {

    public init() {}

    // MARK: - Thread ID Generation

    /// Generate a thread ID from threading headers.
    ///
    /// - Parameters:
    ///   - messageId: The RFC822 Message-ID of this message (normalized, with angle brackets)
    ///   - inReplyTo: The In-Reply-To header (normalized, with angle brackets)
    ///   - references: Array of message IDs from the References header (first is thread root)
    /// - Returns: A deterministic 32-character hex thread ID
    public func generateThreadId(
        messageId: String?,
        inReplyTo: String?,
        references: [String]
    ) -> String {
        // Determine the thread root message ID
        let threadRootId = determineThreadRoot(
            messageId: messageId,
            inReplyTo: inReplyTo,
            references: references
        )

        // Hash the thread root to create the thread ID
        return hashMessageId(threadRootId)
    }

    /// Generate a thread ID from parsed threading headers.
    ///
    /// - Parameter headers: Parsed threading headers from ThreadingHeaderParser
    /// - Returns: A deterministic 32-character hex thread ID
    public func generateThreadId(from headers: ThreadingHeaderParser.ThreadingHeaders) -> String {
        return generateThreadId(
            messageId: headers.messageId,
            inReplyTo: headers.inReplyTo,
            references: headers.references
        )
    }

    /// Generate a thread ID from a MailMessage.
    ///
    /// - Parameter message: The mail message
    /// - Returns: A deterministic 32-character hex thread ID
    public func generateThreadId(from message: MailMessage) -> String {
        return generateThreadId(
            messageId: message.messageId,
            inReplyTo: message.inReplyTo,
            references: message.references
        )
    }

    /// Generate a thread ID with a subject fallback for messages without proper threading headers.
    ///
    /// - Parameters:
    ///   - messageId: The RFC822 Message-ID of this message
    ///   - inReplyTo: The In-Reply-To header
    ///   - references: Array of message IDs from the References header
    ///   - subject: The email subject (used as fallback when no Message-ID available)
    /// - Returns: A deterministic 32-character hex thread ID
    public func generateThreadId(
        messageId: String?,
        inReplyTo: String?,
        references: [String],
        subject: String?
    ) -> String {
        // First try with threading headers
        if let threadRoot = determineThreadRootOrNil(
            messageId: messageId,
            inReplyTo: inReplyTo,
            references: references
        ) {
            return hashMessageId(threadRoot)
        }

        // Fall back to subject-based grouping
        if let subject = subject, !subject.isEmpty {
            let normalizedSubject = normalizeSubject(subject)
            return hashString("subj:\(normalizedSubject)")
        }

        // Absolute fallback: generate a unique ID (message won't be threaded)
        return hashString("noid:\(UUID().uuidString)")
    }

    // MARK: - Thread Root Detection

    /// Determine the thread root message ID.
    ///
    /// Returns the message ID that represents the start of the thread:
    /// - First reference if References header exists
    /// - In-Reply-To if no References but has In-Reply-To
    /// - Own Message-ID if this is a standalone message
    ///
    /// - Parameters:
    ///   - messageId: The message's own Message-ID
    ///   - inReplyTo: The In-Reply-To header
    ///   - references: The References header (array of message IDs)
    /// - Returns: The thread root message ID (never nil, falls back to generated ID)
    public func determineThreadRoot(
        messageId: String?,
        inReplyTo: String?,
        references: [String]
    ) -> String {
        if let root = determineThreadRootOrNil(
            messageId: messageId,
            inReplyTo: inReplyTo,
            references: references
        ) {
            return root
        }

        // Absolute fallback for malformed emails without any message ID
        return "<fallback-\(UUID().uuidString)@local>"
    }

    /// Determine the thread root message ID, returning nil if none can be determined.
    private func determineThreadRootOrNil(
        messageId: String?,
        inReplyTo: String?,
        references: [String]
    ) -> String? {
        // Strategy 1: Use the first reference (this is the original thread root)
        // The References header lists message IDs from oldest (root) to newest (parent)
        if let firstRef = references.first, !firstRef.isEmpty {
            return normalizeMessageIdForHashing(firstRef)
        }

        // Strategy 2: Use In-Reply-To if no References
        // This handles simple reply chains where only In-Reply-To is set
        if let replyTo = inReplyTo, !replyTo.isEmpty {
            return normalizeMessageIdForHashing(replyTo)
        }

        // Strategy 3: Use own Message-ID (this message is the thread root)
        if let msgId = messageId, !msgId.isEmpty {
            return normalizeMessageIdForHashing(msgId)
        }

        return nil
    }

    /// Check if a message appears to be a reply based on its threading headers.
    ///
    /// - Parameters:
    ///   - inReplyTo: The In-Reply-To header
    ///   - references: The References header
    /// - Returns: true if the message has reply indicators
    public func isReply(inReplyTo: String?, references: [String]) -> Bool {
        return (inReplyTo != nil && !inReplyTo!.isEmpty) || !references.isEmpty
    }

    /// Check if a message appears to be forwarded based on its subject.
    ///
    /// - Parameter subject: The email subject
    /// - Returns: true if the subject indicates a forwarded message
    public func isForwarded(subject: String?) -> Bool {
        guard let subject = subject else { return false }
        let lower = subject.lowercased().trimmingCharacters(in: .whitespaces)
        return lower.hasPrefix("fwd:") ||
               lower.hasPrefix("fw:") ||
               lower.hasPrefix("forwarded:")
    }

    // MARK: - Normalization

    /// Normalize a message ID for consistent hashing.
    /// Removes angle brackets, trims whitespace, and lowercases.
    private func normalizeMessageIdForHashing(_ messageId: String) -> String {
        var normalized = messageId.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove angle brackets if present
        if normalized.hasPrefix("<") {
            normalized = String(normalized.dropFirst())
        }
        if normalized.hasSuffix(">") {
            normalized = String(normalized.dropLast())
        }

        return normalized.lowercased()
    }

    /// Normalize an email subject for subject-based threading.
    /// Removes common reply/forward prefixes and normalizes whitespace.
    public func normalizeSubject(_ subject: String) -> String {
        var normalized = subject.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove common reply/forward prefixes (can be nested like "Re: Re: Fwd:")
        let prefixPattern = #"^(?:(?:re|fwd?|aw|antw|vs|sv|odp|r):\s*)+"#
        if let regex = try? NSRegularExpression(pattern: prefixPattern, options: .caseInsensitive) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            normalized = regex.stringByReplacingMatches(
                in: normalized,
                range: range,
                withTemplate: ""
            )
        }

        // Normalize whitespace (collapse multiple spaces)
        normalized = normalized
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return normalized.lowercased()
    }

    // MARK: - Hashing

    /// Hash a message ID to create a thread ID.
    private func hashMessageId(_ messageId: String) -> String {
        return hashString("thread:\(normalizeMessageIdForHashing(messageId))")
    }

    /// Generate a SHA-256 hash and return first 32 characters (128 bits).
    private func hashString(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        // Return first 32 characters for a reasonable ID length
        return String(hashString.prefix(32))
    }
}

// MARK: - Validation Extension

extension ThreadIDGenerator {

    /// Check if a string looks like a valid thread ID.
    public func isValidThreadId(_ id: String) -> Bool {
        // Valid thread IDs are 32 lowercase hex characters
        guard id.count == 32 else { return false }
        return id.allSatisfy { $0.isHexDigit }
    }
}

/// Helper for hex validation
private extension Character {
    var isHexDigit: Bool {
        return ("0"..."9").contains(self) || ("a"..."f").contains(self)
    }
}
