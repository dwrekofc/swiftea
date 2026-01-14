// CalendarSync.swift - Synchronize EventKit calendar data to GRDB mirror
//
// Provides full and incremental sync from EventKit to the calendar database.
// Follows the MailSync pattern with progress callbacks and error handling.

import Foundation
import EventKit

// MARK: - Errors

/// Errors that can occur during calendar sync
public enum CalendarSyncError: Error, LocalizedError {
    case permissionDenied(CalendarPermissionError)
    case databaseError(Error)
    case eventKitError(Error)
    case syncFailed(underlying: Error)
    case notInitialized

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let error):
            return "Calendar permission denied: \(error.localizedDescription)"
        case .databaseError(let error):
            return "Database error during sync: \(error.localizedDescription)"
        case .eventKitError(let error):
            return "EventKit error during sync: \(error.localizedDescription)"
        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"
        case .notInitialized:
            return "Calendar sync not initialized"
        }
    }
}

// MARK: - Progress

/// Progress update during calendar sync
public struct CalendarSyncProgress: Sendable {
    public let phase: CalendarSyncPhase
    public let current: Int
    public let total: Int
    public let message: String

    public init(phase: CalendarSyncPhase, current: Int, total: Int, message: String) {
        self.phase = phase
        self.current = current
        self.total = total
        self.message = message
    }

    public var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total) * 100
    }
}

/// Phases of the calendar sync process
public enum CalendarSyncPhase: String, Sendable {
    case discovering = "Discovering"
    case syncingCalendars = "Syncing calendars"
    case syncingEvents = "Syncing events"
    case syncingAttendees = "Syncing attendees"
    case detectingDeletions = "Detecting deletions"
    case syncingReminders = "Syncing reminders"
    case indexing = "Indexing"
    case complete = "Complete"
}

// MARK: - Result

/// Result of a calendar sync operation
public struct CalendarSyncResult: Sendable {
    public let calendarsProcessed: Int
    public let eventsProcessed: Int
    public let eventsAdded: Int
    public let eventsUpdated: Int
    public let eventsDeleted: Int
    public let attendeesProcessed: Int
    public let remindersProcessed: Int
    public let errors: [String]
    public let duration: TimeInterval
    public let isIncremental: Bool

    public init(
        calendarsProcessed: Int,
        eventsProcessed: Int,
        eventsAdded: Int,
        eventsUpdated: Int,
        eventsDeleted: Int,
        attendeesProcessed: Int,
        remindersProcessed: Int = 0,
        errors: [String],
        duration: TimeInterval,
        isIncremental: Bool = false
    ) {
        self.calendarsProcessed = calendarsProcessed
        self.eventsProcessed = eventsProcessed
        self.eventsAdded = eventsAdded
        self.eventsUpdated = eventsUpdated
        self.eventsDeleted = eventsDeleted
        self.attendeesProcessed = attendeesProcessed
        self.remindersProcessed = remindersProcessed
        self.errors = errors
        self.duration = duration
        self.isIncremental = isIncremental
    }
}

// MARK: - Calendar Sync

/// Synchronizes EventKit calendar data to the GRDB mirror database
@MainActor
public final class CalendarSync {
    private let database: CalendarDatabase
    private let dataAccess: CalendarDataAccess
    private let idGenerator: CalendarIdGenerator

    /// Default date range for sync (days from now)
    public var dateRangeDays: Int = 365

    /// Progress callback
    public var onProgress: ((CalendarSyncProgress) -> Void)?

    public init(
        database: CalendarDatabase,
        dataAccess: CalendarDataAccess = .shared,
        idGenerator: CalendarIdGenerator = CalendarIdGenerator()
    ) {
        self.database = database
        self.dataAccess = dataAccess
        self.idGenerator = idGenerator
    }

