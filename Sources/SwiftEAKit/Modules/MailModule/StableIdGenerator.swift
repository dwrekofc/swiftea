// StableIdGenerator - Generate deterministic, stable IDs for emails

import Foundation
import CryptoKit

/// Generates stable, deterministic IDs for email messages
public struct StableIdGenerator: Sendable {

    public init() {}

    /// Generate a stable ID for an email message
    /// - Parameters:
    ///   - messageId: RFC822 Message-ID header (preferred)
    ///   - subject: Email subject
    ///   - sender: Sender email address
    ///   - date: Date sent or received
    ///   - appleRowId: Apple Mail row ID (fallback component)
    /// - Returns: A stable, deterministic hash-based ID
    public func generateId(
        messageId: String?,
        subject: String?,
        sender: String?,
        date: Date?,
        appleRowId: Int?
    ) -> String {
        // Prefer Message-ID if available (most stable)
        if let msgId = messageId, !msgId.isEmpty {
            return hashString("msgid:\(normalizeMessageId(msgId))")
        }

        // Fallback: create digest from headers
        var components: [String] = []

        if let subject = subject {
            components.append("subj:\(subject)")
        }
        if let sender = sender {
            components.append("from:\(sender.lowercased())")
        }
        if let date = date {
            // Use Unix timestamp for date component
            components.append("date:\(Int(date.timeIntervalSince1970))")
        }
        if let rowId = appleRowId {
            components.append("rowid:\(rowId)")
        }

        let digest = components.joined(separator: "|")

        // If we have enough components, hash them
        if components.count >= 2 {
            return hashString("hdr:\(digest)")
        }

        // Last resort: use Apple rowid alone (still stable within the mail store)
        if let rowId = appleRowId {
            return hashString("row:\(rowId)")
        }

        // Should not happen, but generate a UUID as absolute fallback
        return UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }

    /// Normalize a Message-ID for consistent hashing
    /// Removes angle brackets and normalizes whitespace
    private func normalizeMessageId(_ messageId: String) -> String {
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

    /// Generate a SHA-256 hash and return first 32 characters (128 bits)
    private func hashString(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        // Return first 32 characters for a reasonable ID length
        return String(hashString.prefix(32))
    }
}

/// Extension to validate stable IDs
extension StableIdGenerator {
    /// Check if a string looks like a valid stable ID
    public func isValidId(_ id: String) -> Bool {
        // Valid IDs are 32 lowercase hex characters
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
