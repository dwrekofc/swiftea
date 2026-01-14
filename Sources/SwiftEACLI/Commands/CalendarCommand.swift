import ArgumentParser
import Foundation
import SwiftEAKit

// MARK: - Main Calendar Command

public struct Cal: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "cal",
        abstract: "Calendar operations (list, search, show, export)",
        subcommands: [
            CalCalendars.self,
            CalList.self,
            CalShow.self,
            CalSearch.self,
            CalExport.self,
            CalSync.self
        ]
    )

    public init() {}
}

// MARK: - List Calendars

struct CalCalendars: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calendars",
        abstract: "List available calendars"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        let vault = try VaultContext.require()

        // Open calendar database
        let calDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("calendar.db")
        let database = CalendarDatabase(databasePath: calDbPath)
        try database.initialize()
        defer { database.close() }

        let calendars = try database.getAllCalendars()

        if calendars.isEmpty {
            print("No calendars found. Run 'swiftea cal sync' first.")
            return
        }

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(calendars)
            print(String(data: data, encoding: .utf8) ?? "[]")
        } else {
            print("Calendars (\(calendars.count)):")
            print("")
            for calendar in calendars {
                let subscribed = calendar.isSubscribed ? " [subscribed]" : ""
                let source = calendar.sourceType.map { " (\($0))" } ?? ""
                print("  \(calendar.title)\(source)\(subscribed)")
                print("    ID: \(calendar.id)")
            }
        }
    }
}

// MARK: - List Events

struct CalList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List calendar events"
    )

    @Option(name: .long, help: "Filter by calendar name or ID")
    var calendar: String?

    @Flag(name: .long, help: "Show upcoming events (default)")
    var upcoming: Bool = false

    @Option(name: .long, help: "Start date (YYYY-MM-DD)")
    var from: String?

    @Option(name: .long, help: "End date (YYYY-MM-DD)")
    var to: String?

    @Option(name: .long, help: "Maximum results to return")
    var limit: Int = 20

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        let vault = try VaultContext.require()

        // Open calendar database
        let calDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("calendar.db")
        let database = CalendarDatabase(databasePath: calDbPath)
        try database.initialize()
        defer { database.close() }

        // Resolve calendar filter
        var calendarId: String? = nil
        if let calendarFilter = calendar {
            let calendars = try database.getAllCalendars()
            if let match = calendars.first(where: { $0.id == calendarFilter || $0.title.lowercased().contains(calendarFilter.lowercased()) }) {
                calendarId = match.id
            } else {
                print("Calendar not found: \(calendarFilter)")
                return
            }
        }

        // Parse date range
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let startDate: Date
        let endDate: Date

        if let fromStr = from, let parsedFrom = dateFormatter.date(from: fromStr) {
            startDate = parsedFrom
        } else {
            startDate = Date()
        }

        if let toStr = to, let parsedTo = dateFormatter.date(from: toStr) {
            endDate = parsedTo
        } else {
            // Default to 30 days from start
            endDate = Calendar.current.date(byAdding: .day, value: 30, to: startDate) ?? startDate
        }

        // Query events
        let events = try database.getEvents(from: startDate, to: endDate, calendarId: calendarId, limit: limit)

        if events.isEmpty {
            print("No events found in the specified date range.")
            return
        }

        if json {
            // Build exportable events
            let exportableEvents = try events.map { event -> ExportableEvent in
                let attendees = try database.getAttendees(eventId: event.id)
                let calendar = try database.getCalendar(id: event.calendarId)
                let exporter = JSONCalendarExporter()
                return createExportableEvent(event: event, attendees: attendees, calendar: calendar)
            }

            let envelope = CalendarExportEnvelope(items: exportableEvents)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(envelope)
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            print("Events (\(events.count)):")
            print("")
            for event in events {
                printEventSummary(event, database: database)
            }
        }
    }

    private func createExportableEvent(event: StoredEvent, attendees: [StoredAttendee], calendar: StoredCalendar?) -> ExportableEvent {
        let exportableAttendees = attendees.map { attendee in
            ExportableAttendee(
                name: attendee.name,
                email: attendee.email,
                responseStatus: attendee.responseStatus,
                isOrganizer: attendee.isOrganizer
            )
        }

        return ExportableEvent(
            id: event.id,
            title: event.summary,
            calendar: calendar?.title ?? "Unknown",
            calendarId: event.calendarId,
            start: CalendarDateFormatter.formatISO(event.startDateUtc, isAllDay: event.isAllDay),
            end: CalendarDateFormatter.formatISO(event.endDateUtc, isAllDay: event.isAllDay),
            isAllDay: event.isAllDay,
            location: event.location,
            description: event.eventDescription,
            url: event.url,
            status: event.status,
            isRecurring: event.recurrenceRule != nil || event.masterEventId != nil,
            attendees: exportableAttendees
        )
    }

    private func printEventSummary(_ event: StoredEvent, database: CalendarDatabase) {
        let title = event.summary ?? "Untitled Event"
        let timeStr = CalendarDateFormatter.formatRange(
            start: event.startDateUtc,
            end: event.endDateUtc,
            isAllDay: event.isAllDay,
            timezone: event.startTimezone
        )

        print("  \(title)")
        print("    When: \(timeStr)")
        if let location = event.location, !location.isEmpty {
            print("    Where: \(location)")
        }
        if let calendar = try? database.getCalendar(id: event.calendarId) {
            print("    Calendar: \(calendar.title)")
        }
        print("    ID: \(event.id)")
        print("")
    }
}

