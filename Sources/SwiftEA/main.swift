import ArgumentParser
import SwiftEACLI

@main
struct SwiftEA: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swea",
        abstract: "Swift Executive Assistant - Unified CLI for macOS PIM data",
        version: "0.1.0",
        subcommands: [
            Init.self,
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
