// MessageResolver - Resolves SwiftEA message IDs to Mail.app message references

import Foundation

// MARK: - Resolution Errors

/// Errors that can occur during message resolution
public enum MessageResolutionError: Error, LocalizedError {
    /// The message was not found in the SwiftEA database
    case notFoundInDatabase(id: String)

    /// The message was found but has no Message-ID for Mail.app resolution
    case noMessageIdAvailable(id: String)

    /// The message was not found in Mail.app (may have been deleted)
    case notFoundInMailApp(id: String, messageId: String?)

    /// Multiple messages matched the query (ambiguous resolution)
    case ambiguousMatch(id: String, count: Int)

    /// The message is from an unsupported account type (e.g., Exchange/EWS)
    case unsupportedAccountType(id: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .notFoundInDatabase(let id):
            return "Message '\(id)' not found in database. Run 'swea mail sync' to refresh."
        case .noMessageIdAvailable(let id):
            return "Message '\(id)' has no RFC822 Message-ID for Mail.app lookup."
        case .notFoundInMailApp(let id, let messageId):
            if let msgId = messageId {
                return "Message '\(id)' (Message-ID: \(msgId)) not found in Mail.app. It may have been deleted."
            }
            return "Message '\(id)' not found in Mail.app. It may have been deleted."
        case .ambiguousMatch(let id, let count):
            return "Message '\(id)' matched \(count) messages in Mail.app. Cannot proceed with ambiguous match."
        case .unsupportedAccountType(let id, let reason):
            return "Message '\(id)' cannot be resolved: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notFoundInDatabase:
            return "Run 'swea mail sync' to update the local database, then try again."
        case .noMessageIdAvailable:
            return "This message may be from an older sync. Try running 'swea mail sync' to update metadata."
        case .notFoundInMailApp:
            return "The message may have been deleted or moved. Run 'swea mail sync' to refresh the database."
        case .ambiguousMatch:
            return "Try using a more specific identifier or resolve manually in Mail.app."
        case .unsupportedAccountType:
            return "Some email account types (like Exchange) may not support all actions via AppleScript."
        }
    }
}

// MARK: - Resolved Message

/// A successfully resolved message reference for Mail.app operations
public struct ResolvedMessage: Sendable {
    /// The SwiftEA stable ID
    public let swiftEAId: String

    /// The RFC822 Message-ID for Mail.app lookup
    public let messageId: String

    /// The original message data from the database
    public let message: MailMessage

    /// Whether this resolution is confident (unique Message-ID match)
    public let isConfident: Bool

    public init(swiftEAId: String, messageId: String, message: MailMessage, isConfident: Bool = true) {
        self.swiftEAId = swiftEAId
        self.messageId = messageId
        self.message = message
        self.isConfident = isConfident
    }
}

// MARK: - Message Resolver

/// Resolves SwiftEA message IDs to Mail.app message references
///
/// Resolution strategy:
/// 1. Look up the message by SwiftEA ID in the local database
/// 2. Use the RFC822 Message-ID for Mail.app targeting (preferred)
/// 3. If no Message-ID available, fail with guidance
/// 4. Verify uniqueness before proceeding with actions
public final class MessageResolver: @unchecked Sendable {

    private let database: MailDatabase
    private let appleScriptService: AppleScriptService

    /// Create a message resolver
    /// - Parameters:
    ///   - database: The mail database to look up messages
    ///   - appleScriptService: The AppleScript service for Mail.app verification
    public init(database: MailDatabase, appleScriptService: AppleScriptService = .shared) {
        self.database = database
        self.appleScriptService = appleScriptService
    }

    // MARK: - Resolution

    /// Resolve a SwiftEA message ID to a Mail.app message reference
    ///
    /// - Parameter id: The SwiftEA stable message ID
    /// - Returns: A resolved message reference for Mail.app operations
    /// - Throws: `MessageResolutionError` if resolution fails
    public func resolve(id: String) throws -> ResolvedMessage {
        // Step 1: Look up in database
        guard let message = try database.getMessage(id: id) else {
            throw MessageResolutionError.notFoundInDatabase(id: id)
        }

        // Step 2: Check for Exchange/EWS messages (not supported via AppleScript)
        if let emlxPath = message.emlxPath, emlxPath.contains("ews:") {
            throw MessageResolutionError.unsupportedAccountType(
                id: id,
                reason: "Exchange (EWS) mailboxes cannot be modified via AppleScript."
            )
        }

        // Step 3: Get the RFC822 Message-ID
        guard let messageId = message.messageId, !messageId.isEmpty else {
            throw MessageResolutionError.noMessageIdAvailable(id: id)
        }

        // Step 4: Create resolved message
        return ResolvedMessage(
            swiftEAId: id,
            messageId: messageId,
            message: message,
            isConfident: true
        )
    }