// MARK: - Show Event

struct CalShow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show details of a calendar event"
    )

    @Argument(help: "Event ID")
    var eventId: String

    @Flag(name: .long, help: "Include attendee details")
    var withAttendees: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Flag(name: .long, help: "Output as ICS")
    var ics: Bool = false

    func run() async throws {
        let vault = try VaultContext.require()

        // Open calendar database
        let calDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("calendar.db")
        let database = CalendarDatabase(databasePath: calDbPath)
        try database.initialize()
        defer { database.close() }

        // Find event
        guard let event = try database.getEvent(id: eventId) else {
            print("Event not found: \(eventId)")
            return
        }

        let attendees = try database.getAttendees(eventId: event.id)
        let calendar = try database.getCalendar(id: event.calendarId)

        // Select output format
        let format: CalendarExportFormat
        if ics {
            format = .ics
        } else if json {
            format = .json
        } else {
            format = .markdown
        }

        let exporter = CalendarExporterFactory.create(format: format)
        let output = exporter.export(event: event, attendees: withAttendees || ics || json ? attendees : [], calendar: calendar)
        print(output)
    }
}

// MARK: - Search Events

struct CalSearch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search calendar events",
        discussion: """
            Search for calendar events using full-text search.

            The search uses FTS5 with BM25 ranking for relevance.
            Searches across event summary, description, and location.

            EXAMPLES:
              swiftea cal search "team meeting"
              swiftea cal search "conference" --calendar Work
              swiftea cal search "presentation" --limit 10 --json
            """
    )

    @Argument(help: "Search query")
    var query: String

    @Option(name: .long, help: "Filter by calendar name or ID")
    var calendar: String?

    @Option(name: .long, help: "Start date filter (YYYY-MM-DD)")
    var from: String?

    @Option(name: .long, help: "End date filter (YYYY-MM-DD)")
    var to: String?

    @Option(name: .long, help: "Filter by attendee email or name")
    var attendee: String?

    @Option(name: .long, help: "Maximum results to return")
    var limit: Int = 20

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        let vault = try VaultContext.require()

        // Open calendar database
        let calDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("calendar.db")
        let database = CalendarDatabase(databasePath: calDbPath)
        try database.initialize()
        defer { database.close() }

        // Search using FTS
        var results = try database.searchEvents(query: query, limit: limit)

        // Apply additional filters
        if let calendarFilter = calendar {
            let calendars = try database.getAllCalendars()
            if let match = calendars.first(where: { $0.id == calendarFilter || $0.title.lowercased().contains(calendarFilter.lowercased()) }) {
                results = results.filter { $0.calendarId == match.id }
            }
        }

        // Date range filter
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        if let fromStr = from, let fromDate = dateFormatter.date(from: fromStr) {
            let fromTimestamp = Int(fromDate.timeIntervalSince1970)
            results = results.filter { $0.startDateUtc >= fromTimestamp }
        }

        if let toStr = to, let toDate = dateFormatter.date(from: toStr) {
            let toTimestamp = Int(toDate.timeIntervalSince1970)
            results = results.filter { $0.endDateUtc <= toTimestamp }
        }

        // Attendee filter
        if let attendeeFilter = attendee?.lowercased() {
            results = try results.filter { event in
                let attendees = try database.getAttendees(eventId: event.id)
                return attendees.contains { att in
                    (att.email?.lowercased().contains(attendeeFilter) ?? false) ||
                    (att.name?.lowercased().contains(attendeeFilter) ?? false)
                }
            }
        }

        if results.isEmpty {
            print("No events found for: \(query)")
            return
        }

        if json {
            let exportableEvents = try results.map { event -> ExportableEvent in
                let attendees = try database.getAttendees(eventId: event.id)
                let calendar = try database.getCalendar(id: event.calendarId)
                return createExportableEvent(event: event, attendees: attendees, calendar: calendar)
            }

            let envelope = CalendarExportEnvelope(query: query, items: exportableEvents)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(envelope)
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            print("Search results for '\(query)' (\(results.count)):")
            print("")
            for event in results {
                printEventSummary(event, database: database)
            }
        }
    }

    private func createExportableEvent(event: StoredEvent, attendees: [StoredAttendee], calendar: StoredCalendar?) -> ExportableEvent {
        let exportableAttendees = attendees.map { attendee in
            ExportableAttendee(
                name: attendee.name,
                email: attendee.email,
                responseStatus: attendee.responseStatus,
                isOrganizer: attendee.isOrganizer
            )
        }

        return ExportableEvent(
            id: event.id,
            title: event.summary,
            calendar: calendar?.title ?? "Unknown",
            calendarId: event.calendarId,
            start: CalendarDateFormatter.formatISO(event.startDateUtc, isAllDay: event.isAllDay),
            end: CalendarDateFormatter.formatISO(event.endDateUtc, isAllDay: event.isAllDay),
            isAllDay: event.isAllDay,
            location: event.location,
            description: event.eventDescription,
            url: event.url,
            status: event.status,
            isRecurring: event.recurrenceRule != nil || event.masterEventId != nil,
            attendees: exportableAttendees
        )
    }

    private func printEventSummary(_ event: StoredEvent, database: CalendarDatabase) {
        let title = event.summary ?? "Untitled Event"
        let timeStr = CalendarDateFormatter.formatRange(
            start: event.startDateUtc,
            end: event.endDateUtc,
            isAllDay: event.isAllDay,
            timezone: event.startTimezone
        )

        print("  \(title)")
        print("    When: \(timeStr)")
        if let location = event.location, !location.isEmpty {
            print("    Where: \(location)")
        }
        if let calendar = try? database.getCalendar(id: event.calendarId) {
            print("    Calendar: \(calendar.title)")
        }
        print("    ID: \(event.id)")
        print("")
    }
}

