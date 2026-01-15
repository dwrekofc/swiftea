// AppleScriptService - OSAKit wrapper for Mail.app automation with error mapping

import Foundation

// MARK: - AppleScript Errors

/// Errors that can occur when executing AppleScript for Mail operations
public enum AppleScriptError: Error, LocalizedError {
    /// The Automation permission for Mail.app is not granted
    case automationPermissionDenied(guidance: String)

    /// Mail.app is not running or not responding
    case mailAppNotResponding(underlying: String)

    /// The specified message could not be found in Mail.app
    case messageNotFound(messageId: String)

    /// Multiple messages matched the query (ambiguous resolution)
    case messageResolutionAmbiguous(count: Int, suggestion: String)

    /// The specified mailbox was not found
    case mailboxNotFound(mailbox: String)

    /// The AppleScript failed to compile
    case scriptCompilationFailed(details: String)

    /// The AppleScript execution failed with an error
    case executionFailed(code: Int, message: String)

    /// An unexpected error occurred
    case unexpected(underlying: Error)

    /// Mail.app failed to launch within the timeout period
    case mailLaunchTimeout(seconds: Int)

    public var errorDescription: String? {
        switch self {
        case .automationPermissionDenied(let guidance):
            return """
                Automation permission denied for Mail.app.

                \(guidance)
                """
        case .mailAppNotResponding(let underlying):
            return "Mail.app is not running or not responding: \(underlying)"
        case .messageNotFound(let messageId):
            return "Message not found in Mail.app: \(messageId)"
        case .messageResolutionAmbiguous(let count, let suggestion):
            return "Found \(count) messages matching the query. \(suggestion)"
        case .mailboxNotFound(let mailbox):
            return "Mailbox not found: \(mailbox)"
        case .scriptCompilationFailed(let details):
            return "AppleScript compilation failed: \(details)"
        case .executionFailed(let code, let message):
            return "AppleScript execution failed (error \(code)): \(message)"
        case .unexpected(let underlying):
            return "Unexpected error: \(underlying.localizedDescription)"
        case .mailLaunchTimeout(let seconds):
            return "Mail.app failed to launch within \(seconds) seconds"
        }
    }

    /// Provides guidance for resolving the error
    public var recoveryGuidance: String? {
        switch self {
        case .automationPermissionDenied:
            return """
                To grant permission:
                1. Open System Settings > Privacy & Security > Automation
                2. Find swea (or Terminal if running from terminal)
                3. Enable the toggle for Mail.app
                4. If not listed, try running the command again to trigger the permission prompt
                """
        case .mailAppNotResponding:
            return "Try opening Mail.app manually or check if it's blocked by a dialog."
        case .messageNotFound:
            return "The message may have been deleted or moved. Run 'swea mail sync' to refresh."
        case .messageResolutionAmbiguous:
            return "Try using --message-id with the RFC822 Message-ID for exact matching."
        case .mailboxNotFound:
            return "Check mailbox name with 'swea mail mailboxes' (if available) or use the full path."
        case .mailLaunchTimeout:
            return "Try launching Mail.app manually or check if macOS is prompting for permissions."
        default:
            return nil
        }
    }
}

// MARK: - Execution Result

/// Result of an AppleScript execution
public struct AppleScriptResult {
    /// Whether the script executed successfully
    public let success: Bool

    /// The output from the script (if any)
    public let output: String?

    /// Create a successful result
    public static func success(_ output: String? = nil) -> AppleScriptResult {
        AppleScriptResult(success: true, output: output)
    }
}

// MARK: - AppleScript Service

/// Service for executing AppleScript commands targeting Mail.app
///
/// This service provides a unified interface for running AppleScript with:
/// - Structured error handling with actionable messages
/// - Automation permission detection and guidance
/// - Mail.app specific error mapping
public final class AppleScriptService: Sendable {

    /// Shared instance for convenience (stateless, so sharing is safe)
    public static let shared = AppleScriptService()

