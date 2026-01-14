// CalendarDataAccess.swift - EventKit data access layer
//
// Provides read access to calendars, events, and reminders via EventKit.
// Uses singleton EKEventStore with proper permission handling.

import Foundation
import EventKit

// MARK: - Permission Errors

/// Errors related to calendar access permissions
public enum CalendarPermissionError: Error, LocalizedError {
    case denied
    case restricted
    case notDetermined
    case unknown(Error?)

    public var errorDescription: String? {
        switch self {
        case .denied:
            return "Calendar access denied. Please enable in System Settings > Privacy & Security > Calendars"
        case .restricted:
            return "Calendar access is restricted by device policy"
        case .notDetermined:
            return "Calendar permission not yet requested"
        case .unknown(let error):
            if let error = error {
                return "Calendar access error: \(error.localizedDescription)"
            }
            return "Unknown calendar access error"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .denied:
            return "Open System Settings > Privacy & Security > Calendars and enable access for this app"
        case .restricted:
            return "Contact your system administrator to enable calendar access"
        case .notDetermined:
            return "The app will request permission on first use"
        case .unknown:
            return nil
        }
    }
}

// MARK: - Data Access Errors

/// Errors during calendar data access
public enum CalendarDataAccessError: Error, LocalizedError {
    case permissionError(CalendarPermissionError)
    case queryFailed(Error)
    case invalidCalendar(String)
    case eventNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .permissionError(let error):
            return error.errorDescription
        case .queryFailed(let error):
            return "Failed to query calendar data: \(error.localizedDescription)"
        case .invalidCalendar(let id):
            return "Invalid or inaccessible calendar: \(id)"
        case .eventNotFound(let id):
            return "Event not found: \(id)"
        }
    }
}

// MARK: - Calendar Data Access

/// Provides read access to EventKit calendars and events.
/// Uses a singleton EKEventStore for efficient access.
@MainActor
public final class CalendarDataAccess: Sendable {
    /// Shared singleton instance
    public static let shared = CalendarDataAccess()

    /// The EventKit event store
    private let eventStore: EKEventStore

    /// Current authorization status
    public var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// Whether we have calendar access
    public var hasAccess: Bool {
        authorizationStatus == .fullAccess || authorizationStatus == .authorized
    }

    private init() {
        self.eventStore = EKEventStore()
    }

    // MARK: - Permission Handling

    /// Request calendar access permission.
    /// Uses appropriate API based on macOS version.
    ///
    /// - Returns: True if access was granted
    /// - Throws: CalendarPermissionError if access denied or error occurs
    public func requestAccess() async throws -> Bool {
        // Check current status first
        let status = authorizationStatus

        switch status {
        case .fullAccess, .authorized:
            return true

        case .denied:
            throw CalendarPermissionError.denied

        case .restricted:
            throw CalendarPermissionError.restricted

        case .notDetermined:
            // Request permission
            return try await requestPermission()

        case .writeOnly:
            // We need read access, not just write
            throw CalendarPermissionError.denied

        @unknown default:
            throw CalendarPermissionError.unknown(nil)
        }
    }