// MARK: - Export Events

struct CalExport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export calendar events"
    )

    @Option(name: .long, help: "Filter by calendar name or ID")
    var calendar: String?

    @Option(name: .long, help: "Start date (YYYY-MM-DD)")
    var from: String?

    @Option(name: .long, help: "End date (YYYY-MM-DD)")
    var to: String?

    @Option(name: .long, help: "Export format: md (markdown), json, ics")
    var format: String = "md"

    @Option(name: .shortAndLong, help: "Output file path")
    var output: String?

    func run() async throws {
        let vault = try VaultContext.require()

        // Open calendar database
        let calDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("calendar.db")
        let database = CalendarDatabase(databasePath: calDbPath)
        try database.initialize()
        defer { database.close() }

        // Resolve calendar filter
        var calendarId: String? = nil
        if let calendarFilter = calendar {
            let calendars = try database.getAllCalendars()
            if let match = calendars.first(where: { $0.id == calendarFilter || $0.title.lowercased().contains(calendarFilter.lowercased()) }) {
                calendarId = match.id
            } else {
                print("Calendar not found: \(calendarFilter)")
                return
            }
        }

        // Parse date range
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let startDate: Date
        let endDate: Date

        if let fromStr = from, let parsedFrom = dateFormatter.date(from: fromStr) {
            startDate = parsedFrom
        } else {
            // Default to 30 days ago
            startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        }

        if let toStr = to, let parsedTo = dateFormatter.date(from: toStr) {
            endDate = parsedTo
        } else {
            // Default to 365 days from start
            endDate = Calendar.current.date(byAdding: .day, value: 365, to: startDate) ?? startDate
        }

        // Get events with attendees
        let eventsWithAttendees = try database.getEventsWithAttendees(from: startDate, to: endDate, calendarId: calendarId)

        if eventsWithAttendees.isEmpty {
            print("No events found in the specified date range.")
            return
        }

        // Build export data
        let exportData: [(StoredEvent, [StoredAttendee], StoredCalendar?)] = eventsWithAttendees.map { (event, attendees) in
            let calendar = try? database.getCalendar(id: event.calendarId)
            return (event, attendees, calendar)
        }

        // Parse format
        guard let exportFormat = CalendarExportFormat(rawValue: format.lowercased()) else {
            print("Invalid format: \(format). Use: md, json, or ics")
            return
        }

        let exporter = CalendarExporterFactory.create(format: exportFormat)
        let exportedContent = exporter.export(events: exportData, query: nil)

        // Output
        if let outputPath = output {
            try exportedContent.write(toFile: outputPath, atomically: true, encoding: .utf8)
            print("Exported \(eventsWithAttendees.count) events to: \(outputPath)")
        } else {
            print(exportedContent)
        }
    }
}