    public init() {}

    // MARK: - Public API

    /// Execute an AppleScript and return the result
    ///
    /// - Parameter script: The AppleScript source code to execute
    /// - Returns: The result of the script execution
    /// - Throws: `AppleScriptError` if execution fails
    public func execute(_ script: String) throws -> AppleScriptResult {
        var error: NSDictionary?

        guard let appleScript = NSAppleScript(source: script) else {
            throw AppleScriptError.scriptCompilationFailed(details: "Failed to create NSAppleScript instance")
        }

        let result = appleScript.executeAndReturnError(&error)

        if let error = error {
            throw mapAppleScriptError(error)
        }

        // Extract string output, handling list results
        let output = extractStringOutput(from: result)
        return .success(output)
    }

    /// Execute an AppleScript targeting Mail.app
    ///
    /// This is a convenience wrapper that wraps the script in a Mail.app tell block
    /// and provides better error context for Mail-specific operations.
    ///
    /// - Parameter mailScript: The script to run inside `tell application "Mail"`
    /// - Returns: The result of the script execution
    /// - Throws: `AppleScriptError` if execution fails
    public func executeMailScript(_ mailScript: String) throws -> AppleScriptResult {
        let fullScript = """
            tell application "Mail"
                \(mailScript)
            end tell
            """

        do {
            return try execute(fullScript)
        } catch let error as AppleScriptError {
            // Re-throw with additional Mail context if needed
            throw error
        } catch {
            throw AppleScriptError.unexpected(underlying: error)
        }
    }

    /// Check if Mail.app automation permission is granted
    ///
    /// Attempts a minimal AppleScript operation to verify permission.
    /// - Returns: `true` if permission is granted
    public func checkMailPermission() -> Bool {
        do {
            // Try to get account count - minimal operation that requires permission
            _ = try executeMailScript("return count of accounts")
            return true
        } catch {
            return false
        }
    }

    /// Default timeout for waiting for Mail.app to launch (in seconds)
    public static let defaultMailLaunchTimeout: Int = 10

    /// Default polling interval when waiting for Mail.app to launch (in microseconds)
    public static let defaultMailPollIntervalMicroseconds: UInt32 = 100_000  // 100ms

    /// Ensure Mail.app is running
    ///
    /// Launches Mail.app if it's not running and waits for it to be ready.
    /// Uses polling instead of a fixed delay for optimal performance:
    /// - If Mail is already running, returns immediately (no delay)
    /// - If Mail needs to launch, polls every 100ms until ready or timeout
    ///
    /// - Parameter timeout: Maximum seconds to wait for Mail.app to launch (default: 10)
    /// - Throws: `AppleScriptError.mailLaunchTimeout` if Mail.app doesn't start within timeout
    /// - Throws: `AppleScriptError` if Mail.app cannot be launched
    public func ensureMailRunning(timeout: Int = AppleScriptService.defaultMailLaunchTimeout) throws {
        // First, check if Mail is already running (fast path)
        let checkRunningScript = """
            tell application "Mail"
                return running
            end tell
            """

        let initialCheck = try execute(checkRunningScript)
        if initialCheck.output?.lowercased() == "true" {
            // Mail is already running, return immediately
            return
        }

        // Mail is not running, launch it
        let launchScript = """
            tell application "Mail"
                launch
            end tell
            """
        _ = try execute(launchScript)

        // Poll until Mail.app is running or timeout
        let startTime = Date()
        let timeoutInterval = TimeInterval(timeout)

        while Date().timeIntervalSince(startTime) < timeoutInterval {
            let checkResult = try execute(checkRunningScript)
            if checkResult.output?.lowercased() == "true" {
                // Mail is now running
                return
            }

            // Wait before next poll (100ms)
            usleep(Self.defaultMailPollIntervalMicroseconds)
        }

        // Timeout reached
        throw AppleScriptError.mailLaunchTimeout(seconds: timeout)
    }

    // MARK: - Error Mapping

