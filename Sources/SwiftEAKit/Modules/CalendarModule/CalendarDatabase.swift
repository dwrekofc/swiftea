// CalendarDatabase.swift - GRDB-backed calendar database
//
// Uses GRDB.swift for type-safe SQLite access with FTS5 support.
// Schema follows design doc: UTC timestamps, multi-ID strategy, synchronized FTS.

import Foundation
import GRDB

// MARK: - Errors

/// Errors that can occur during calendar database operations
public enum CalendarDatabaseError: Error, LocalizedError {
    case connectionFailed(underlying: Error)
    case migrationFailed(underlying: Error)
    case queryFailed(underlying: Error)
    case notInitialized

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let error):
            return "Failed to connect to calendar database: \(error.localizedDescription)"
        case .migrationFailed(let error):
            return "Failed to run database migration: \(error.localizedDescription)"
        case .queryFailed(let error):
            return "Database query failed: \(error.localizedDescription)"
        case .notInitialized:
            return "Calendar database not initialized"
        }
    }
}

// MARK: - Calendar Database

/// Manages the GRDB database for calendar data
public final class CalendarDatabase: @unchecked Sendable {
    private var dbQueue: DatabaseQueue?
    private let databasePath: String

    public init(databasePath: String) {
        self.databasePath = databasePath
    }

