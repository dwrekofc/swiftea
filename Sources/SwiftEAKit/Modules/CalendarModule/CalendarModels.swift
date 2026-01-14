// CalendarModels.swift - Data models for Calendar module
//
// Codable structs that map to GRDB database tables and provide
// JSON export capabilities for ClaudEA consumption.

import Foundation
import GRDB

// MARK: - Stored Event Identity

/// Multi-ID strategy for stable event references across EventKit sync operations.
/// EventKit provides multiple identifiers with different stability characteristics.
public struct StoredEventIdentity: Codable, Hashable, Sendable {
    /// EKEvent.eventIdentifier - fast local lookup, may change after sync
    public var eventIdentifier: String?

    /// EKEvent.calendarItemExternalIdentifier - most stable for CalDAV/iCloud, can be nil before sync
    public var externalIdentifier: String?

    /// EKCalendar.calendarIdentifier - stable calendar-level ID
    public var calendarIdentifier: String

    public init(
        eventIdentifier: String? = nil,
        externalIdentifier: String? = nil,
        calendarIdentifier: String
    ) {
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.calendarIdentifier = calendarIdentifier
    }
}

// MARK: - Stored Calendar

/// Represents a calendar source (Work, Personal, iCloud, etc.)
public struct StoredCalendar: Codable, Sendable, FetchableRecord, PersistableRecord {
    /// Stable ID (calendarIdentifier from EventKit)
    public var id: String

    /// EventKit identifier for reverse lookup
    public var eventkitId: String?

    /// Calendar display title
    public var title: String

    /// Source type: local, iCloud, Exchange, caldav, etc.
    public var sourceType: String?

    /// Hex color code for display
    public var color: String?

    /// Whether this is a subscribed (read-only) calendar
    public var isSubscribed: Bool

    /// Whether this calendar is immutable
    public var isImmutable: Bool

    /// Last sync timestamp
    public var syncedAt: Int?

    public static var databaseTableName: String { "calendars" }

    enum CodingKeys: String, CodingKey {
        case id
        case eventkitId = "eventkit_id"
        case title
        case sourceType = "source_type"
        case color
        case isSubscribed = "is_subscribed"
        case isImmutable = "is_immutable"
        case syncedAt = "synced_at"
    }

    public init(
        id: String,
        eventkitId: String? = nil,
        title: String,
        sourceType: String? = nil,
        color: String? = nil,
        isSubscribed: Bool = false,
        isImmutable: Bool = false,
        syncedAt: Int? = nil
    ) {
        self.id = id
        self.eventkitId = eventkitId
        self.title = title
        self.sourceType = sourceType
        self.color = color
        self.isSubscribed = isSubscribed
        self.isImmutable = isImmutable
        self.syncedAt = syncedAt
    }
}

// MARK: - Event Status

/// Event confirmation status
public enum EventStatus: String, Codable, Sendable {
    case confirmed
    case tentative
    case cancelled
}

// MARK: - Stored Event

/// Represents a calendar event (single or recurring instance).
/// Schema follows design doc with multi-ID strategy and UTC timestamps.
public struct StoredEvent: Codable, Sendable, FetchableRecord, PersistableRecord {
    /// Stable public ID (external_id or hash fallback)
    public var id: String

    /// EKEvent.eventIdentifier for fast local lookup
    public var eventkitId: String?

    /// calendarItemExternalIdentifier - most stable, can be NULL
    public var externalId: String?

    /// Reference to calendar
    public var calendarId: String

    /// Event title/summary
    public var summary: String?

    /// Event description/notes
    public var eventDescription: String?

    /// Location string
    public var location: String?

    /// Associated URL
    public var url: String?

    /// Start time as Unix timestamp in UTC
    public var startDateUtc: Int

    /// End time as Unix timestamp in UTC
    public var endDateUtc: Int

    /// Original timezone for display (e.g., "America/New_York")
    public var startTimezone: String?

    /// Original end timezone for display
    public var endTimezone: String?

    /// Whether this is an all-day event
    public var isAllDay: Bool

    /// RRULE string for recurring events (reference only)
    public var recurrenceRule: String?

    /// Reference to master event for recurring instances
    public var masterEventId: String?

    /// Occurrence date for recurring instances (combines with UID for unique ID)
    public var occurrenceDate: Int?