    /// Map NSAppleScript error dictionary to structured AppleScriptError
    private func mapAppleScriptError(_ error: NSDictionary) -> AppleScriptError {
        let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? -1
        let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
        let errorBrief = error[NSAppleScript.errorBriefMessage] as? String

        // Automation permission denied
        // Error -1743: "Not authorized to send Apple events to Mail."
        // Error -600: "Application isn't running." (sometimes indicates permission issue)
        if errorNumber == -1743 || errorMessage.lowercased().contains("not authorized") {
            return .automationPermissionDenied(guidance: """
                swea needs permission to control Mail.app.

                Grant access in System Settings > Privacy & Security > Automation.
                """)
        }

        // Application not running or not responding
        // Error -600: "Application isn't running."
        // Error -609: "Connection is invalid."
        // Error -903: "No user interaction allowed." (can happen with non-GUI context)
        if errorNumber == -600 || errorNumber == -609 || errorNumber == -903 {
            return .mailAppNotResponding(underlying: errorBrief ?? errorMessage)
        }

        // Message or object not found
        // Error -1728: "Can't get [object]." (object doesn't exist)
        // Error -1719: "Can't get [item] of [container]."
        if errorNumber == -1728 || errorNumber == -1719 {
            if errorMessage.lowercased().contains("message") {
                // Extract message ID from error if possible
                return .messageNotFound(messageId: "unknown")
            }
            if errorMessage.lowercased().contains("mailbox") {
                // Extract mailbox name from error if possible
                let mailboxName = extractQuotedValue(from: errorMessage) ?? "unknown"
                return .mailboxNotFound(mailbox: mailboxName)
            }
        }

        // Compilation errors
        // Error -2740: Syntax error
        // Error -2741: Semantic error
        if errorNumber == -2740 || errorNumber == -2741 {
            return .scriptCompilationFailed(details: errorMessage)
        }

        // Default: execution failed with generic error
        return .executionFailed(code: errorNumber, message: errorMessage)
    }

    /// Extract a quoted value from an error message (e.g., "Can't get mailbox \"INBOX\"")
    private func extractQuotedValue(from message: String) -> String? {
        let pattern = "\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: message, options: [], range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range(at: 1), in: message) else {
            return nil
        }
        return String(message[range])
    }

    /// Extract string output from NSAppleEventDescriptor
    private func extractStringOutput(from descriptor: NSAppleEventDescriptor) -> String? {
        // Handle list results
        if descriptor.numberOfItems > 0 {
            var items: [String] = []
            for i in 1...descriptor.numberOfItems {
                if let item = descriptor.atIndex(i)?.stringValue {
                    items.append(item)
                }
            }
            return items.isEmpty ? nil : items.joined(separator: "\n")
        }

        // Handle simple values
        return descriptor.stringValue
    }
}

// MARK: - Mail Action Scripts

/// Pre-built AppleScript templates for common Mail.app actions
public struct MailActionScripts {

    // MARK: - Private Helpers

    /// Generate the AppleScript fragment for resolving a message by its Message-ID.
    ///
    /// This helper consolidates the common boilerplate for finding a message and
    /// validating that exactly one match exists. It sets `theMessage` variable to
    /// the resolved message.
    ///
    /// - Parameter messageId: The RFC822 Message-ID to search for
    /// - Returns: AppleScript fragment that sets `theMessage` to the found message
    ///
    /// Generated script pattern:
    /// ```applescript
    /// set targetMessages to (every message whose message id is "<messageId>")
    /// if (count of targetMessages) = 0 then
    ///     error "Message not found: <messageId>" number -1728
    /// end if
    /// if (count of targetMessages) > 1 then
    ///     error "Multiple messages found with Message-ID" number -1
    /// end if
    /// set theMessage to item 1 of targetMessages
    /// ```
    private static func messageResolutionScript(messageId: String) -> String {
        """
        set targetMessages to (every message whose message id is "\(escapeAppleScriptString(messageId))")
        if (count of targetMessages) = 0 then
            error "Message not found: \(escapeAppleScriptString(messageId))" number -1728
        end if
        if (count of targetMessages) > 1 then
            error "Multiple messages found with Message-ID" number -1
        end if
        set theMessage to item 1 of targetMessages
        """
    }

