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
            MailExportCommand.self,
            // Action commands
            MailArchiveCommand.self,
            MailDeleteCommand.self,
            MailMoveCommand.self,
            MailFlagCommand.self,
            MailMarkCommand.self,
            MailReplyCommand.self,
            MailComposeCommand.self
        ]
    )

    public init() {}
}

struct MailSyncCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync mail data from Apple Mail"
    )

    @Flag(name: .long, help: "Install and start watch daemon for continuous sync")
    var watch: Bool = false

    @Flag(name: .long, help: "Stop the watch daemon")
    var stop: Bool = false

    @Flag(name: .long, help: "Show sync status and watch daemon state")
    var status: Bool = false

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
        defer { mailDatabase.close() }

        if verbose {
            print("Mail database: \(mailDbPath)")
        }

        // Handle --status flag
        if status {
            try showSyncStatus(mailDatabase: mailDatabase, vault: vault)
            return
        }

        // Handle --watch flag
        if watch {
            try installWatchDaemon(vault: vault, verbose: verbose)
            return
        }

        // Handle --stop flag
        if stop {
            try stopWatchDaemon(verbose: verbose)
            return
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
    }

    // MARK: - Status

    private func showSyncStatus(mailDatabase: MailDatabase, vault: VaultContext) throws {
        let summary = try mailDatabase.getSyncStatusSummary()
        let daemonStatus = getDaemonStatus()

        print("Mail Sync Status")
        print("================")
        print("")

        // Daemon status
        print("Watch Daemon: \(daemonStatus.isRunning ? "running" : "stopped")")
        if let pid = daemonStatus.pid {
            print("  PID: \(pid)")
        }
        print("")

        // Sync state
        print("Last Sync:")
        print("  State: \(summary.state.rawValue)")

        if let lastSync = summary.lastSyncTime {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            print("  Time: \(formatter.string(from: lastSync))")
        } else {
            print("  Time: Never")
        }

        if let duration = summary.duration {
            print("  Duration: \(String(format: "%.2f", duration))s")
        }

        if let isIncremental = summary.isIncremental {
            print("  Type: \(isIncremental ? "incremental" : "full")")
        }

        // Message counts
        if summary.messagesAdded > 0 || summary.messagesUpdated > 0 || summary.messagesDeleted > 0 {
            print("  Messages: +\(summary.messagesAdded) ~\(summary.messagesUpdated) -\(summary.messagesDeleted)")
        }

        // Error if any
        if let error = summary.lastSyncError {
            print("")
            print("Last Error: \(error)")
        }

        // Database location
        print("")
        print("Database: \(vault.dataFolderPath)/mail.db")
    }

    private struct DaemonStatus {
        let isRunning: Bool
        let pid: Int?
    }

    private func getDaemonStatus() -> DaemonStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", "com.swiftea.mail.sync"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    // Parse PID from launchctl output (format: "PID\tStatus\tLabel")
                    let components = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t")
                    if components.count >= 1, let pid = Int(components[0]), pid > 0 {
                        return DaemonStatus(isRunning: true, pid: pid)
                    }
                    // Job exists but not running (PID is "-")
                    return DaemonStatus(isRunning: false, pid: nil)
                }
            }
        } catch {
            // launchctl failed, daemon not loaded
        }

        return DaemonStatus(isRunning: false, pid: nil)
    }

    // MARK: - Watch Daemon

    private static let launchAgentLabel = "com.swiftea.mail.sync"
    private static let syncIntervalSeconds = 300 // 5 minutes

    private func getLaunchAgentPath() -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDir)/Library/LaunchAgents/\(Self.launchAgentLabel).plist"
    }

    private func installWatchDaemon(vault: VaultContext, verbose: Bool) throws {
        let launchAgentPath = getLaunchAgentPath()
        let executablePath = ProcessInfo.processInfo.arguments[0]

        // Resolve to absolute path if needed
        let absoluteExecutablePath: String
        if executablePath.hasPrefix("/") {
            absoluteExecutablePath = executablePath
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            absoluteExecutablePath = (currentDir as NSString).appendingPathComponent(executablePath)
        }

        // Create LaunchAgents directory if needed
        let launchAgentsDir = (getLaunchAgentPath() as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: launchAgentsDir) {
            try FileManager.default.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
        }

        // Create log directory
        let logDir = "\(vault.dataFolderPath)/logs"
        if !FileManager.default.fileExists(atPath: logDir) {
            try FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        }

        // Generate plist content
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(Self.launchAgentLabel)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(absoluteExecutablePath)</string>
                    <string>mail</string>
                    <string>sync</string>
                    <string>--incremental</string>
                </array>
                <key>StartInterval</key>
                <integer>\(Self.syncIntervalSeconds)</integer>
                <key>RunAtLoad</key>
                <true/>
                <key>StandardOutPath</key>
                <string>\(logDir)/mail-sync.log</string>
                <key>StandardErrorPath</key>
                <string>\(logDir)/mail-sync.log</string>
                <key>WorkingDirectory</key>
                <string>\(vault.rootPath)</string>
                <key>EnvironmentVariables</key>
                <dict>
                    <key>PATH</key>
                    <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
                </dict>
            </dict>
            </plist>
            """

        // Write plist file
        try plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)

        if verbose {
            print("Created LaunchAgent: \(launchAgentPath)")
        }

        // Unload if already loaded (ignore errors)
        let unloadProcess = Process()
        unloadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        unloadProcess.arguments = ["unload", launchAgentPath]
        unloadProcess.standardOutput = FileHandle.nullDevice
        unloadProcess.standardError = FileHandle.nullDevice
        try? unloadProcess.run()
        unloadProcess.waitUntilExit()

        // Load the LaunchAgent
        let loadProcess = Process()
        loadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        loadProcess.arguments = ["load", launchAgentPath]

        let errorPipe = Pipe()
        loadProcess.standardError = errorPipe

        try loadProcess.run()
        loadProcess.waitUntilExit()

        if loadProcess.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            print("Failed to load LaunchAgent: \(errorOutput)")
            throw ExitCode.failure
        }

        print("Watch daemon installed and started")
        print("  Syncing every \(Self.syncIntervalSeconds / 60) minutes")
        print("  Logs: \(logDir)/mail-sync.log")
        print("")
        print("Use 'swiftea mail sync --status' to check status")
        print("Use 'swiftea mail sync --stop' to stop the daemon")
    }

    private func stopWatchDaemon(verbose: Bool) throws {
        let launchAgentPath = getLaunchAgentPath()

        // Check if plist exists
        guard FileManager.default.fileExists(atPath: launchAgentPath) else {
            print("Watch daemon is not installed")
            return
        }

        // Unload the LaunchAgent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", launchAgentPath]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            // Check if it was already unloaded
            if !errorOutput.contains("Could not find specified service") {
                print("Warning: \(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        // Remove the plist file
        try? FileManager.default.removeItem(atPath: launchAgentPath)

        if verbose {
            print("Removed LaunchAgent: \(launchAgentPath)")
        }

        print("Watch daemon stopped and uninstalled")
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
        // Flat filename using message ID for uniqueness and idempotent overwrites
        let ext = format.lowercased() == "json" ? "json" : "md"
        return "\(message.id).\(ext)"
    }

    private func formatAsMarkdown(_ message: MailMessage) -> String {
        var lines: [String] = []

        // Minimal YAML frontmatter: id, subject, from, date, aliases
        lines.append("---")
        lines.append("id: \"\(message.id)\"")
        lines.append("subject: \"\(escapeYaml(message.subject))\"")
        lines.append("from: \"\(escapeYaml(formatSender(message)))\"")
        if let date = message.dateSent {
            lines.append("date: \(date.iso8601String)")
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

// MARK: - Mail Action Commands

/// Error thrown when action validation fails
enum MailActionError: Error, LocalizedError {
    case messageNotFound(String)
    case mailboxRequired
    case confirmationRequired(action: String)
    case invalidFlagOperation
    case invalidMarkOperation

    var errorDescription: String? {
        switch self {
        case .messageNotFound(let id):
            return "Message not found: \(id)"
        case .mailboxRequired:
            return "Target mailbox is required. Use --mailbox to specify destination."
        case .confirmationRequired(let action):
            return "Destructive action '\(action)' requires --yes to confirm or --dry-run to preview."
        case .invalidFlagOperation:
            return "Specify either --set or --clear for flag operation."
        case .invalidMarkOperation:
            return "Specify either --read or --unread for mark operation."
        }
    }
}

struct MailArchiveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Archive a mail message",
        discussion: """
            Moves the specified message to the Archive mailbox in Mail.app.

            DESTRUCTIVE ACTION: This command modifies your mailbox.
            Use --dry-run to preview the action without making changes.
            Use --yes to confirm the action.
            """
    )

    @Option(name: .long, help: "Message ID to archive (required)")
    var id: String

    @Flag(name: .long, help: "Confirm the destructive action")
    var yes: Bool = false

    @Flag(name: .long, help: "Preview the action without making changes")
    var dryRun: Bool = false

    func validate() throws {
        // Validate that either --yes or --dry-run is provided
        if !yes && !dryRun {
            throw MailActionError.confirmationRequired(action: "archive")
        }
    }

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database to validate message exists
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        guard let message = try mailDatabase.getMessage(id: id) else {
            throw MailActionError.messageNotFound(id)
        }

        if dryRun {
            print("[DRY RUN] Would archive message:")
            print("  ID: \(message.id)")
            print("  Subject: \(message.subject)")
            print("  From: \(message.senderEmail ?? "Unknown")")
            print("  Current mailbox: \(message.mailboxName ?? "Unknown")")
            return
        }

        // TODO: Implement AppleScript execution (swiftea-01t.2)
        print("Archiving message: \(message.id)")
        print("  Subject: \(message.subject)")
        print("Action: Archive via AppleScript (not yet implemented)")
    }
}

struct MailDeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a mail message",
        discussion: """
            Moves the specified message to the Trash mailbox in Mail.app.

            DESTRUCTIVE ACTION: This command modifies your mailbox.
            Use --dry-run to preview the action without making changes.
            Use --yes to confirm the action.
            """
    )

    @Option(name: .long, help: "Message ID to delete (required)")
    var id: String

    @Flag(name: .long, help: "Confirm the destructive action")
    var yes: Bool = false

    @Flag(name: .long, help: "Preview the action without making changes")
    var dryRun: Bool = false

    func validate() throws {
        // Validate that either --yes or --dry-run is provided
        if !yes && !dryRun {
            throw MailActionError.confirmationRequired(action: "delete")
        }
    }

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database to validate message exists
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        guard let message = try mailDatabase.getMessage(id: id) else {
            throw MailActionError.messageNotFound(id)
        }

        if dryRun {
            print("[DRY RUN] Would delete message:")
            print("  ID: \(message.id)")
            print("  Subject: \(message.subject)")
            print("  From: \(message.senderEmail ?? "Unknown")")
            print("  Current mailbox: \(message.mailboxName ?? "Unknown")")
            return
        }

        // TODO: Implement AppleScript execution (swiftea-01t.2)
        print("Deleting message: \(message.id)")
        print("  Subject: \(message.subject)")
        print("Action: Delete via AppleScript (not yet implemented)")
    }
}

struct MailMoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Move a mail message to a different mailbox",
        discussion: """
            Moves the specified message to the target mailbox in Mail.app.

            DESTRUCTIVE ACTION: This command modifies your mailbox.
            Use --dry-run to preview the action without making changes.
            Use --yes to confirm the action.
            """
    )

    @Option(name: .long, help: "Message ID to move (required)")
    var id: String

    @Option(name: .long, help: "Target mailbox name (required)")
    var mailbox: String?

    @Flag(name: .long, help: "Confirm the destructive action")
    var yes: Bool = false

    @Flag(name: .long, help: "Preview the action without making changes")
    var dryRun: Bool = false

    func validate() throws {
        // Validate mailbox is provided
        guard mailbox != nil else {
            throw MailActionError.mailboxRequired
        }

        // Validate that either --yes or --dry-run is provided
        if !yes && !dryRun {
            throw MailActionError.confirmationRequired(action: "move")
        }
    }

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database to validate message exists
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        guard let message = try mailDatabase.getMessage(id: id) else {
            throw MailActionError.messageNotFound(id)
        }

        let targetMailbox = mailbox!

        if dryRun {
            print("[DRY RUN] Would move message:")
            print("  ID: \(message.id)")
            print("  Subject: \(message.subject)")
            print("  From: \(message.senderEmail ?? "Unknown")")
            print("  Current mailbox: \(message.mailboxName ?? "Unknown")")
            print("  Target mailbox: \(targetMailbox)")
            return
        }

        // TODO: Implement AppleScript execution (swiftea-01t.2)
        print("Moving message: \(message.id)")
        print("  Subject: \(message.subject)")
        print("  To mailbox: \(targetMailbox)")
        print("Action: Move via AppleScript (not yet implemented)")
    }
}

struct MailFlagCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flag",
        abstract: "Set or clear the flag on a mail message",
        discussion: """
            Sets or clears the flag (star) on the specified message in Mail.app.

            Use --set to flag the message.
            Use --clear to remove the flag.
            """
    )

    @Option(name: .long, help: "Message ID to flag/unflag (required)")
    var id: String

    @Flag(name: .long, help: "Set the flag on the message")
    var set: Bool = false

    @Flag(name: .long, help: "Clear the flag from the message")
    var clear: Bool = false

    func validate() throws {
        // Exactly one of --set or --clear must be provided
        if set == clear {
            throw MailActionError.invalidFlagOperation
        }
    }

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database to validate message exists
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        guard let message = try mailDatabase.getMessage(id: id) else {
            throw MailActionError.messageNotFound(id)
        }

        let action = set ? "Setting flag on" : "Clearing flag from"
        print("\(action) message: \(message.id)")
        print("  Subject: \(message.subject)")
        print("  Current flag status: \(message.isFlagged ? "flagged" : "not flagged")")

        // TODO: Implement AppleScript execution (swiftea-01t.2)
        print("Action: \(set ? "Set" : "Clear") flag via AppleScript (not yet implemented)")
    }
}

struct MailMarkCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mark",
        abstract: "Mark a mail message as read or unread",
        discussion: """
            Marks the specified message as read or unread in Mail.app.

            Use --read to mark the message as read.
            Use --unread to mark the message as unread.
            """
    )

    @Option(name: .long, help: "Message ID to mark (required)")
    var id: String

    @Flag(name: .long, help: "Mark the message as read")
    var read: Bool = false

    @Flag(name: .long, help: "Mark the message as unread")
    var unread: Bool = false

    func validate() throws {
        // Exactly one of --read or --unread must be provided
        if read == unread {
            throw MailActionError.invalidMarkOperation
        }
    }

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database to validate message exists
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        guard let message = try mailDatabase.getMessage(id: id) else {
            throw MailActionError.messageNotFound(id)
        }

        let action = read ? "Marking as read" : "Marking as unread"
        print("\(action): \(message.id)")
        print("  Subject: \(message.subject)")
        print("  Current status: \(message.isRead ? "read" : "unread")")

        // TODO: Implement AppleScript execution (swiftea-01t.2)
        print("Action: Mark \(read ? "read" : "unread") via AppleScript (not yet implemented)")
    }
}

struct MailReplyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reply",
        abstract: "Create a reply to a mail message",
        discussion: """
            Creates a reply draft for the specified message in Mail.app.

            By default, opens the reply in Mail.app for editing.
            Use --send to send the reply immediately (requires --body).

            The reply will be addressed to the original sender and include
            the original message as quoted text.
            """
    )

    @Option(name: .long, help: "Message ID to reply to (required)")
    var id: String

    @Option(name: .long, help: "Reply body text (required if using --send)")
    var body: String?

    @Flag(name: .long, help: "Reply to all recipients")
    var all: Bool = false

    @Flag(name: .long, help: "Send the reply immediately instead of opening a draft")
    var send: Bool = false

    func validate() throws {
        // If --send is specified, --body is required
        if send && body == nil {
            throw ValidationError("--body is required when using --send")
        }
    }

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database to validate message exists
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        guard let message = try mailDatabase.getMessage(id: id) else {
            throw MailActionError.messageNotFound(id)
        }

        let replyType = all ? "Reply All" : "Reply"
        print("Creating \(replyType.lowercased()) to message: \(message.id)")
        print("  Subject: \(message.subject)")
        print("  Original sender: \(message.senderEmail ?? "Unknown")")

        if let replyBody = body {
            print("  Reply body: \(replyBody.prefix(50))...")
        }

        if send {
            print("  Mode: Send immediately")
        } else {
            print("  Mode: Open draft in Mail.app")
        }

        // TODO: Implement AppleScript execution (swiftea-01t.2)
        print("Action: \(replyType) via AppleScript (not yet implemented)")
    }
}

struct MailComposeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compose",
        abstract: "Compose a new mail message",
        discussion: """
            Creates a new email draft in Mail.app.

            By default, opens the compose window in Mail.app for editing.
            Use --send to send the message immediately.
            """
    )

    @Option(name: .long, help: "Recipient email address (required)")
    var to: String

    @Option(name: .long, help: "Email subject (required)")
    var subject: String

    @Option(name: .long, help: "Email body text")
    var body: String?

    @Option(name: .long, help: "CC recipients (comma-separated)")
    var cc: String?

    @Option(name: .long, help: "BCC recipients (comma-separated)")
    var bcc: String?

    @Flag(name: .long, help: "Send the message immediately instead of opening a draft")
    var send: Bool = false

    func run() throws {
        _ = try VaultContext.require()

        print("Composing new message:")
        print("  To: \(to)")
        print("  Subject: \(subject)")

        if let ccRecipients = cc {
            print("  CC: \(ccRecipients)")
        }
        if let bccRecipients = bcc {
            print("  BCC: \(bccRecipients)")
        }
        if let messageBody = body {
            print("  Body: \(messageBody.prefix(50))...")
        }

        if send {
            print("  Mode: Send immediately")
        } else {
            print("  Mode: Open draft in Mail.app")
        }

        // TODO: Implement AppleScript execution (swiftea-01t.2)
        print("Action: Compose via AppleScript (not yet implemented)")
    }
}
