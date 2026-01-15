// MailExporter - Export mail messages to markdown files
//
// Provides auto-export functionality after mail sync, exporting
// new messages to Swiftea/Mail/ as markdown files with YAML frontmatter.

import Foundation

/// Result of an export operation
public struct MailExportResult: Sendable {
    public let exported: Int
    public let skipped: Int
    public let errors: [String]

    public init(exported: Int, skipped: Int, errors: [String]) {
        self.exported = exported
        self.skipped = skipped
        self.errors = errors
    }
}

/// Exports mail messages to markdown files
public final class MailExporter {
    private let mailDatabase: MailDatabase
    private let fileManager: FileManager

    public init(mailDatabase: MailDatabase, fileManager: FileManager = .default) {
        self.mailDatabase = mailDatabase
        self.fileManager = fileManager
    }

    /// Export messages that haven't been exported yet to the specified directory
    /// - Parameters:
    ///   - outputDir: Directory to export files to (e.g., Swiftea/Mail/)
    ///   - limit: Maximum messages to export (0 = unlimited)
    /// - Returns: Export result with counts and any errors
    public func exportNewMessages(to outputDir: String, limit: Int = 0) throws -> MailExportResult {
        // Create output directory if needed
        if !fileManager.fileExists(atPath: outputDir) {
            try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        }

        // Get messages that need to be exported
        let messages = try mailDatabase.getMessagesNeedingExport(limit: limit)

        if messages.isEmpty {
            return MailExportResult(exported: 0, skipped: 0, errors: [])
        }

        var exported = 0
        var skipped = 0
        var errors: [String] = []

        for message in messages {
            do {
                let filePath = try exportMessage(message, to: outputDir)
                try mailDatabase.updateExportPath(id: message.id, path: filePath)
                exported += 1
            } catch {
                errors.append("Failed to export \(message.id): \(error.localizedDescription)")
                skipped += 1
            }
        }

        return MailExportResult(exported: exported, skipped: skipped, errors: errors)
    }

    /// Export a single message to a markdown file
    /// - Parameters:
    ///   - message: The message to export
    ///   - outputDir: Directory to export to
    /// - Returns: The full path of the exported file
    @discardableResult
    public func exportMessage(_ message: MailMessage, to outputDir: String) throws -> String {
        let filename = "\(message.id).md"
        let filePath = (outputDir as NSString).appendingPathComponent(filename)

        let content = formatAsMarkdown(message)
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)

        return filePath
    }

    // MARK: - Thread Metadata

    /// Get thread metadata for a message including position in thread
    private func getThreadMetadata(for message: MailMessage) -> (thread: Thread, position: Int, total: Int)? {
        guard let threadId = message.threadId else {
            return nil
        }

        do {
            guard let thread = try mailDatabase.getThread(id: threadId) else {
                return nil
            }

            // Get all messages in the thread to calculate position
            let messages = try mailDatabase.getMessagesInThreadViaJunction(threadId: threadId, limit: 10000)
            let sortedMessages = messages.sorted { (m1, m2) -> Bool in
                guard let d1 = m1.dateSent, let d2 = m2.dateSent else {
                    return m1.dateSent != nil
                }
                return d1 < d2
            }

            // Find position of current message (1-indexed)
            let position = (sortedMessages.firstIndex(where: { $0.id == message.id }) ?? 0) + 1
            let total = sortedMessages.count

            return (thread, position, total)
        } catch {
            return nil
        }
    }

    // MARK: - Markdown Formatting

    private func formatAsMarkdown(_ message: MailMessage) -> String {
        var lines: [String] = []

        // Get thread metadata if available
        let threadMeta = getThreadMetadata(for: message)

        // Minimal YAML frontmatter: id, subject, from, date, aliases, thread info
        lines.append("---")
        lines.append("id: \"\(message.id)\"")
        lines.append("subject: \"\(escapeYaml(message.subject))\"")
        lines.append("from: \"\(escapeYaml(formatSender(message)))\"")
        if let date = message.dateSent {
            lines.append("date: \(iso8601String(from: date))")
        }
        if let mailbox = message.mailboxName {
            lines.append("mailbox: \"\(escapeYaml(mailbox))\"")
        }

        // Thread metadata
        if let (thread, position, total) = threadMeta {
            lines.append("thread_id: \"\(escapeYaml(thread.id))\"")
            lines.append("thread_position: \"Message \(position) of \(total)\"")
            if let threadSubject = thread.subject {
                lines.append("thread_subject: \"\(escapeYaml(threadSubject))\"")
            }
        }

        // aliases: use subject as an alias for linking by topic
        lines.append("aliases:")
        lines.append("  - \"\(escapeYaml(message.subject))\"")
        lines.append("---")
        lines.append("")

        // Subject as heading
        lines.append("# \(message.subject)")
        lines.append("")

        // Body content
        if let textBody = message.bodyText, !textBody.isEmpty {
            lines.append(textBody)
        } else if let htmlBody = message.bodyHtml {
            // Fall back to stripped HTML
            lines.append(stripHtml(htmlBody))
        } else {
            lines.append("*(No message body)*")
        }

        return lines.joined(separator: "\n")
    }

    private func formatSender(_ message: MailMessage) -> String {
        if let name = message.senderName, let email = message.senderEmail {
            return "\(name) <\(email)>"
        } else if let email = message.senderEmail {
            return email
        } else if let name = message.senderName {
            return name
        }
        return "Unknown"
    }

    private func escapeYaml(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func stripHtml(_ html: String) -> String {
        var result = html
        result = result.replacingOccurrences(of: "<script[^>]*>.*?</script>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "<style[^>]*>.*?</style>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</p>", with: "\n\n")
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