    // MARK: - Public API

    /// Generate script to delete a message by Message-ID
    public static func deleteMessage(byMessageId messageId: String) -> String {
        """
        \(messageResolutionScript(messageId: messageId))
        delete theMessage
        return "deleted"
        """
    }

    /// Generate script to move a message to a mailbox by Message-ID
    public static func moveMessage(byMessageId messageId: String, toMailbox mailbox: String, inAccount account: String? = nil) -> String {
        let mailboxRef: String
        if let account = account {
            mailboxRef = "mailbox \"\(escapeAppleScriptString(mailbox))\" of account \"\(escapeAppleScriptString(account))\""
        } else {
            mailboxRef = "mailbox \"\(escapeAppleScriptString(mailbox))\""
        }

        return """
        \(messageResolutionScript(messageId: messageId))
        set targetMailbox to \(mailboxRef)
        move theMessage to targetMailbox
        return "moved"
        """
    }

    /// Generate script to set flag status on a message
    public static func setFlag(byMessageId messageId: String, flagged: Bool) -> String {
        """
        \(messageResolutionScript(messageId: messageId))
        set flagged status of theMessage to \(flagged)
        return "\(flagged ? "flagged" : "unflagged")"
        """
    }

    /// Generate script to set read status on a message
    public static func setReadStatus(byMessageId messageId: String, read: Bool) -> String {
        """
        \(messageResolutionScript(messageId: messageId))
        set read status of theMessage to \(read)
        return "\(read ? "read" : "unread")"
        """
    }

    /// Generate script to create a reply to a message
    public static func createReply(byMessageId messageId: String, replyToAll: Bool, body: String?, send: Bool) -> String {
        let replyType = replyToAll ? "reply to all" : "reply to"
        let bodyClause = body.map { "set content of theReply to \"\(escapeAppleScriptString($0))\"" } ?? ""
        let sendClause = send ? "send theReply" : "open theReply"

        return """
        \(messageResolutionScript(messageId: messageId))
        set theReply to \(replyType) theMessage
        \(bodyClause)
        \(sendClause)
        return "\(send ? "sent" : "opened")"
        """
    }

    /// Generate script to compose a new message
    public static func compose(
        to: String,
        subject: String,
        body: String?,
        cc: String?,
        bcc: String?,
        send: Bool
    ) -> String {
        var makeClause = "make new outgoing message with properties {"
        makeClause += "subject:\"\(escapeAppleScriptString(subject))\""
        if let body = body {
            makeClause += ", content:\"\(escapeAppleScriptString(body))\""
        }
        makeClause += ", visible:true}"

        var recipientClauses: [String] = []

        // Add To recipients
        for recipient in to.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            recipientClauses.append("make new to recipient at end of to recipients with properties {address:\"\(escapeAppleScriptString(recipient))\"}")
        }

        // Add CC recipients
        if let cc = cc {
            for recipient in cc.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                recipientClauses.append("make new cc recipient at end of cc recipients with properties {address:\"\(escapeAppleScriptString(recipient))\"}")
            }
        }

        // Add BCC recipients
        if let bcc = bcc {
            for recipient in bcc.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                recipientClauses.append("make new bcc recipient at end of bcc recipients with properties {address:\"\(escapeAppleScriptString(recipient))\"}")
            }
        }

        let sendClause = send ? "send theMessage" : ""

        return """
        set theMessage to \(makeClause)
        tell theMessage
            \(recipientClauses.joined(separator: "\n            "))
        end tell
        \(sendClause)
        return "\(send ? "sent" : "opened")"
        """
    }

    /// Escape a string for safe use in AppleScript
    private static func escapeAppleScriptString(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
