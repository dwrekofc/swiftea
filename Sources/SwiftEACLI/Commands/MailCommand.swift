import ArgumentParser
import Foundation
import SwiftEAKit

// MARK: - Date Extension for ISO 8601 formatting

extension Date {
    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: self)
    }
}

public struct Mail: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "mail",
        abstract: "Mail operations (sync, search, show, export, actions)",
        subcommands: [
            MailSyncCommand.self,
            MailSearchCommand.self,
            MailShowCommand.self,
            MailExportCommand.self
        ]
    )

    public init() {}
}

struct MailSyncCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync mail data from Apple Mail"
    )

    @Flag(name: .long, help: "Watch for changes (not yet implemented)")
    var watch: Bool = false

    @Flag(name: .long, help: "Only sync messages changed since last sync")
    var incremental: Bool = false

    @Flag(name: .long, help: "Show detailed progress")
    var verbose: Bool = false

    func run() throws {
        let vault = try VaultContext.require()

        // Create mail database in vault's data folder
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()

        if verbose {
            print("Mail database: \(mailDbPath)")
        }

        // Create sync engine
        let sync = MailSync(mailDatabase: mailDatabase)

        print("Syncing mail from Apple Mail...")

        do {
            let result = try sync.sync(incremental: incremental)

            print("Sync complete:")
            print("  Messages processed: \(result.messagesProcessed)")
            print("  Messages added: \(result.messagesAdded)")
            print("  Messages updated: \(result.messagesUpdated)")
            print("  Mailboxes: \(result.mailboxesProcessed)")
            print("  Duration: \(String(format: "%.2f", result.duration))s")

            if !result.errors.isEmpty {
                print("\nWarnings/Errors:")
                for error in result.errors.prefix(10) {
                    print("  - \(error)")
                }
                if result.errors.count > 10 {
                    print("  ... and \(result.errors.count - 10) more")
                }
            }
        } catch let error as MailSyncError {
            print("Sync failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        if watch {
            print("\nWatch mode not yet implemented")
        }
    }
}

struct MailSearchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search mail using full-text search"
    )

    @Argument(help: "Search query")
    var query: String

    @Option(name: .long, help: "Maximum results to return")
    var limit: Int = 20

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()

        let results = try mailDatabase.searchMessages(query: query, limit: limit)

        if results.isEmpty {
            print("No messages found for: \(query)")
            return
        }

        if json {
            // Output as JSON
            var output: [[String: Any]] = []
            for msg in results {
                output.append([
                    "id": msg.id,
                    "subject": msg.subject,
                    "sender": msg.senderEmail ?? "",
                    "date": msg.dateSent?.description ?? "",
                    "mailbox": msg.mailboxName ?? ""
                ])
            }
            if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
               let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            print("Found \(results.count) message(s):\n")
            for msg in results {
                let date = msg.dateSent.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "Unknown"
                let sender = msg.senderName ?? msg.senderEmail ?? "Unknown"
                print("[\(msg.id)]")
                print("  Subject: \(msg.subject)")
                print("  From: \(sender)")
                print("  Date: \(date)")
                print("  Mailbox: \(msg.mailboxName ?? "Unknown")")
                print("")
            }
        }
    }
}

struct MailShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Display a single email message"
    )

    @Argument(help: "Message ID to display")
    var id: String

    @Flag(name: .long, help: "Show HTML body instead of plain text")
    var html: Bool = false

    @Flag(name: .long, help: "Show raw .emlx content")
    var raw: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        guard let message = try mailDatabase.getMessage(id: id) else {
            print("Message not found: \(id)")
            throw ExitCode.failure
        }

        // Handle --raw flag: read original .emlx file
        if raw {
            guard let emlxPath = message.emlxPath else {
                print("No .emlx path available for this message")
                throw ExitCode.failure
            }
            guard let content = try? String(contentsOfFile: emlxPath, encoding: .utf8) else {
                print("Could not read .emlx file: \(emlxPath)")
                throw ExitCode.failure
            }
            print(content)
            return
        }

        // Handle --json flag
        if json {
            let output: [String: Any] = [
                "id": message.id,
                "messageId": message.messageId ?? "",
                "subject": message.subject,
                "from": formatSender(message),
                "date": message.dateSent?.iso8601String ?? "",
                "mailbox": message.mailboxName ?? "",
                "isRead": message.isRead,
                "isFlagged": message.isFlagged,
                "hasAttachments": message.hasAttachments,
                "body": html ? (message.bodyHtml ?? "") : (message.bodyText ?? "")
            ]
            if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
               let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
            return
        }

        // Default: formatted text output
        let date = message.dateSent.map { DateFormatter.localizedString(from: $0, dateStyle: .long, timeStyle: .long) } ?? "Unknown"
        let sender = formatSender(message)

        print("Subject: \(message.subject)")
        print("From: \(sender)")
        print("Date: \(date)")
        print("Mailbox: \(message.mailboxName ?? "Unknown")")
        if message.hasAttachments {
            print("Attachments: Yes")
        }
        print("")
        print(String(repeating: "-", count: 60))
        print("")

        // Show body content
        if html {
            if let htmlBody = message.bodyHtml {
                print(htmlBody)
            } else {
                print("(No HTML body available)")
            }
        } else {
            if let textBody = message.bodyText {
                print(textBody)
            } else if let htmlBody = message.bodyHtml {
                // Fallback: strip HTML tags for plain text display
                print(stripHtml(htmlBody))
            } else {
                print("(No message body available)")
            }
        }
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

    private func stripHtml(_ html: String) -> String {
        // Simple HTML tag stripping
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
}

