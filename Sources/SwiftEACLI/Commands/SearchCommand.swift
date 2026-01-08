import ArgumentParser

public struct Search: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search across all modules"
    )

    @Argument(help: "Search query")
    var query: String

    @Flag(name: .long, help: "Search mail only")
    var mail: Bool = false

    @Flag(name: .long, help: "Search calendar only")
    var calendar: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    public init() {}

    public func run() throws {
        print("Searching for: \(query)")
        if mail {
            print("Scope: mail")
        }
        if calendar {
            print("Scope: calendar")
        }
        if json {
            print("Output format: JSON")
        }
    }
}