    /// Event status
    public var status: String?

    /// Creation timestamp
    public var createdAt: Int?

    /// Last modification timestamp
    public var updatedAt: Int?

    /// Last sync timestamp
    public var syncedAt: Int?

    public static var databaseTableName: String { "events" }

    enum CodingKeys: String, CodingKey {
        case id
        case eventkitId = "eventkit_id"
        case externalId = "external_id"
        case calendarId = "calendar_id"
        case summary
        case eventDescription = "description"
        case location
        case url
        case startDateUtc = "start_date_utc"
        case endDateUtc = "end_date_utc"
        case startTimezone = "start_timezone"
        case endTimezone = "end_timezone"
        case isAllDay = "is_all_day"
        case recurrenceRule = "recurrence_rule"
        case masterEventId = "master_event_id"
        case occurrenceDate = "occurrence_date"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }

    public init(
        id: String,
        eventkitId: String? = nil,
        externalId: String? = nil,
        calendarId: String,
        summary: String? = nil,
        eventDescription: String? = nil,
        location: String? = nil,
        url: String? = nil,
        startDateUtc: Int,
        endDateUtc: Int,
        startTimezone: String? = nil,
        endTimezone: String? = nil,
        isAllDay: Bool = false,
        recurrenceRule: String? = nil,
        masterEventId: String? = nil,
        occurrenceDate: Int? = nil,
        status: String? = nil,
        createdAt: Int? = nil,
        updatedAt: Int? = nil,
        syncedAt: Int? = nil
    ) {
        self.id = id
        self.eventkitId = eventkitId
        self.externalId = externalId
        self.calendarId = calendarId
        self.summary = summary
        self.eventDescription = eventDescription
        self.location = location
        self.url = url
        self.startDateUtc = startDateUtc
        self.endDateUtc = endDateUtc
        self.startTimezone = startTimezone
        self.endTimezone = endTimezone
        self.isAllDay = isAllDay
        self.recurrenceRule = recurrenceRule
        self.masterEventId = masterEventId
        self.occurrenceDate = occurrenceDate
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncedAt = syncedAt
    }
}

// MARK: - Attendee Response Status

/// Attendee response status per iCalendar spec
public enum AttendeeResponseStatus: String, Codable, Sendable {
    case accepted
    case declined
    case tentative
    case needsAction = "needs-action"
}

// MARK: - Stored Attendee

/// Represents an event attendee with response status
public struct StoredAttendee: Codable, Sendable, FetchableRecord, PersistableRecord {
    /// Auto-increment primary key
    public var id: Int64?

    /// Reference to event
    public var eventId: String

    /// Attendee display name
    public var name: String?

    /// Attendee email address
    public var email: String?

    /// Response status
    public var responseStatus: String?

    /// Whether this attendee is the organizer
    public var isOrganizer: Bool

    /// Whether this attendee is optional
    public var isOptional: Bool

    public static var databaseTableName: String { "attendees" }

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case name
        case email
        case responseStatus = "response_status"
        case isOrganizer = "is_organizer"
        case isOptional = "is_optional"
    }

    public init(
        id: Int64? = nil,
        eventId: String,
        name: String? = nil,
        email: String? = nil,
        responseStatus: String? = nil,
        isOrganizer: Bool = false,
        isOptional: Bool = false
    ) {
        self.id = id
        self.eventId = eventId
        self.name = name
        self.email = email
        self.responseStatus = responseStatus
        self.isOrganizer = isOrganizer
        self.isOptional = isOptional
    }
}

// MARK: - Stored Reminder

/// Represents a reminder (task) from EventKit
public struct StoredReminder: Codable, Sendable, FetchableRecord, PersistableRecord {
    /// Stable ID
    public var id: String

    /// EventKit identifier
    public var eventkitId: String?

    /// Reference to calendar
    public var calendarId: String?

    /// Reminder title
    public var title: String?

    /// Notes/description
    public var notes: String?

    /// Due date as Unix timestamp
    public var dueDate: Int?

    /// Priority (0-9, 0 = no priority)
    public var priority: Int?

    /// Whether the reminder is completed
    public var isCompleted: Bool

    /// Completion timestamp
    public var completedAt: Int?