// MARK: - Sync Command (Placeholder - Full implementation in Track G)

struct CalSync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync calendar data from Apple Calendar"
    )

    @Flag(name: .long, help: "Watch for changes (continuous sync)")
    var watch: Bool = false

    @Flag(name: .long, help: "Only sync changes since last sync")
    var incremental: Bool = false

    @Flag(name: .long, help: "Show detailed progress")
    var verbose: Bool = false

    @MainActor
    func run() async throws {
        let vault = try VaultContext.require()

        // Open calendar database
        let calDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("calendar.db")
        let database = CalendarDatabase(databasePath: calDbPath)
        try database.initialize()
        defer { database.close() }

        // Create sync instance
        let sync = CalendarSync(database: database)

        // Set up progress reporting
        if verbose {
            sync.onProgress = { progress in
                print("[\(progress.phase.rawValue)] \(progress.message)")
                if progress.total > 0 {
                    print("  Progress: \(progress.current)/\(progress.total) (\(String(format: "%.1f", progress.percentage))%)")
                }
            }
        }

        print("Starting calendar sync...")

        do {
            let result = try await sync.sync(incremental: incremental)

            print("")
            print("Sync complete:")
            print("  Calendars: \(result.calendarsProcessed)")
            print("  Events: +\(result.eventsAdded) ~\(result.eventsUpdated) -\(result.eventsDeleted)")
            if result.attendeesProcessed > 0 {
                print("  Attendees: \(result.attendeesProcessed)")
            }
            if result.remindersProcessed > 0 {
                print("  Reminders: \(result.remindersProcessed)")
            }
            print("  Duration: \(String(format: "%.2f", result.duration))s")

            if !result.errors.isEmpty {
                print("")
                print("Warnings (\(result.errors.count)):")
                for error in result.errors.prefix(5) {
                    print("  - \(error)")
                }
                if result.errors.count > 5 {
                    print("  ... and \(result.errors.count - 5) more")
                }
            }
        } catch CalendarSyncError.permissionDenied(let error) {
            print("Error: Calendar access denied")
            print(error.localizedDescription)
            throw ExitCode.failure
        } catch {
            print("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        if watch {
            print("")
            print("Watch mode not yet implemented. See Track G.")
        }
    }
}