    /// Initialize the database connection and run migrations
    public func initialize() throws {
        do {
            var config = Configuration()
            // Enable WAL mode for concurrent access
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode=WAL")
                try db.execute(sql: "PRAGMA busy_timeout=5000")
            }

            dbQueue = try DatabaseQueue(path: databasePath, configuration: config)

            try runMigrations()
        } catch {
            throw CalendarDatabaseError.connectionFailed(underlying: error)
        }
    }

    /// Close the database connection
    public func close() {
        dbQueue = nil
    }

    /// Access to the database queue for direct queries
    public var queue: DatabaseQueue? {
        dbQueue
    }

    // MARK: - Migrations

    private func runMigrations() throws {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        var migrator = DatabaseMigrator()

        #if DEBUG
        // Erase database on schema change during development
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        // v1: Initial schema
        migrator.registerMigration("v1_initial") { db in
            // Calendars table
            try db.create(table: "calendars") { t in
                t.column("id", .text).primaryKey()
                t.column("eventkit_id", .text)
                t.column("title", .text).notNull()
                t.column("source_type", .text)
                t.column("color", .text)
                t.column("is_subscribed", .boolean).notNull().defaults(to: false)
                t.column("is_immutable", .boolean).notNull().defaults(to: false)
                t.column("synced_at", .integer)
            }

            // Events table with multi-ID strategy and UTC timestamps
            try db.create(table: "events") { t in
                t.column("id", .text).primaryKey()
                t.column("eventkit_id", .text)
                t.column("external_id", .text)
                t.column("calendar_id", .text).notNull()
                    .references("calendars", onDelete: .cascade)
                t.column("summary", .text)
                t.column("description", .text)
                t.column("location", .text)
                t.column("url", .text)
                // UTC timestamps per design
                t.column("start_date_utc", .integer).notNull()
                t.column("end_date_utc", .integer).notNull()
                // Original timezones for display
                t.column("start_timezone", .text)
                t.column("end_timezone", .text)
                t.column("is_all_day", .boolean).notNull().defaults(to: false)
                // Recurrence handling
                t.column("recurrence_rule", .text)
                t.column("master_event_id", .text)
                t.column("occurrence_date", .integer)
                t.column("status", .text)
                t.column("created_at", .integer)
                t.column("updated_at", .integer)
                t.column("synced_at", .integer)
            }

            // Attendees table with CASCADE delete
            try db.create(table: "attendees") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("event_id", .text).notNull()
                    .references("events", onDelete: .cascade)
                t.column("name", .text)
                t.column("email", .text)
                t.column("response_status", .text)
                t.column("is_organizer", .boolean).notNull().defaults(to: false)
                t.column("is_optional", .boolean).notNull().defaults(to: false)
            }

            // Reminders table (for future use)
            try db.create(table: "reminders") { t in
                t.column("id", .text).primaryKey()
                t.column("eventkit_id", .text)
                t.column("calendar_id", .text)
                t.column("title", .text)
                t.column("notes", .text)
                t.column("due_date", .integer)
                t.column("priority", .integer)
                t.column("is_completed", .boolean).notNull().defaults(to: false)
                t.column("completed_at", .integer)
                t.column("synced_at", .integer)
            }

            // Sync status table
            try db.create(table: "sync_status") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
                t.column("updated_at", .integer).notNull()
            }

            // Optimized indexes per design
            // Date range queries (common for calendar views)
            try db.create(
                index: "idx_events_date_range",
                on: "events",
                columns: ["calendar_id", "start_date_utc", "end_date_utc"]
            )

            // External ID lookups (partial index for non-null values)
            try db.execute(sql: """
                CREATE INDEX idx_events_external_id
                ON events(external_id)
                WHERE external_id IS NOT NULL
                """)

            // Recurring event lookups (partial index)
            try db.execute(sql: """
                CREATE INDEX idx_events_master
                ON events(master_event_id)
                WHERE master_event_id IS NOT NULL
                """)

            // Sync queries
            try db.create(
                index: "idx_events_updated",
                on: "events",
                columns: ["updated_at"]
            )

            // Attendee lookups
            try db.create(
                index: "idx_attendees_event_id",
                on: "attendees",
                columns: ["event_id"]
            )

            try db.create(
                index: "idx_attendees_email",
                on: "attendees",
                columns: ["email"]
            )
        }

        // v2: Add FTS5 with external content table
        migrator.registerMigration("v2_add_fts") { db in
            // Create FTS5 table synchronized with events table
            // Uses external content table pattern - FTS reads from events table
            try db.execute(sql: """
                CREATE VIRTUAL TABLE events_fts USING fts5(
                    summary,
                    description,
                    location,
                    content='events',
                    content_rowid='rowid',
                    tokenize='porter unicode61'
                )
                """)

            // Triggers to keep FTS in sync with events table
            try db.execute(sql: """
                CREATE TRIGGER events_fts_ai AFTER INSERT ON events BEGIN
                    INSERT INTO events_fts(rowid, summary, description, location)
                    VALUES (NEW.rowid, NEW.summary, NEW.description, NEW.location);
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER events_fts_ad AFTER DELETE ON events BEGIN
                    INSERT INTO events_fts(events_fts, rowid, summary, description, location)
                    VALUES ('delete', OLD.rowid, OLD.summary, OLD.description, OLD.location);
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER events_fts_au AFTER UPDATE ON events BEGIN
                    INSERT INTO events_fts(events_fts, rowid, summary, description, location)
                    VALUES ('delete', OLD.rowid, OLD.summary, OLD.description, OLD.location);
                    INSERT INTO events_fts(rowid, summary, description, location)
                    VALUES (NEW.rowid, NEW.summary, NEW.description, NEW.location);
                END
                """)
        }

        do {
            try migrator.migrate(dbQueue)
        } catch {
            throw CalendarDatabaseError.migrationFailed(underlying: error)
        }
    }

    // MARK: - Calendar Operations

    /// Insert or update a calendar
    public func upsertCalendar(_ calendar: StoredCalendar) throws {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        try dbQueue.write { db in
            try calendar.save(db)
        }
    }

    /// Get all calendars
    public func getAllCalendars() throws -> [StoredCalendar] {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        return try dbQueue.read { db in
            try StoredCalendar.fetchAll(db)
        }
    }

    /// Get a calendar by ID
    public func getCalendar(id: String) throws -> StoredCalendar? {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        return try dbQueue.read { db in
            try StoredCalendar.fetchOne(db, key: id)
        }
    }

    // MARK: - Event Operations

    /// Insert or update an event
    public func upsertEvent(_ event: StoredEvent) throws {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        try dbQueue.write { db in
            try event.save(db)
        }
    }

    /// Insert or update multiple events in a single transaction
    public func upsertEvents(_ events: [StoredEvent]) throws {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        try dbQueue.write { db in
            for event in events {
                try event.save(db)
            }
        }
    }

    /// Get an event by ID
    public func getEvent(id: String) throws -> StoredEvent? {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        return try dbQueue.read { db in
            try StoredEvent.fetchOne(db, key: id)
        }
    }

    /// Get an event by EventKit ID (for fast local lookup)
    public func getEvent(eventkitId: String) throws -> StoredEvent? {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        return try dbQueue.read { db in
            try StoredEvent
                .filter(Column("eventkit_id") == eventkitId)
                .fetchOne(db)
        }
    }

    /// Get events in a date range
    public func getEvents(
        from startDate: Date,
        to endDate: Date,
        calendarId: String? = nil,
        limit: Int = 1000
    ) throws -> [StoredEvent] {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        let startTimestamp = Int(startDate.timeIntervalSince1970)
        let endTimestamp = Int(endDate.timeIntervalSince1970)

        return try dbQueue.read { db in
            var query = StoredEvent
                .filter(Column("start_date_utc") >= startTimestamp)
                .filter(Column("end_date_utc") <= endTimestamp)

            if let calendarId = calendarId {
                query = query.filter(Column("calendar_id") == calendarId)
            }

            return try query
                .order(Column("start_date_utc"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Get upcoming events from now
    public func getUpcomingEvents(limit: Int = 50) throws -> [StoredEvent] {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)

        return try dbQueue.read { db in
            try StoredEvent
                .filter(Column("start_date_utc") >= now)
                .order(Column("start_date_utc"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Search events using FTS
    public func searchEvents(query: String, limit: Int = 50) throws -> [StoredEvent] {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        return try dbQueue.read { db in
            let sql = """
                SELECT e.* FROM events e
                JOIN events_fts fts ON e.rowid = fts.rowid
                WHERE events_fts MATCH ?
                ORDER BY bm25(events_fts)
                LIMIT ?
                """
            return try StoredEvent.fetchAll(db, sql: sql, arguments: [query, limit])
        }
    }

    /// Delete an event
    public func deleteEvent(id: String) throws -> Bool {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        return try dbQueue.write { db in
            try StoredEvent.deleteOne(db, key: id)
        }
    }

    /// Delete events not in the given ID set (for sync cleanup)
    public func deleteEventsNotIn(ids: Set<String>, forCalendar calendarId: String) throws -> Int {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        return try dbQueue.write { db in
            let deletedCount = try StoredEvent
                .filter(Column("calendar_id") == calendarId)
                .filter(!ids.contains(Column("id")))
                .deleteAll(db)
            return deletedCount
        }
    }

    // MARK: - Attendee Operations

    /// Insert or update an attendee
    public func upsertAttendee(_ attendee: StoredAttendee) throws {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        try dbQueue.write { db in
            try attendee.save(db)
        }
    }

    /// Get attendees for an event
    public func getAttendees(eventId: String) throws -> [StoredAttendee] {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        return try dbQueue.read { db in
            try StoredAttendee
                .filter(Column("event_id") == eventId)
                .fetchAll(db)
        }
    }

    /// Delete all attendees for an event
    public func deleteAttendees(eventId: String) throws {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        _ = try dbQueue.write { db in
            try StoredAttendee
                .filter(Column("event_id") == eventId)
                .deleteAll(db)
        }
    }

    /// Replace attendees for an event (delete existing, insert new)
    public func replaceAttendees(eventId: String, attendees: [StoredAttendee]) throws {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        try dbQueue.write { db in
            // Delete existing attendees
            try StoredAttendee
                .filter(Column("event_id") == eventId)
                .deleteAll(db)

            // Insert new attendees
            for attendee in attendees {
                var mutableAttendee = attendee
                mutableAttendee.eventId = eventId
                try mutableAttendee.insert(db)
            }
        }
    }

    // MARK: - Reminder Operations

    /// Insert or update a reminder
    public func upsertReminder(_ reminder: StoredReminder) throws {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        try dbQueue.write { db in
            try reminder.save(db)
        }
    }

    /// Get all reminders
    public func getAllReminders(includeCompleted: Bool = false) throws -> [StoredReminder] {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        return try dbQueue.read { db in
            var query = StoredReminder.all()
            if !includeCompleted {
                query = query.filter(Column("is_completed") == false)
            }
            return try query.fetchAll(db)
        }
    }

    // MARK: - Sync Status Operations

    /// Get a sync status value
    public func getSyncStatus(key: String) throws -> String? {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        return try dbQueue.read { db in
            let status = try CalendarSyncStatus.fetchOne(db, key: key)
            return status?.value
        }
    }

    /// Set a sync status value
    public func setSyncStatus(key: String, value: String) throws {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        let now = Int(Date().timeIntervalSince1970)
        let status = CalendarSyncStatus(key: key, value: value, updatedAt: now)

        try dbQueue.write { db in
            try status.save(db)
        }
    }

    /// Get last sync timestamp
    public func getLastSyncTime() throws -> Date? {
        guard let value = try getSyncStatus(key: CalendarSyncStatus.Key.lastSyncTime),
              let timestamp = Double(value) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// Set last sync timestamp
    public func setLastSyncTime(_ date: Date) throws {
        try setSyncStatus(
            key: CalendarSyncStatus.Key.lastSyncTime,
            value: String(date.timeIntervalSince1970)
        )
    }

    // MARK: - Statistics

    /// Get count of events
    public func getEventCount() throws -> Int {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        return try dbQueue.read { db in
            try StoredEvent.fetchCount(db)
        }
    }

    /// Get count of calendars
    public func getCalendarCount() throws -> Int {
        guard let dbQueue = dbQueue else {
            throw CalendarDatabaseError.notInitialized
        }

        return try dbQueue.read { db in
            try StoredCalendar.fetchCount(db)
        }
    }

    // MARK: - Export Support

    /// Get events with attendees for export
    public func getEventsWithAttendees(
        from startDate: Date,
        to endDate: Date,
        calendarId: String? = nil
    ) throws -> [(StoredEvent, [StoredAttendee])] {
        let events = try getEvents(from: startDate, to: endDate, calendarId: calendarId)
        var results: [(StoredEvent, [StoredAttendee])] = []

        for event in events {
            let attendees = try getAttendees(eventId: event.id)
            results.append((event, attendees))
        }

        return results
    }
}
