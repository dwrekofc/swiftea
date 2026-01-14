import Foundation
import SwiftEAKit

// MARK: - Mail Command Utilities

/// Shared utility functions for mail commands.
/// These functions are extracted from duplicated code to ensure consistent behavior
/// and allow bugs to be fixed in one place.

// MARK: - HTML Processing

/// Strips HTML tags and entities from a string, converting it to plain text.
/// - Parameter html: The HTML string to strip
/// - Returns: Plain text with HTML tags removed and entities decoded
func stripHtml(_ html: String) -> String {
    var result = html
    // Remove script and style blocks
    result = result.replacingOccurrences(of: "<script[^>]*>.*?</script>", with: "", options: .regularExpression)
    result = result.replacingOccurrences(of: "<style[^>]*>.*?</style>", with: "", options: .regularExpression)
    // Replace common entities
    result = result.replacingOccurrences(of: "&nbsp;", with: " ")
    result = result.replacingOccurrences(of: "&amp;", with: "&")
    result = result.replacingOccurrences(of: "&lt;", with: "<")
    result = result.replacingOccurrences(of: "&gt;", with: ">")
    result = result.replacingOccurrences(of: "&quot;", with: "\"")
    // Replace <br> and </p> with newlines
    result = result.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
    result = result.replacingOccurrences(of: "</p>", with: "\n\n")
    // Remove all remaining tags
    result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    // Collapse multiple newlines
    result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Sender Formatting

/// Formats a mail message sender for display.
/// Returns "Name <email>" if both are available, otherwise just the name or email.
/// - Parameter message: The mail message containing sender information
/// - Returns: Formatted sender string, or "Unknown" if no sender information is available
func formatSender(_ message: MailMessage) -> String {
    if let name = message.senderName, let email = message.senderEmail {
        return "\(name) <\(email)>"
    } else if let email = message.senderEmail {
        return email
    } else if let name = message.senderName {
        return name
    }
    return "Unknown"
}

// MARK: - Retry Logic

/// Configuration for retry operations with exponential backoff.
struct RetryConfiguration {
    /// Maximum number of retry attempts
    let maxAttempts: Int

    /// Base delay in seconds for exponential backoff
    let baseDelay: TimeInterval

    /// Maximum delay in seconds between retries
    let maxDelay: TimeInterval

    /// Default configuration for mail sync operations
    static let `default` = RetryConfiguration(
        maxAttempts: 5,
        baseDelay: 2.0,
        maxDelay: 60.0
    )
}

/// Determines if an error is transient and worth retrying.
/// Transient errors include database locks, timeouts, and temporary failures.
/// - Parameter error: The error to check
/// - Returns: True if the error is transient and the operation should be retried
func isTransientError(_ error: Error) -> Bool {
    let description = error.localizedDescription.lowercased()
    // Database lock errors, network timeouts, permission issues that may be temporary
    return description.contains("locked") ||
           description.contains("busy") ||
           description.contains("timeout") ||
           description.contains("temporarily") ||
           description.contains("try again")
}

/// Executes an operation with exponential backoff retry for transient errors.
/// - Parameters:
///   - config: The retry configuration (defaults to standard mail sync settings)
///   - logger: Optional logging function for retry messages
///   - operation: The operation to execute
/// - Returns: The result of the operation if successful
/// - Throws: The last error if all retries are exhausted or a non-transient error occurs
@discardableResult
func withRetry<T>(
    config: RetryConfiguration = .default,
    logger: ((String) -> Void)? = nil,
    operation: () throws -> T
) throws -> T {
    var lastError: Error?
    var attempt = 0

    while attempt < config.maxAttempts {
        do {
            return try operation()
        } catch {
            lastError = error
            attempt += 1

            // Check if error is transient and worth retrying
            if isTransientError(error) && attempt < config.maxAttempts {
                // Calculate exponential backoff delay with jitter
                let delay = min(
                    config.baseDelay * pow(2.0, Double(attempt - 1)),
                    config.maxDelay
                )
                // Add 10-20% random jitter to prevent thundering herd
                let jitter = delay * Double.random(in: 0.1...0.2)
                let totalDelay = delay + jitter

                logger?("Transient error (attempt \(attempt)/\(config.maxAttempts)): \(error.localizedDescription)")
                logger?("Retrying in \(String(format: "%.1f", totalDelay)) seconds...")

                Thread.sleep(forTimeInterval: totalDelay)
            } else {
                // Non-transient error or max retries reached
                break
            }
        }
    }

    // All retries exhausted or non-transient error
    if let error = lastError {
        logger?("Operation failed after \(attempt) attempt(s): \(error.localizedDescription)")
        throw error
    }

    // This should never happen, but satisfy the compiler
    fatalError("withRetry ended without returning or throwing")
}

// MARK: - AppleScript Escaping

/// Escapes a string for safe use in AppleScript.
/// Handles backslashes and double quotes.
/// - Parameter string: The string to escape
/// - Returns: The escaped string safe for AppleScript inclusion
func escapeAppleScript(_ string: String) -> String {
    string
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

// MARK: - YAML Escaping

/// Escapes a string for safe use in YAML values.
/// - Parameter text: The text to escape
/// - Returns: The escaped string safe for YAML inclusion
func escapeYaml(_ text: String) -> String {
    text.replacingOccurrences(of: "\"", with: "\\\"")
}
