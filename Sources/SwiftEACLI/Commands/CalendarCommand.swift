import AppKit
import ArgumentParser
import EventKit
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
            print("No calendars found. Run 'swea cal sync' first.")
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
              swea cal search "team meeting"
              swea cal search "conference" --calendar Work
              swea cal search "presentation" --limit 10 --json
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

// MARK: - Sync Command

struct CalSync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync calendar data from Apple Calendar",
        discussion: """
            Synchronizes calendar data from Apple Calendar (EventKit) to the local database.

            WATCH MODE
            Use --watch to install a persistent sync daemon that:
            - Runs periodic syncs every 5 minutes
            - Triggers immediate sync on system wake from sleep
            - Listens for EKEventStoreChangedNotification for real-time updates

            EXAMPLES
              # Run a one-time sync
              swea cal sync

              # Run incremental sync (only changes since last sync)
              swea cal sync --incremental

              # Install and start watch daemon
              swea cal sync --watch

              # Check sync and daemon status
              swea cal sync --status

              # Stop the watch daemon
              swea cal sync --stop
            """
    )

    @Flag(name: .long, help: "Install and start watch daemon for continuous sync")
    var watch: Bool = false

    @Flag(name: .long, help: "Stop the watch daemon")
    var stop: Bool = false

    @Flag(name: .long, help: "Show sync status and watch daemon state")
    var status: Bool = false

    @Flag(name: .long, help: "Only sync changes since last sync")
    var incremental: Bool = false

    @Flag(name: .long, help: "Show detailed progress")
    var verbose: Bool = false

    @Flag(name: .long, help: "Run as persistent daemon with sleep/wake detection (internal use)")
    var daemon: Bool = false

    // MARK: - Retry Configuration (for daemon mode)

    private static let maxRetryAttempts = 5
    private static let baseRetryDelay: TimeInterval = 2.0
    private static let maxRetryDelay: TimeInterval = 60.0

    private func isTransientError(_ error: Error) -> Bool {
        let description = error.localizedDescription.lowercased()
        return description.contains("locked") ||
               description.contains("busy") ||
               description.contains("timeout") ||
               description.contains("temporarily") ||
               description.contains("try again")
    }

    // MARK: - Daemon-safe Logging

    private var isDaemonMode: Bool {
        return isatty(STDOUT_FILENO) == 0
    }

    private func log(_ message: String) {
        if isDaemonMode {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            fputs("[\(timestamp)] \(message)\n", stdout)
            fflush(stdout)
        } else {
            print(message)
        }
    }

    private func logError(_ message: String) {
        if isDaemonMode {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            fputs("[\(timestamp)] ERROR: \(message)\n", stderr)
            fflush(stderr)
        } else {
            fputs("Error: \(message)\n", stderr)
        }
    }

    @MainActor
    func run() async throws {
        if isDaemonMode {
            log("cal sync started (daemon mode, pid=\(ProcessInfo.processInfo.processIdentifier))")
            log("working directory: \(FileManager.default.currentDirectoryPath)")
        }

        if isDaemonMode {
            try await executeSyncWithRetry()
        } else {
            do {
                try await executeSync()
            } catch {
                logError("\(error.localizedDescription)")
                throw error
            }
        }
    }

    @MainActor
    private func executeSyncWithRetry() async throws {
        var lastError: Error?
        var attempt = 0

        while attempt < Self.maxRetryAttempts {
            do {
                try await executeSync()
                log("cal sync completed successfully")
                return
            } catch {
                lastError = error
                attempt += 1

                if isTransientError(error) && attempt < Self.maxRetryAttempts {
                    let delay = min(
                        Self.baseRetryDelay * pow(2.0, Double(attempt - 1)),
                        Self.maxRetryDelay
                    )
                    let jitter = delay * Double.random(in: 0.1...0.2)
                    let totalDelay = delay + jitter

                    log("Transient error (attempt \(attempt)/\(Self.maxRetryAttempts)): \(error.localizedDescription)")
                    log("Retrying in \(String(format: "%.1f", totalDelay)) seconds...")

                    try await Task.sleep(nanoseconds: UInt64(totalDelay * 1_000_000_000))
                } else {
                    break
                }
            }
        }

        if let error = lastError {
            logError("Sync failed after \(attempt) attempt(s): \(error.localizedDescription)")
            log("cal sync failed")
            throw error
        }
    }

    @MainActor
    private func executeSync() async throws {
        let vault = try VaultContext.require()

        let calDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("calendar.db")
        let database = CalendarDatabase(databasePath: calDbPath)
        try database.initialize()
        defer { database.close() }

        if verbose || isDaemonMode {
            log("Calendar database: \(calDbPath)")
        }

        // Handle --status flag
        if status {
            try showSyncStatus(database: database, vault: vault)
            return
        }

        // Handle --watch flag
        if watch {
            try await installWatchDaemon(vault: vault, database: database)
            return
        }

        // Handle --stop flag
        if stop {
            try stopWatchDaemon()
            return
        }

        // Handle --daemon flag: run as persistent daemon
        if daemon {
            try await runPersistentDaemon(database: database)
            return
        }

        // Regular sync
        let sync = CalendarSync(database: database)

        if verbose {
            sync.onProgress = { progress in
                print("[\(progress.phase.rawValue)] \(progress.message)")
                if progress.total > 0 {
                    print("  Progress: \(progress.current)/\(progress.total) (\(String(format: "%.1f", progress.percentage))%)")
                }
            }
        }

        log("Starting calendar sync...")

        do {
            let result = try await sync.sync(incremental: incremental)

            log("")
            log("Sync complete:")
            log("  Calendars: \(result.calendarsProcessed)")
            log("  Events: +\(result.eventsAdded) ~\(result.eventsUpdated) -\(result.eventsDeleted)")
            if result.attendeesProcessed > 0 {
                log("  Attendees: \(result.attendeesProcessed)")
            }
            if result.remindersProcessed > 0 {
                log("  Reminders: \(result.remindersProcessed)")
            }
            log("  Duration: \(String(format: "%.2f", result.duration))s")

            if !result.errors.isEmpty {
                log("")
                log("Warnings (\(result.errors.count)):")
                for error in result.errors.prefix(5) {
                    log("  - \(error)")
                }
                if result.errors.count > 5 {
                    log("  ... and \(result.errors.count - 5) more")
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
    }

    // MARK: - Status

    private func showSyncStatus(database: CalendarDatabase, vault: VaultContext) throws {
        let daemonStatus = getDaemonStatus()

        print("Calendar Sync Status")
        print("====================")
        print("")

        // Daemon status
        print("Watch Daemon: \(daemonStatus.isRunning ? "running" : "stopped")")
        if let pid = daemonStatus.pid {
            print("  PID: \(pid)")
        }
        print("")

        // Sync state from database
        print("Last Sync:")
        if let lastSyncTimeStr = try? database.getSyncStatus(key: CalendarSyncStatus.Key.lastSyncTime),
           let timestamp = Double(lastSyncTimeStr) {
            let lastSyncDate = Date(timeIntervalSince1970: timestamp)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            print("  Time: \(formatter.string(from: lastSyncDate))")
        } else {
            print("  Time: Never")
        }

        if let stateStr = try? database.getSyncStatus(key: CalendarSyncStatus.Key.state) {
            print("  State: \(stateStr)")
        }

        if let durationStr = try? database.getSyncStatus(key: CalendarSyncStatus.Key.syncDuration),
           let duration = Double(durationStr) {
            print("  Duration: \(String(format: "%.2f", duration))s")
        }

        // Event counts from last sync
        if let addedStr = try? database.getSyncStatus(key: CalendarSyncStatus.Key.eventsAdded),
           let updatedStr = try? database.getSyncStatus(key: CalendarSyncStatus.Key.eventsUpdated),
           let deletedStr = try? database.getSyncStatus(key: CalendarSyncStatus.Key.eventsDeleted) {
            let added = Int(addedStr) ?? 0
            let updated = Int(updatedStr) ?? 0
            let deleted = Int(deletedStr) ?? 0
            if added > 0 || updated > 0 || deleted > 0 {
                print("  Events: +\(added) ~\(updated) -\(deleted)")
            }
        }

        // Error if any
        if let error = try? database.getSyncStatus(key: CalendarSyncStatus.Key.lastSyncError),
           !error.isEmpty {
            print("")
            print("Last Error: \(error)")
        }

        // Database location
        print("")
        print("Database: \(vault.dataFolderPath)/calendar.db")
    }

    private struct DaemonStatus {
        let isRunning: Bool
        let pid: Int?
    }

    private func getDaemonStatus() -> DaemonStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    for line in output.split(separator: "\n") {
                        if line.contains(Self.launchAgentLabel) {
                            let components = line.split(separator: "\t")
                            if components.count >= 3 {
                                let pidStr = String(components[0])
                                if pidStr != "-", let pid = Int(pidStr), pid > 0 {
                                    return DaemonStatus(isRunning: true, pid: pid)
                                }
                                return DaemonStatus(isRunning: false, pid: nil)
                            }
                        }
                    }
                }
            }
        } catch {
            // launchctl failed, daemon not loaded
        }

        return DaemonStatus(isRunning: false, pid: nil)
    }

    // MARK: - Watch Daemon

    private static let launchAgentLabel = "com.swiftea.calendar.sync"
    private static let syncIntervalSeconds = 300 // 5 minutes

    private func getLaunchAgentPath() -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDir)/Library/LaunchAgents/\(Self.launchAgentLabel).plist"
    }

    @MainActor
    private func installWatchDaemon(vault: VaultContext, database: CalendarDatabase) async throws {
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

        // Run initial sync before starting watch daemon
        print("Running initial sync before starting watch daemon...")

        // Check if we have any events - if not, do a full sync; otherwise incremental
        let existingEvents = try database.getEvents(from: Date(), to: Date().addingTimeInterval(86400), calendarId: nil, limit: 1)
        let isFirstSync = existingEvents.isEmpty

        let sync = CalendarSync(database: database)

        do {
            let result = try await sync.sync(incremental: !isFirstSync)
            print("Initial sync complete:")
            print("  Events: +\(result.eventsAdded) ~\(result.eventsUpdated)")
            print("  Duration: \(String(format: "%.2f", result.duration))s")
            if !result.errors.isEmpty {
                print("  Warnings: \(result.errors.count)")
            }
        } catch {
            print("Warning: Initial sync failed: \(error.localizedDescription)")
            print("The daemon will retry on its first run.")
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
                    <string>cal</string>
                    <string>sync</string>
                    <string>--daemon</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <true/>
                <key>StandardOutPath</key>
                <string>\(logDir)/cal-sync.log</string>
                <key>StandardErrorPath</key>
                <string>\(logDir)/cal-sync.log</string>
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
        print("  Mode: Persistent daemon with sleep/wake detection")
        print("  Syncing every \(Self.syncIntervalSeconds / 60) minutes + on wake + on calendar changes")
        print("  Logs: \(logDir)/cal-sync.log")
        print("")
        print("Use 'swea cal sync --status' to check status")
        print("Use 'swea cal sync --stop' to stop the daemon")
    }

    private func stopWatchDaemon() throws {
        let launchAgentPath = getLaunchAgentPath()

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

    // MARK: - Persistent Daemon

    @MainActor
    private func runPersistentDaemon(database: CalendarDatabase) async throws {
        log("Starting persistent calendar sync daemon (pid=\(ProcessInfo.processInfo.processIdentifier))")

        // Run initial incremental sync on startup
        log("Running initial sync...")
        await performDaemonSync(database: database)

        // Create a daemon controller to handle sleep/wake and EventKit notifications
        let controller = CalendarSyncDaemonController(database: database, logger: log)

        // Start the run loop - this blocks until the daemon is terminated
        controller.startRunLoop()

        log("Daemon shutting down")
    }

    @MainActor
    private func performDaemonSync(database: CalendarDatabase) async {
        let maxRetryAttempts = 5
        let baseRetryDelay: TimeInterval = 2.0
        let maxRetryDelay: TimeInterval = 60.0

        var attempt = 0

        while attempt < maxRetryAttempts {
            do {
                let sync = CalendarSync(database: database)
                let result = try await sync.sync(incremental: true)

                let timestamp = ISO8601DateFormatter().string(from: Date())
                fputs("[\(timestamp)] Sync complete: +\(result.eventsAdded) ~\(result.eventsUpdated) (\(String(format: "%.2f", result.duration))s)\n", stdout)
                fflush(stdout)
                return

            } catch {
                attempt += 1

                let description = error.localizedDescription.lowercased()
                let isTransient = description.contains("locked") ||
                                  description.contains("busy") ||
                                  description.contains("timeout") ||
                                  description.contains("temporarily") ||
                                  description.contains("try again")

                if isTransient && attempt < maxRetryAttempts {
                    let delay = min(baseRetryDelay * pow(2.0, Double(attempt - 1)), maxRetryDelay)
                    let jitter = delay * Double.random(in: 0.1...0.2)
                    let totalDelay = delay + jitter

                    let timestamp = ISO8601DateFormatter().string(from: Date())
                    fputs("[\(timestamp)] Transient error (attempt \(attempt)/\(maxRetryAttempts)): \(error.localizedDescription)\n", stdout)
                    fputs("[\(timestamp)] Retrying in \(String(format: "%.1f", totalDelay))s...\n", stdout)
                    fflush(stdout)

                    try? await Task.sleep(nanoseconds: UInt64(totalDelay * 1_000_000_000))
                } else {
                    let timestamp = ISO8601DateFormatter().string(from: Date())
                    fputs("[\(timestamp)] ERROR: Initial sync failed: \(error.localizedDescription)\n", stderr)
                    fflush(stderr)
                    return
                }
            }
        }
    }
}

// MARK: - Calendar Sync Daemon Controller

/// Controls the calendar sync daemon with sleep/wake detection and EventKit change notifications.
final class CalendarSyncDaemonController: NSObject {
    private let database: CalendarDatabase
    private let logger: (String) -> Void
    private var isSyncing = false
    private let syncQueue = DispatchQueue(label: "com.swiftea.calendar.sync.daemon")
    private var syncTimer: Timer?
    private let eventStore = EKEventStore()

    private static let syncIntervalSeconds: TimeInterval = 300
    private static let minSyncIntervalSeconds: TimeInterval = 30

    private var lastSyncTime: Date?

    init(database: CalendarDatabase, logger: @escaping (String) -> Void) {
        self.database = database
        self.logger = logger
        super.init()

        registerForPowerNotifications()
        registerForEventKitNotifications()
    }

    deinit {
        unregisterForNotifications()
        syncTimer?.invalidate()
    }

    func startRunLoop() {
        scheduleSyncTimer()
        RunLoop.current.run()
    }

    // MARK: - Power Notifications

    private func registerForPowerNotifications() {
        let workspace = NSWorkspace.shared
        let center = workspace.notificationCenter

        center.addObserver(
            self,
            selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        center.addObserver(
            self,
            selector: #selector(systemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        logger("Registered for sleep/wake notifications")
    }

    private func registerForEventKitNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(eventStoreChanged(_:)),
            name: .EKEventStoreChanged,
            object: eventStore
        )

        logger("Registered for EKEventStoreChangedNotification")
    }

    private func unregisterForNotifications() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func systemDidWake(_ notification: Notification) {
        logger("System woke from sleep - triggering catch-up sync")
        triggerSync(reason: "wake")
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        logger("System going to sleep")
        syncTimer?.invalidate()
        syncTimer = nil
    }

    @objc private func eventStoreChanged(_ notification: Notification) {
        logger("EventKit data changed - triggering sync")
        triggerSync(reason: "eventkit-change")
    }

    // MARK: - Sync Timer

    private func scheduleSyncTimer() {
        syncTimer?.invalidate()

        syncTimer = Timer.scheduledTimer(withTimeInterval: Self.syncIntervalSeconds, repeats: true) { [weak self] _ in
            self?.triggerSync(reason: "scheduled")
        }

        logger("Scheduled sync timer (every \(Int(Self.syncIntervalSeconds))s)")
    }

    // MARK: - Sync Execution

    private func triggerSync(reason: String) {
        // Debounce: don't sync if we synced very recently
        if let lastSync = lastSyncTime {
            let elapsed = Date().timeIntervalSince(lastSync)
            if elapsed < Self.minSyncIntervalSeconds {
                logger("Skipping \(reason) sync (last sync was \(Int(elapsed))s ago)")
                return
            }
        }

        syncQueue.async { [weak self] in
            guard let self = self else { return }

            if self.isSyncing {
                self.logger("Sync already in progress, skipping \(reason) sync")
                return
            }

            self.isSyncing = true
            self.lastSyncTime = Date()

            // Run sync on main actor
            Task { @MainActor in
                await self.performSync(reason: reason)
                self.isSyncing = false

                // Re-schedule timer after wake
                if reason == "wake" {
                    self.scheduleSyncTimer()
                }
            }
        }
    }

    @MainActor
    private func performSync(reason: String) async {
        logger("Starting \(reason) sync...")

        let maxRetryAttempts = 5
        let baseRetryDelay: TimeInterval = 2.0
        let maxRetryDelay: TimeInterval = 60.0

        var attempt = 0
        var lastError: Error?

        while attempt < maxRetryAttempts {
            do {
                let sync = CalendarSync(database: database)
                let result = try await sync.sync(incremental: true)

                logger("Sync complete: +\(result.eventsAdded) ~\(result.eventsUpdated) (\(String(format: "%.2f", result.duration))s)")

                if !result.errors.isEmpty {
                    logger("  \(result.errors.count) warning(s)")
                }
                return

            } catch {
                lastError = error
                attempt += 1

                let description = error.localizedDescription.lowercased()
                let isTransient = description.contains("locked") ||
                                  description.contains("busy") ||
                                  description.contains("timeout") ||
                                  description.contains("temporarily") ||
                                  description.contains("try again")

                if isTransient && attempt < maxRetryAttempts {
                    let delay = min(baseRetryDelay * pow(2.0, Double(attempt - 1)), maxRetryDelay)
                    let jitter = delay * Double.random(in: 0.1...0.2)
                    let totalDelay = delay + jitter

                    logger("Transient error (attempt \(attempt)/\(maxRetryAttempts)): \(error.localizedDescription)")
                    logger("Retrying in \(String(format: "%.1f", totalDelay))s...")

                    try? await Task.sleep(nanoseconds: UInt64(totalDelay * 1_000_000_000))
                } else {
                    break
                }
            }
        }

        if let error = lastError {
            logger("ERROR: Sync failed after \(attempt) attempt(s): \(error.localizedDescription)")
        }
    }
}
