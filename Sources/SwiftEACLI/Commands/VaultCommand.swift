import ArgumentParser

public struct Vault: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "vault",
        abstract: "Manage swiftea vaults",
        subcommands: [VaultInit.self]
    )

    public init() {}
}

struct VaultInit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize a new vault"
    )

    @Option(name: .long, help: "Vault path")
    var path: String?

    func run() throws {
        let vaultPath = path ?? "."
        print("Initializing vault at: \(vaultPath)")
    }
}