    /// Run a sync from EventKit to the mirror database
    /// - Parameter incremental: If true, only sync changes since last sync
    public func sync(incremental: Bool = false) async throws -> CalendarSyncResult {
        let startTime = Date()
        var errors: [String] = []
        var calendarsProcessed = 0
        var eventsProcessed = 0
        var eventsAdded = 0
        var eventsUpdated = 0
        var eventsDeleted = 0
        var attendeesProcessed = 0
        var remindersProcessed = 0

        // Record sync start
        try database.setSyncStatus(key: CalendarSyncStatus.Key.state, value: CalendarSyncStatus.State.running.rawValue)
        try database.setSyncStatus(key: CalendarSyncStatus.Key.lastSyncStartTime, value: String(startTime.timeIntervalSince1970))

        do {
            // Ensure we have calendar access
            reportProgress(.discovering, 0, 1, "Checking calendar permissions...")
            do {
                _ = try await dataAccess.requestAccess()
            } catch let error as CalendarPermissionError {
                throw CalendarSyncError.permissionDenied(error)
            }

            // Sync calendars first
            reportProgress(.syncingCalendars, 0, 1, "Discovering calendars...")
            calendarsProcessed = try await syncCalendars()

            // Calculate date range for events
            let now = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
            let endDate = Calendar.current.date(byAdding: .day, value: dateRangeDays, to: now) ?? now

            // Store date range in sync status
            try database.setSyncStatus(key: CalendarSyncStatus.Key.dateRangeStart, value: String(startDate.timeIntervalSince1970))
            try database.setSyncStatus(key: CalendarSyncStatus.Key.dateRangeEnd, value: String(endDate.timeIntervalSince1970))

            // Get last sync time for incremental
            var lastSyncTime: Date? = nil
            if incremental {
                lastSyncTime = try database.getLastSyncTime()
            }

            // Sync events
            let eventResult: (processed: Int, added: Int, updated: Int, deleted: Int, attendees: Int)
            if incremental, let lastSync = lastSyncTime {
                eventResult = try await syncEventsIncremental(
                    startDate: startDate,
                    endDate: endDate,
                    since: lastSync,
                    errors: &errors
                )
            } else {
                eventResult = try await syncEventsFull(
                    startDate: startDate,
                    endDate: endDate,
                    errors: &errors
                )
            }

            eventsProcessed = eventResult.processed
            eventsAdded = eventResult.added
            eventsUpdated = eventResult.updated
            eventsDeleted = eventResult.deleted
            attendeesProcessed = eventResult.attendees

            // Sync reminders (read-only)
            reportProgress(.syncingReminders, 0, 1, "Syncing reminders...")
            remindersProcessed = try await syncReminders(errors: &errors)

            // Record sync success
            let duration = Date().timeIntervalSince(startTime)
            try database.setSyncStatus(key: CalendarSyncStatus.Key.state, value: CalendarSyncStatus.State.success.rawValue)
            try database.setSyncStatus(key: CalendarSyncStatus.Key.lastSyncTime, value: String(Date().timeIntervalSince1970))
            try database.setSyncStatus(key: CalendarSyncStatus.Key.lastSyncEndTime, value: String(Date().timeIntervalSince1970))
            try database.setSyncStatus(key: CalendarSyncStatus.Key.syncDuration, value: String(duration))
            try database.setSyncStatus(key: CalendarSyncStatus.Key.eventsAdded, value: String(eventsAdded))
            try database.setSyncStatus(key: CalendarSyncStatus.Key.eventsUpdated, value: String(eventsUpdated))
            try database.setSyncStatus(key: CalendarSyncStatus.Key.eventsDeleted, value: String(eventsDeleted))

            reportProgress(.complete, 1, 1, "Sync complete")

            return CalendarSyncResult(
                calendarsProcessed: calendarsProcessed,
                eventsProcessed: eventsProcessed,
                eventsAdded: eventsAdded,
                eventsUpdated: eventsUpdated,
                eventsDeleted: eventsDeleted,
                attendeesProcessed: attendeesProcessed,
                remindersProcessed: remindersProcessed,
                errors: errors,
                duration: Date().timeIntervalSince(startTime),
                isIncremental: incremental
            )
        } catch {
            // Record sync failure
            try? database.setSyncStatus(key: CalendarSyncStatus.Key.state, value: CalendarSyncStatus.State.failed.rawValue)
            try? database.setSyncStatus(key: CalendarSyncStatus.Key.lastSyncError, value: error.localizedDescription)

            if let syncError = error as? CalendarSyncError {
                throw syncError
            }
            throw CalendarSyncError.syncFailed(underlying: error)
        }
    }

