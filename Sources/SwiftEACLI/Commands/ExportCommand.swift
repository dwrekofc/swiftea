import ArgumentParser

public struct Export: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export data to markdown or JSON"
    )

    @Option(name: .long, help: "Item ID to export")
    var id: String?

    @Option(name: .long, help: "Export format (markdown, json)")
    var format: String = "markdown"

    @Option(name: .long, help: "Output directory")
    var output: String?

    @Flag(name: .long, help: "Export all data")
    var all: Bool = false

    public init() {}

    public func run() throws {
        if all {
            print("Exporting all data to \(format)")
        } else if let id = id {
            print("Exporting item \(id) to \(format)")
        } else {
            print("Error: specify --id or --all")
        }

        if let output = output {
            print("Output directory: \(output)")
        }
    }
}