    /// Last sync timestamp
    public var syncedAt: Int?

    public static var databaseTableName: String { "reminders" }

    enum CodingKeys: String, CodingKey {
        case id
        case eventkitId = "eventkit_id"
        case calendarId = "calendar_id"
        case title
        case notes
        case dueDate = "due_date"
        case priority
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case syncedAt = "synced_at"
    }

    public init(
        id: String,
        eventkitId: String? = nil,
        calendarId: String? = nil,
        title: String? = nil,
        notes: String? = nil,
        dueDate: Int? = nil,
        priority: Int? = nil,
        isCompleted: Bool = false,
        completedAt: Int? = nil,
        syncedAt: Int? = nil
    ) {
        self.id = id
        self.eventkitId = eventkitId
        self.calendarId = calendarId
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priority = priority
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.syncedAt = syncedAt
    }
}

// MARK: - Calendar Sync Status

/// Tracks sync state for the calendar module
public struct CalendarSyncStatus: Codable, Sendable, FetchableRecord, PersistableRecord {
    /// Status key
    public var key: String

    /// Status value
    public var value: String

    /// Last update timestamp
    public var updatedAt: Int

    public static var databaseTableName: String { "sync_status" }

    enum CodingKeys: String, CodingKey {
        case key
        case value
        case updatedAt = "updated_at"
    }

    public init(key: String, value: String, updatedAt: Int) {
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}

// MARK: - Sync Status Keys

extension CalendarSyncStatus {
    /// Well-known sync status keys
    public enum Key {
        public static let state = "sync_state"
        public static let lastSyncTime = "last_sync_time"
        public static let lastSyncStartTime = "last_sync_start_time"
        public static let lastSyncEndTime = "last_sync_end_time"
        public static let lastSyncError = "last_sync_error"
        public static let eventsAdded = "events_added"
        public static let eventsUpdated = "events_updated"
        public static let eventsDeleted = "events_deleted"
        public static let syncDuration = "sync_duration"
        public static let dateRangeStart = "date_range_start"
        public static let dateRangeEnd = "date_range_end"
    }

    /// Sync state values
    public enum State: String {
        case idle
        case running
        case success
        case failed
    }
}

// MARK: - JSON Export Types (ClaudEA Contract)

/// JSON envelope for ClaudEA consumption
public struct CalendarExportEnvelope<T: Codable>: Codable {
    public let version: String
    public let query: String?
    public let total: Int
    public let items: [T]

    public init(version: String = "1.0", query: String? = nil, items: [T]) {
        self.version = version
        self.query = query
        self.total = items.count
        self.items = items
    }
}

/// Event item for JSON export per ClaudEA contract
public struct ExportableEvent: Codable, Sendable {
    public let id: String
    public let title: String?
    public let calendar: String
    public let calendarId: String
    public let start: String
    public let end: String
    public let isAllDay: Bool
    public let location: String?
    public let description: String?
    public let url: String?
    public let status: String?
    public let isRecurring: Bool
    public let attendees: [ExportableAttendee]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case calendar
        case calendarId = "calendar_id"
        case start
        case end
        case isAllDay = "is_all_day"
        case location
        case description
        case url
        case status
        case isRecurring = "is_recurring"
        case attendees
    }

    public init(
        id: String,
        title: String?,
        calendar: String,
        calendarId: String,
        start: String,
        end: String,
        isAllDay: Bool,
        location: String?,
        description: String?,
        url: String?,
        status: String?,
        isRecurring: Bool,
        attendees: [ExportableAttendee]
    ) {
        self.id = id
        self.title = title
        self.calendar = calendar
        self.calendarId = calendarId
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.description = description
        self.url = url
        self.status = status
        self.isRecurring = isRecurring
        self.attendees = attendees
    }
}

/// Attendee for JSON export
public struct ExportableAttendee: Codable, Sendable {
    public let name: String?
    public let email: String?
    public let responseStatus: String?
    public let isOrganizer: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case email
        case responseStatus = "response_status"
        case isOrganizer = "is_organizer"
    }

    public init(
        name: String?,
        email: String?,
        responseStatus: String?,
        isOrganizer: Bool
    ) {
        self.name = name
        self.email = email
        self.responseStatus = responseStatus
        self.isOrganizer = isOrganizer
    }
}