    // MARK: - Calendar Sync

    /// Sync all calendars from EventKit
    private func syncCalendars() async throws -> Int {
        let calendars = try await dataAccess.getAllCalendars()

        reportProgress(.syncingCalendars, 0, calendars.count, "Syncing \(calendars.count) calendars...")

        for (index, calendar) in calendars.enumerated() {
            let storedCalendar = dataAccess.transformToStoredCalendar(calendar, using: idGenerator)
            try database.upsertCalendar(storedCalendar)

            reportProgress(.syncingCalendars, index + 1, calendars.count, "Synced calendar: \(calendar.title)")
        }

        return calendars.count
    }

    // MARK: - Event Sync (Full)

    /// Full sync of all events in date range
    private func syncEventsFull(
        startDate: Date,
        endDate: Date,
        errors: inout [String]
    ) async throws -> (processed: Int, added: Int, updated: Int, deleted: Int, attendees: Int) {
        var processed = 0
        var added = 0
        var updated = 0
        var attendeesCount = 0

        // Get all calendars
        let calendars = try await dataAccess.getAllCalendars()

        // Track all event IDs we see for deletion detection
        var seenEventIds = Set<String>()

        // Query events for each calendar
        for calendar in calendars {
            reportProgress(.syncingEvents, processed, 0, "Querying events from \(calendar.title)...")

            let events = try await dataAccess.getEvents(
                from: startDate,
                to: endDate,
                calendars: [calendar]
            )

            reportProgress(.syncingEvents, processed, processed + events.count, "Processing \(events.count) events from \(calendar.title)...")

            for event in events {
                do {
                    let result = try syncEvent(event)
                    seenEventIds.insert(result.id)

                    if result.isNew {
                        added += 1
                    } else {
                        updated += 1
                    }

                    // Sync attendees
                    let attendeeCount = try syncAttendees(for: event, eventId: result.id)
                    attendeesCount += attendeeCount

                    processed += 1
                    if processed % 100 == 0 {
                        reportProgress(.syncingEvents, processed, processed + (events.count - processed % events.count), "Processed \(processed) events...")
                    }
                } catch {
                    errors.append("Failed to sync event '\(event.title ?? "Unknown")': \(error.localizedDescription)")
                }
            }
        }

        // Detect deletions per calendar
        reportProgress(.detectingDeletions, 0, calendars.count, "Detecting deleted events...")
        var deleted = 0

        for calendar in calendars {
            let calendarId = idGenerator.generateCalendarId(
                calendarIdentifier: calendar.calendarIdentifier,
                title: calendar.title,
                source: calendar.source?.title
            )

            // Get IDs of events we've seen for this calendar
            let calendarEventIds = seenEventIds.filter { id in
                // Events from this calendar will have the calendar ID in their public ID
                id.contains(calendarId) || id.hasPrefix("cal-")
            }

            let deletedCount = try database.deleteEventsNotIn(ids: calendarEventIds, forCalendar: calendarId)
            deleted += deletedCount
        }

        return (processed, added, updated, deleted, attendeesCount)
    }

    // MARK: - Event Sync (Incremental)

    /// Incremental sync of events modified since last sync
    private func syncEventsIncremental(
        startDate: Date,
        endDate: Date,
        since lastSync: Date,
        errors: inout [String]
    ) async throws -> (processed: Int, added: Int, updated: Int, deleted: Int, attendees: Int) {
        // For EventKit, we can't easily query "modified since" directly
        // So we do a full query but compare modification dates during upsert
        // EventKit handles the heavy lifting internally

        return try await syncEventsFull(startDate: startDate, endDate: endDate, errors: &errors)
    }