    /// Request permission using appropriate API for OS version.
    private func requestPermission() async throws -> Bool {
        do {
            // macOS 14+ uses requestFullAccessToEvents()
            if #available(macOS 14.0, *) {
                let granted = try await eventStore.requestFullAccessToEvents()
                if !granted {
                    throw CalendarPermissionError.denied
                }
                return granted
            } else {
                // Earlier versions use requestAccess(to:)
                let granted = try await eventStore.requestAccess(to: .event)
                if !granted {
                    throw CalendarPermissionError.denied
                }
                return granted
            }
        } catch let error as CalendarPermissionError {
            throw error
        } catch {
            throw CalendarPermissionError.unknown(error)
        }
    }

    /// Ensure we have permission, requesting if needed.
    public func ensureAccess() async throws {
        if !hasAccess {
            _ = try await requestAccess()
        }
    }

    // MARK: - Calendar Discovery

    /// Get all accessible calendars, filtering out problematic ones.
    ///
    /// - Returns: Array of calendars
    /// - Throws: CalendarDataAccessError if permission denied
    public func getAllCalendars() async throws -> [EKCalendar] {
        try await ensureAccess()

        let calendars = eventStore.calendars(for: .event)

        // Filter out Siri Suggestions and other problematic calendars
        // per design doc: calendars with no valid identifier can crash
        return calendars.filter { calendar in
            // Skip calendars with empty or nil identifiers
            guard !calendar.calendarIdentifier.isEmpty else {
                return false
            }

            // Skip Siri Suggestions calendar (source type = .subscribed with specific title patterns)
            if calendar.source?.sourceType == .subscribed {
                let title = calendar.title.lowercased()
                if title.contains("siri") || title.contains("suggestions") {
                    return false
                }
            }

            return true
        }
    }

    /// Get a specific calendar by identifier.
    ///
    /// - Parameter identifier: Calendar identifier
    /// - Returns: The calendar if found
    /// - Throws: CalendarDataAccessError if not found or permission denied
    public func getCalendar(identifier: String) async throws -> EKCalendar? {
        try await ensureAccess()
        return eventStore.calendar(withIdentifier: identifier)
    }

    // MARK: - Event Query

    /// Query events in a date range.
    /// EventKit automatically expands recurring events.
    ///
    /// - Parameters:
    ///   - startDate: Start of date range
    ///   - endDate: End of date range
    ///   - calendars: Optional calendar filter (nil = all calendars)
    /// - Returns: Array of events
    /// - Throws: CalendarDataAccessError if query fails
    public func getEvents(
        from startDate: Date,
        to endDate: Date,
        calendars: [EKCalendar]? = nil
    ) async throws -> [EKEvent] {
        try await ensureAccess()

        let calendarsToSearch = calendars ?? eventStore.calendars(for: .event)

        // Create predicate for date range
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: calendarsToSearch
        )

        // EventKit returns expanded recurring events
        return eventStore.events(matching: predicate)
    }

    /// Get a specific event by identifier.
    ///
    /// - Parameter identifier: Event identifier (eventIdentifier)
    /// - Returns: The event if found
    /// - Throws: CalendarDataAccessError if permission denied
    public func getEvent(identifier: String) async throws -> EKEvent? {
        try await ensureAccess()
        return eventStore.event(withIdentifier: identifier)
    }

    // MARK: - ID Extraction

    /// Extracted identity information from an EKEvent.
    public struct ExtractedEventIdentity: Sendable {
        public let eventIdentifier: String
        public let externalIdentifier: String?
        public let calendarIdentifier: String
        public let isRecurring: Bool
        public let occurrenceDate: Date?

        public init(
            eventIdentifier: String,
            externalIdentifier: String?,
            calendarIdentifier: String,
            isRecurring: Bool,
            occurrenceDate: Date?
        ) {
            self.eventIdentifier = eventIdentifier
            self.externalIdentifier = externalIdentifier
            self.calendarIdentifier = calendarIdentifier
            self.isRecurring = isRecurring
            self.occurrenceDate = occurrenceDate
        }
    }

    /// Extract all identity information from an event.
    /// Per design: capture all three IDs for multi-ID strategy.
    ///
    /// - Parameter event: The EKEvent
    /// - Returns: Extracted identity information
    public func extractIdentity(from event: EKEvent) -> ExtractedEventIdentity {
        let isRecurring = event.hasRecurrenceRules || event.occurrenceDate != event.startDate

        return ExtractedEventIdentity(
            eventIdentifier: event.eventIdentifier,
            externalIdentifier: event.calendarItemExternalIdentifier,
            calendarIdentifier: event.calendar.calendarIdentifier,
            isRecurring: isRecurring,
            occurrenceDate: isRecurring ? event.occurrenceDate : nil
        )
    }

    // MARK: - Attendee Extraction

    /// Extracted attendee information.
    public struct ExtractedAttendee: Sendable {
        public let name: String?
        public let email: String?
        public let isOrganizer: Bool
        public let isOptional: Bool
        public let participantStatus: EKParticipantStatus

        public var responseStatusString: String {
            switch participantStatus {
            case .accepted:
                return "accepted"
            case .declined:
                return "declined"
            case .tentative:
                return "tentative"
            case .pending:
                return "needs-action"
            case .unknown, .completed, .delegated, .inProcess:
                return "unknown"
            @unknown default:
                return "unknown"
            }
        }
    }

    /// Extract attendees from an event.
    ///
    /// - Parameter event: The EKEvent
    /// - Returns: Array of extracted attendee info
    public func extractAttendees(from event: EKEvent) -> [ExtractedAttendee] {
        guard let attendees = event.attendees else {
            return []
        }

        return attendees.map { participant in
            ExtractedAttendee(
                name: participant.name,
                email: extractEmail(from: participant),
                isOrganizer: participant.isCurrentUser && event.organizer == participant,
                isOptional: participant.participantRole == .optional,
                participantStatus: participant.participantStatus
            )
        }
    }

    /// Extract organizer information.
    ///
    /// - Parameter event: The EKEvent
    /// - Returns: Organizer as ExtractedAttendee, or nil if no organizer
    public func extractOrganizer(from event: EKEvent) -> ExtractedAttendee? {
        guard let organizer = event.organizer else {
            return nil
        }

        return ExtractedAttendee(
            name: organizer.name,
            email: extractEmail(from: organizer),
            isOrganizer: true,
            isOptional: false,
            participantStatus: organizer.participantStatus
        )
    }

    /// Extract email from participant.
    private func extractEmail(from participant: EKParticipant) -> String? {
        // URL format is typically: mailto:email@example.com
        let url = participant.url
        let urlString = url.absoluteString

        if urlString.lowercased().hasPrefix("mailto:") {
            return String(urlString.dropFirst(7))
        }

        return nil
    }

    // MARK: - Reminder Access

    /// Request reminder access permission (separate from calendar).
    public func requestReminderAccess() async throws -> Bool {
        if #available(macOS 14.0, *) {
            return try await eventStore.requestFullAccessToReminders()
        } else {
            return try await eventStore.requestAccess(to: .reminder)
        }
    }

    /// Get all reminder lists.
    public func getReminderLists() async throws -> [EKCalendar] {
        // Note: Reminder access requires separate permission
        return eventStore.calendars(for: .reminder)
    }

    /// Extracted reminder information (Sendable).
    public struct ExtractedReminder: Sendable {
        public let calendarItemIdentifier: String
        public let calendarItemExternalIdentifier: String?
        public let calendarIdentifier: String
        public let title: String?
        public let notes: String?
        public let isCompleted: Bool
        public let completionDate: Date?
        public let dueDate: Date?
        public let priority: Int
        public let creationDate: Date?
        public let lastModifiedDate: Date?
    }

    /// Get reminders in a date range.
    ///
    /// - Parameters:
    ///   - startDate: Optional start date
    ///   - endDate: Optional end date
    ///   - calendars: Optional calendar filter
    /// - Returns: Array of extracted reminder info
    public func getReminders(
        from startDate: Date? = nil,
        to endDate: Date? = nil,
        calendars: [EKCalendar]? = nil
    ) async throws -> [ExtractedReminder] {
        let predicate: NSPredicate

        if let start = startDate, let end = endDate {
            predicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: start,
                ending: end,
                calendars: calendars
            )
        } else {
            predicate = eventStore.predicateForReminders(in: calendars)
        }

        // Extract Sendable data from reminders immediately in the callback
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let extracted = (reminders ?? []).map { reminder in
                    ExtractedReminder(
                        calendarItemIdentifier: reminder.calendarItemIdentifier,
                        calendarItemExternalIdentifier: reminder.calendarItemExternalIdentifier,
                        calendarIdentifier: reminder.calendar?.calendarIdentifier ?? "",
                        title: reminder.title,
                        notes: reminder.notes,
                        isCompleted: reminder.isCompleted,
                        completionDate: reminder.completionDate,
                        dueDate: reminder.dueDateComponents?.date,
                        priority: reminder.priority,
                        creationDate: reminder.creationDate,
                        lastModifiedDate: reminder.lastModifiedDate
                    )
                }
                continuation.resume(returning: extracted)
            }
        }
    }

    // MARK: - Change Notification

    /// Subscribe to calendar change notifications.
    ///
    /// - Parameter handler: Closure called when changes occur
    /// - Returns: Notification observation token (keep reference to continue receiving)
    public func observeChanges(
        handler: @escaping @Sendable () -> Void
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { _ in
            handler()
        }
    }

    // MARK: - Event Transformation

    /// Transform an EKEvent to StoredEvent for database storage.
    /// Uses the CalendarIdGenerator for stable ID generation.
    ///
    /// - Parameters:
    ///   - event: The EKEvent to transform
    ///   - idGenerator: ID generator for stable IDs
    /// - Returns: StoredEvent ready for database
    public func transformToStoredEvent(
        _ event: EKEvent,
        using idGenerator: CalendarIdGenerator
    ) -> StoredEvent {
        let identity = extractIdentity(from: event)

        // Generate stable public ID
        let publicId = idGenerator.generatePublicId(
            identity: EventKitIdentity(
                eventIdentifier: identity.eventIdentifier,
                externalIdentifier: identity.externalIdentifier,
                calendarIdentifier: identity.calendarIdentifier
            ),
            summary: event.title,
            startDate: event.startDate,
            occurrenceDate: identity.occurrenceDate
        )

        // Extract recurrence rule string if present
        var rruleString: String? = nil
        if let rules = event.recurrenceRules, let firstRule = rules.first {
            // Simple RRULE representation
            rruleString = "FREQ=\(frequencyString(firstRule.frequency))"
            if let interval = firstRule.interval as Int?, interval > 1 {
                rruleString! += ";INTERVAL=\(interval)"
            }
        }

        let now = Int(Date().timeIntervalSince1970)

        return StoredEvent(
            id: publicId,
            eventkitId: identity.eventIdentifier,
            externalId: identity.externalIdentifier,
            calendarId: identity.calendarIdentifier,
            summary: event.title,
            eventDescription: event.notes,
            location: event.location,
            url: event.url?.absoluteString,
            startDateUtc: Int(event.startDate.timeIntervalSince1970),
            endDateUtc: Int(event.endDate.timeIntervalSince1970),
            startTimezone: event.timeZone?.identifier,
            endTimezone: event.timeZone?.identifier,
            isAllDay: event.isAllDay,
            recurrenceRule: rruleString,
            masterEventId: identity.isRecurring ? nil : nil, // Would need parent tracking
            occurrenceDate: identity.occurrenceDate.map { Int($0.timeIntervalSince1970) },
            status: statusString(event.status),
            createdAt: event.creationDate.map { Int($0.timeIntervalSince1970) },
            updatedAt: event.lastModifiedDate.map { Int($0.timeIntervalSince1970) },
            syncedAt: now
        )
    }

    /// Transform an EKCalendar to StoredCalendar.
    public func transformToStoredCalendar(
        _ calendar: EKCalendar,
        using idGenerator: CalendarIdGenerator
    ) -> StoredCalendar {
        let calendarId = idGenerator.generateCalendarId(
            calendarIdentifier: calendar.calendarIdentifier,
            title: calendar.title,
            source: calendar.source?.title
        )

        let now = Int(Date().timeIntervalSince1970)

        return StoredCalendar(
            id: calendarId,
            eventkitId: calendar.calendarIdentifier,
            title: calendar.title,
            sourceType: sourceTypeString(calendar.source?.sourceType),
            color: hexColor(from: calendar.cgColor),
            isSubscribed: calendar.isSubscribed,
            isImmutable: calendar.isImmutable,
            syncedAt: now
        )
    }

    // MARK: - Helpers

    private func frequencyString(_ frequency: EKRecurrenceFrequency) -> String {
        switch frequency {
        case .daily: return "DAILY"
        case .weekly: return "WEEKLY"
        case .monthly: return "MONTHLY"
        case .yearly: return "YEARLY"
        @unknown default: return "UNKNOWN"
        }
    }

    private func statusString(_ status: EKEventStatus) -> String? {
        switch status {
        case .confirmed: return "confirmed"
        case .tentative: return "tentative"
        case .canceled: return "cancelled"
        case .none: return nil
        @unknown default: return nil
        }
    }

    private func sourceTypeString(_ sourceType: EKSourceType?) -> String? {
        guard let sourceType = sourceType else { return nil }
        switch sourceType {
        case .local: return "local"
        case .exchange: return "exchange"
        case .calDAV: return "caldav"
        case .mobileMe: return "mobileme"
        case .subscribed: return "subscribed"
        case .birthdays: return "birthdays"
        @unknown default: return "unknown"
        }
    }

    private func hexColor(from cgColor: CGColor?) -> String? {
        guard let color = cgColor,
              let components = color.components,
              components.count >= 3 else {
            return nil
        }

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
