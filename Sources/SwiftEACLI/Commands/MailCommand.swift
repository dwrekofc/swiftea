import ArgumentParser
import SwiftEAKit

public struct Mail: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "mail",
        abstract: "Mail operations (sync, search, export, actions)",
        subcommands: [
            MailSync.self,
            MailSearch.self,
            MailExport.self
        ]
    )

    public init() {}
}

struct MailSync: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync mail data from Apple Mail"
    )

    @Flag(name: .long, help: "Watch for changes")
    var watch: Bool = false

    func run() throws {
        let vault = try VaultContext.require()
        print("Mail sync - not yet implemented")
        print("Using vault: \(vault.rootPath)")
        if watch {
            print("Watch mode requested")
        }
    }
}

struct MailSearch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search mail"
    )

    @Argument(help: "Search query")
    var query: String

    func run() throws {
        let vault = try VaultContext.require()
        print("Searching mail for: \(query)")
        print("Using vault: \(vault.rootPath)")
    }
}

struct MailExport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export mail"
    )

    @Option(name: .long, help: "Export format (markdown, json)")
    var format: String = "markdown"

    func run() throws {
        let vault = try VaultContext.require()
        print("Exporting mail to \(format)")
        print("Using vault: \(vault.rootPath)")
    }
}