    // MARK: - Single Event Sync

    /// Sync a single event and return result
    private func syncEvent(_ event: EKEvent) throws -> (id: String, isNew: Bool) {
        let storedEvent = dataAccess.transformToStoredEvent(event, using: idGenerator)

        // Check if event already exists
        let existing = try database.getEvent(id: storedEvent.id)
        let isNew = existing == nil

        // Upsert the event
        try database.upsertEvent(storedEvent)

        return (storedEvent.id, isNew)
    }

    // MARK: - Attendee Sync

    /// Sync attendees for an event
    private func syncAttendees(for event: EKEvent, eventId: String) throws -> Int {
        let extractedAttendees = dataAccess.extractAttendees(from: event)

        // Include organizer if present
        var allAttendees: [CalendarDataAccess.ExtractedAttendee] = extractedAttendees
        if let organizer = dataAccess.extractOrganizer(from: event) {
            // Only add if not already in attendees
            let organizerEmail = organizer.email?.lowercased()
            if !extractedAttendees.contains(where: { $0.email?.lowercased() == organizerEmail }) {
                allAttendees.insert(organizer, at: 0)
            }
        }

        // Transform to stored attendees
        let storedAttendees = allAttendees.map { attendee in
            StoredAttendee(
                eventId: eventId,
                name: attendee.name,
                email: attendee.email,
                responseStatus: attendee.responseStatusString,
                isOrganizer: attendee.isOrganizer,
                isOptional: attendee.isOptional
            )
        }

        // Replace attendees (delete existing, insert new)
        try database.replaceAttendees(eventId: eventId, attendees: storedAttendees)

        return storedAttendees.count
    }

    // MARK: - Reminder Sync

    /// Sync reminders (read-only)
    private func syncReminders(errors: inout [String]) async throws -> Int {
        // Check if we have reminder access
        do {
            let hasAccess = try await dataAccess.requestReminderAccess()
            guard hasAccess else {
                return 0
            }
        } catch {
            // Reminder access is optional, don't fail sync
            return 0
        }

        // Get reminders
        let reminders = try await dataAccess.getReminders()

        for reminder in reminders {
            do {
                let storedReminder = StoredReminder(
                    id: idGenerator.generateReminderId(
                        identifier: reminder.calendarItemIdentifier,
                        title: reminder.title
                    ),
                    eventkitId: reminder.calendarItemIdentifier,
                    calendarId: reminder.calendarIdentifier,
                    title: reminder.title,
                    notes: reminder.notes,
                    dueDate: reminder.dueDate.map { Int($0.timeIntervalSince1970) },
                    priority: reminder.priority,
                    isCompleted: reminder.isCompleted,
                    completedAt: reminder.completionDate.map { Int($0.timeIntervalSince1970) },
                    syncedAt: Int(Date().timeIntervalSince1970)
                )

                try database.upsertReminder(storedReminder)
            } catch {
                errors.append("Failed to sync reminder '\(reminder.title ?? "Unknown")': \(error.localizedDescription)")
            }
        }

        return reminders.count
    }

    // MARK: - Progress Reporting

    private func reportProgress(_ phase: CalendarSyncPhase, _ current: Int, _ total: Int, _ message: String) {
        let progress = CalendarSyncProgress(phase: phase, current: current, total: total, message: message)
        onProgress?(progress)
    }
}

// MARK: - ID Generator Extension

extension CalendarIdGenerator {
    /// Generate a reminder ID using the fallback ID mechanism
    func generateReminderId(identifier: String, title: String?) -> String {
        // Use the same approach as event fallback IDs
        return generateFallbackId(
            calendarId: "reminders",
            summary: title,
            startDate: Date(timeIntervalSince1970: Double(identifier.hashValue))
        )
    }
}
