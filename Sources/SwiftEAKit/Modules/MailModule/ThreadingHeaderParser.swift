// ThreadingHeaderParser - Parse and normalize email threading headers

import Foundation

/// Parses and normalizes Message-ID, References, and In-Reply-To headers
/// for email threading. Handles malformed headers gracefully.
public final class ThreadingHeaderParser: Sendable {

    public init() {}

    // MARK: - Message-ID Parsing

    /// Normalizes a Message-ID header value.
    /// - Parameter value: Raw Message-ID header (may include angle brackets, whitespace)
    /// - Returns: Normalized Message-ID (trimmed, with angle brackets) or nil if invalid
    public func normalizeMessageId(_ value: String?) -> String? {
        guard let value = value, !value.isEmpty else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract the first valid message ID (some headers have multiple or malformed values)
        if let extracted = extractFirstMessageId(trimmed) {
            return extracted
        }

        // If no angle brackets but looks like a message ID, add them
        if !trimmed.hasPrefix("<") && trimmed.contains("@") {
            return "<\(trimmed)>"
        }

        return nil
    }

    /// Extracts the first valid message ID from a string.
    /// Message IDs are enclosed in angle brackets: <message-id@domain>
    private func extractFirstMessageId(_ text: String) -> String? {
        let pattern = #"<[^<>\s]+>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, range: range),
           let swiftRange = Range(match.range, in: text) {
            return String(text[swiftRange])
        }

        return nil
    }

    // MARK: - In-Reply-To Parsing

    /// Normalizes an In-Reply-To header value.
    /// The In-Reply-To header should contain a single message ID referencing the parent message.
    /// - Parameter value: Raw In-Reply-To header
    /// - Returns: Normalized message ID or nil if invalid/missing
    public func normalizeInReplyTo(_ value: String?) -> String? {
        guard let value = value, !value.isEmpty else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        // In-Reply-To should be a single message ID, but some mail clients put multiple
        // Take the first valid one
        return extractFirstMessageId(trimmed)
    }

    // MARK: - References Parsing

    /// Parses and normalizes a References header into an array of message IDs.
    /// The References header contains a list of message IDs representing the thread ancestry.
    /// - Parameter value: Raw References header (space/newline separated message IDs)
    /// - Returns: Array of normalized message IDs (empty array if none found)
    public func parseReferences(_ value: String?) -> [String] {
        guard let value = value, !value.isEmpty else { return [] }

        return extractAllMessageIds(value)
    }

    /// Extracts all valid message IDs from a string.
    private func extractAllMessageIds(_ text: String) -> [String] {
        let pattern = #"<[^<>\s]+>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        return matches.compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    // MARK: - Combined Parsing

    /// Parsed threading headers from an email
    public struct ThreadingHeaders: Sendable, Equatable {
        /// The RFC822 Message-ID of this email
        public let messageId: String?
        /// The In-Reply-To header (parent message ID)
        public let inReplyTo: String?
        /// The References header (thread ancestry as message IDs)
        public let references: [String]

        public init(messageId: String?, inReplyTo: String?, references: [String]) {
            self.messageId = messageId
            self.inReplyTo = inReplyTo
            self.references = references
        }

        /// Whether this message appears to be a reply (has threading information)
        public var isReply: Bool {
            inReplyTo != nil || !references.isEmpty
        }

        /// Whether this message has valid threading headers
        public var hasThreadingHeaders: Bool {
            messageId != nil || isReply
        }
    }

    /// Parses and normalizes all threading headers from raw values.
    /// - Parameters:
    ///   - messageId: Raw Message-ID header
    ///   - inReplyTo: Raw In-Reply-To header
    ///   - references: Raw References header
    /// - Returns: Normalized threading headers
    public func parseThreadingHeaders(
        messageId: String?,
        inReplyTo: String?,
        references: String?
    ) -> ThreadingHeaders {
        let normalizedMessageId = normalizeMessageId(messageId)
        let normalizedInReplyTo = normalizeInReplyTo(inReplyTo)
        let parsedReferences = parseReferences(references)

        return ThreadingHeaders(
            messageId: normalizedMessageId,
            inReplyTo: normalizedInReplyTo,
            references: parsedReferences
        )
    }

    /// Parses threading headers from a ParsedEmlx object.
    /// - Parameter emlx: Parsed EMLX data
    /// - Returns: Normalized threading headers
    public func parseThreadingHeaders(from emlx: ParsedEmlx) -> ThreadingHeaders {
        // ParsedEmlx already has parsed references as an array
        // We just need to normalize the message ID and in-reply-to
        let normalizedMessageId = normalizeMessageId(emlx.messageId)
        let normalizedInReplyTo = normalizeInReplyTo(emlx.inReplyTo)

        // References are already parsed by EmlxParser
        return ThreadingHeaders(
            messageId: normalizedMessageId,
            inReplyTo: normalizedInReplyTo,
            references: emlx.references
        )
    }

    // MARK: - JSON Serialization

    /// Encodes an array of message IDs to JSON for database storage.
    /// - Parameter references: Array of message IDs
    /// - Returns: JSON string or nil if array is empty
    public func encodeReferencesToJson(_ references: [String]) -> String? {
        guard !references.isEmpty else { return nil }

        guard let data = try? JSONEncoder().encode(references),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        return json
    }

    /// Decodes an array of message IDs from JSON.
    /// - Parameter json: JSON string from database
    /// - Returns: Array of message IDs (empty if nil or invalid JSON)
    public func decodeReferencesFromJson(_ json: String?) -> [String] {
        guard let json = json, !json.isEmpty,
              let data = json.data(using: .utf8),
              let references = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return references
    }
}