    /// Resolve and verify a message exists in Mail.app
    ///
    /// This performs additional verification by querying Mail.app to ensure
    /// the message actually exists before performing an action.
    ///
    /// - Parameter id: The SwiftEA stable message ID
    /// - Returns: A verified resolved message reference
    /// - Throws: `MessageResolutionError` if resolution or verification fails
    public func resolveAndVerify(id: String) throws -> ResolvedMessage {
        // First, resolve from database
        let resolved = try resolve(id: id)

        // Then verify in Mail.app
        try verifyInMailApp(resolved)

        return resolved
    }

    /// Verify that a resolved message exists in Mail.app
    ///
    /// - Parameter resolved: The resolved message to verify
    /// - Throws: `MessageResolutionError` if verification fails
    public func verifyInMailApp(_ resolved: ResolvedMessage) throws {
        let script = """
            set matchCount to count of (every message whose message id is "\(escapeAppleScript(resolved.messageId))")
            return matchCount
            """

        do {
            let result = try appleScriptService.executeMailScript(script)

            guard let output = result.output,
                  let count = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw MessageResolutionError.notFoundInMailApp(
                    id: resolved.swiftEAId,
                    messageId: resolved.messageId
                )
            }

            if count == 0 {
                throw MessageResolutionError.notFoundInMailApp(
                    id: resolved.swiftEAId,
                    messageId: resolved.messageId
                )
            }

            if count > 1 {
                throw MessageResolutionError.ambiguousMatch(
                    id: resolved.swiftEAId,
                    count: count
                )
            }

            // count == 1, verification passed
        } catch let error as AppleScriptError {
            // Map AppleScript errors to resolution errors
            switch error {
            case .automationPermissionDenied:
                throw error // Re-throw permission errors
            case .mailAppNotResponding:
                throw error // Re-throw app errors
            default:
                throw MessageResolutionError.notFoundInMailApp(
                    id: resolved.swiftEAId,
                    messageId: resolved.messageId
                )
            }
        }
    }

    // MARK: - Batch Resolution

    /// Resolve multiple message IDs
    ///
    /// - Parameter ids: Array of SwiftEA message IDs
    /// - Returns: Dictionary mapping IDs to their resolution results
    public func resolveMultiple(ids: [String]) -> [String: Result<ResolvedMessage, MessageResolutionError>] {
        var results: [String: Result<ResolvedMessage, MessageResolutionError>] = [:]

        for id in ids {
            do {
                let resolved = try resolve(id: id)
                results[id] = .success(resolved)
            } catch let error as MessageResolutionError {
                results[id] = .failure(error)
            } catch {
                results[id] = .failure(.notFoundInDatabase(id: id))
            }
        }

        return results
    }

    // MARK: - Helpers

    /// Escape a string for safe use in AppleScript
    private func escapeAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - Message Resolution Result

/// Convenience wrapper for resolution results with action context
public struct MessageResolutionResult: Sendable {
    public let resolved: ResolvedMessage?
    public let error: MessageResolutionError?
    public let action: String

    public var succeeded: Bool { resolved != nil }

    public init(resolved: ResolvedMessage, action: String) {
        self.resolved = resolved
        self.error = nil
        self.action = action
    }

    public init(error: MessageResolutionError, action: String) {
        self.resolved = nil
        self.error = error
        self.action = action
    }

    /// Format the result for CLI output
    public func formatForOutput() -> String {
        if let resolved = resolved {
            return """
                Message resolved for \(action):
                  SwiftEA ID: \(resolved.swiftEAId)
                  Message-ID: \(resolved.messageId)
                  Subject: \(resolved.message.subject)
                """
        } else if let error = error {
            var output = "Failed to resolve message for \(action): \(error.localizedDescription)"
            if let suggestion = error.recoverySuggestion {
                output += "\n  Suggestion: \(suggestion)"
            }
            return output
        }
        return "Unknown resolution state"
    }
}
