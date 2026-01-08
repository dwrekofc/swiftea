import ArgumentParser
import SwiftEACLI

@main
struct SwiftEA: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftea",
        abstract: "Swift Executive Assistant - Unified CLI for macOS PIM data",
        version: "0.1.0",
        subcommands: [
            Mail.self,
            Cal.self,
            Contacts.self,
            Sync.self,
            Search.self,
            Export.self,
            Config.self,
            Status.self,
            Vault.self
        ]
    )
}