struct MailExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export mail messages to markdown or JSON"
    )

    @Option(name: .long, help: "Export format (markdown, json)")
    var format: String = "markdown"

    @Option(name: .long, help: "Message ID to export (or 'all' for all synced messages)")
    var id: String = "all"

    @Option(name: .shortAndLong, help: "Output directory (default: vault exports folder)")
    var output: String?

    @Option(name: .long, help: "Search query to filter messages for export")
    var query: String?

    @Option(name: .long, help: "Maximum messages to export (default: 100)")
    var limit: Int = 100

    func run() throws {
        let vault = try VaultContext.require()

        // Determine output directory
        let outputDir: String
        if let specifiedOutput = output {
            outputDir = specifiedOutput
        } else {
            outputDir = (vault.rootPath as NSString).appendingPathComponent("exports/mail")
        }

        // Create output directory if needed
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: outputDir) {
            try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        }

        // Open mail database
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        // Get messages to export
        var messages: [MailMessage] = []

        if id != "all" {
            // Export single message
            if let message = try mailDatabase.getMessage(id: id) {
                messages = [message]
            } else {
                print("Message not found: \(id)")
                throw ExitCode.failure
            }
        } else if let searchQuery = query {
            // Export messages matching query
            messages = try mailDatabase.searchMessages(query: searchQuery, limit: limit)
        } else {
            // Export all messages (up to limit) - use a broad search
            messages = try mailDatabase.searchMessages(query: "*", limit: limit)
        }

        if messages.isEmpty {
            print("No messages to export")
            return
        }

        print("Exporting \(messages.count) message(s) to \(outputDir)...")

        var exportedCount = 0
        for message in messages {
            let filename = generateFilename(for: message, format: format)
            let filePath = (outputDir as NSString).appendingPathComponent(filename)

            let content: String
            switch format.lowercased() {
            case "json":
                content = formatAsJson(message)
            case "markdown", "md":
                content = formatAsMarkdown(message)
            default:
                print("Unknown format: \(format). Use 'markdown' or 'json'.")
                throw ExitCode.failure
            }

            try content.write(toFile: filePath, atomically: true, encoding: .utf8)

            // Update export path in database
            try mailDatabase.updateExportPath(id: message.id, path: filePath)
            exportedCount += 1
        }

        print("Exported \(exportedCount) message(s) to \(outputDir)")
    }

    private func generateFilename(for message: MailMessage, format: String) -> String {
        // Format: YYYY-MM-DD-subject-slug.ext
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let datePrefix = message.dateSent.map { dateFormatter.string(from: $0) } ?? "unknown-date"

        let slug = slugify(message.subject)
        let ext = format.lowercased() == "json" ? "json" : "md"

        // Include message ID prefix to ensure uniqueness
        let shortId = String(message.id.prefix(8))
        return "\(datePrefix)-\(shortId)-\(slug).\(ext)"
    }

    private func slugify(_ text: String) -> String {
        var slug = text.lowercased()
        // Replace non-alphanumeric with hyphens
        slug = slug.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        // Remove leading/trailing hyphens
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        // Limit length
        if slug.count > 50 {
            slug = String(slug.prefix(50))
            // Don't end with hyphen
            slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        return slug.isEmpty ? "untitled" : slug
    }

    private func formatAsMarkdown(_ message: MailMessage) -> String {
        var lines: [String] = []

        // YAML frontmatter
        lines.append("---")
        lines.append("subject: \"\(escapeYaml(message.subject))\"")
        lines.append("from: \"\(escapeYaml(formatSender(message)))\"")
        if let date = message.dateSent {
            lines.append("date: \(date.iso8601String)")
        }
        if let messageId = message.messageId {
            lines.append("message_id: \"\(escapeYaml(messageId))\"")
        }
        if let mailbox = message.mailboxName {
            lines.append("mailbox: \"\(escapeYaml(mailbox))\"")
        }
        lines.append("is_read: \(message.isRead)")
        lines.append("is_flagged: \(message.isFlagged)")
        lines.append("has_attachments: \(message.hasAttachments)")
        lines.append("swiftea_id: \"\(message.id)\"")
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

    private func formatAsJson(_ message: MailMessage) -> String {
        let output: [String: Any] = [
            "id": message.id,
            "messageId": message.messageId ?? "",
            "subject": message.subject,
            "from": [
                "name": message.senderName ?? "",
                "email": message.senderEmail ?? ""
            ],
            "date": message.dateSent?.iso8601String ?? "",
            "mailbox": message.mailboxName ?? "",
            "isRead": message.isRead,
            "isFlagged": message.isFlagged,
            "hasAttachments": message.hasAttachments,
            "bodyText": message.bodyText ?? "",
            "bodyHtml": message.bodyHtml ?? ""
        ]

        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return "{}"
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
