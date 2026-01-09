import ArgumentParser
import Foundation
import SwiftEAKit

public struct Mail: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "mail",
        abstract: "Mail operations (sync, search, export, actions)",
        subcommands: [
            MailSyncCommand.self,
            MailSearchCommand.self,
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

struct MailExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export mail messages"
    )

    @Option(name: .long, help: "Export format (markdown, json)")
    var format: String = "markdown"

    @Option(name: .long, help: "Message ID to export (or 'all' for all messages)")
    var id: String = "all"

    func run() throws {
        let vault = try VaultContext.require()
        print("Export not yet implemented")
        print("Format: \(format), ID: \(id)")
        print("Using vault: \(vault.rootPath)")
    }
}
