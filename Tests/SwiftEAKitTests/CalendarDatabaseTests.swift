import XCTest
@testable import SwiftEAKit

final class CalendarDatabaseTests: XCTestCase {
    var testDir: String!
    var database: CalendarDatabase!

    override func setUp() {
        super.setUp()
        testDir = NSTemporaryDirectory() + "swiftea-caldb-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)

        let dbPath = (testDir as NSString).appendingPathComponent("calendar.db")
        database = CalendarDatabase(databasePath: dbPath)
    }

    override func tearDown() {
        database.close()
        try? FileManager.default.removeItem(atPath: testDir)
        database = nil
        super.tearDown()
    }

    // MARK: - Initialization

    func testInitializeCreatesDatabase() throws {
        try database.initialize()

        let dbPath = (testDir as NSString).appendingPathComponent("calendar.db")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath))
    }

    func testInitializeTwiceSucceeds() throws {
        try database.initialize()
        try database.initialize() // Should not throw - idempotent
    }

    // MARK: - Calendar CRUD

    func testUpsertAndGetCalendar() throws {
        try database.initialize()

        let calendar = StoredCalendar(
            id: "cal-work-123",
            eventkitId: "ek-work-123",
            title: "Work Calendar",
            sourceType: "iCloud",
            color: "#FF5733",
            isSubscribed: false,
            isImmutable: false,
            syncedAt: Int(Date().timeIntervalSince1970)
        )

        try database.upsertCalendar(calendar)

        let retrieved = try database.getCalendar(id: "cal-work-123")

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, "cal-work-123")
        XCTAssertEqual(retrieved?.eventkitId, "ek-work-123")
        XCTAssertEqual(retrieved?.title, "Work Calendar")
        XCTAssertEqual(retrieved?.sourceType, "iCloud")
        XCTAssertEqual(retrieved?.color, "#FF5733")
        XCTAssertEqual(retrieved?.isSubscribed, false)
        XCTAssertEqual(retrieved?.isImmutable, false)
    }

    func testGetAllCalendars() throws {
        try database.initialize()

        let cal1 = StoredCalendar(id: "cal-1", title: "Personal")
        let cal2 = StoredCalendar(id: "cal-2", title: "Work")
        let cal3 = StoredCalendar(id: "cal-3", title: "Family", isSubscribed: true)

        try database.upsertCalendar(cal1)
        try database.upsertCalendar(cal2)
        try database.upsertCalendar(cal3)

        let calendars = try database.getAllCalendars()

        XCTAssertEqual(calendars.count, 3)
    }

    func testCalendarUpsertUpdatesExisting() throws {
        try database.initialize()

        let calendar1 = StoredCalendar(id: "cal-update", title: "Original Title")
        try database.upsertCalendar(calendar1)

        let calendar2 = StoredCalendar(id: "cal-update", title: "Updated Title", color: "#AABBCC")
        try database.upsertCalendar(calendar2)

        let retrieved = try database.getCalendar(id: "cal-update")

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.title, "Updated Title")
        XCTAssertEqual(retrieved?.color, "#AABBCC")
    }

    // MARK: - Event CRUD

    func testUpsertAndGetEvent() throws {
        try database.initialize()

        // First create a calendar (required for foreign key)
        let calendar = StoredCalendar(id: "cal-test", title: "Test Calendar")
        try database.upsertCalendar(calendar)

        let event = StoredEvent(
            id: "event-123",
            eventkitId: "ek-event-123",
            externalId: "external-123",
            calendarId: "cal-test",
            summary: "Team Standup",
            eventDescription: "Daily sync meeting",
            location: "Conference Room A",
            url: "https://meet.example.com/standup",
            startDateUtc: 1736150400, // 2025-01-06 10:00 UTC
            endDateUtc: 1736154000,   // 2025-01-06 11:00 UTC
            startTimezone: "America/New_York",
            endTimezone: "America/New_York",
            isAllDay: false,
            recurrenceRule: "FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR",
            masterEventId: nil,
            occurrenceDate: nil,
            status: "confirmed",
            createdAt: Int(Date().timeIntervalSince1970),
            updatedAt: Int(Date().timeIntervalSince1970),
            syncedAt: Int(Date().timeIntervalSince1970)
        )

        try database.upsertEvent(event)

        let retrieved = try database.getEvent(id: "event-123")

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, "event-123")
        XCTAssertEqual(retrieved?.eventkitId, "ek-event-123")
        XCTAssertEqual(retrieved?.externalId, "external-123")
        XCTAssertEqual(retrieved?.calendarId, "cal-test")
        XCTAssertEqual(retrieved?.summary, "Team Standup")
        XCTAssertEqual(retrieved?.eventDescription, "Daily sync meeting")
        XCTAssertEqual(retrieved?.location, "Conference Room A")
        XCTAssertEqual(retrieved?.startDateUtc, 1736150400)
        XCTAssertEqual(retrieved?.endDateUtc, 1736154000)
        XCTAssertEqual(retrieved?.startTimezone, "America/New_York")
        XCTAssertEqual(retrieved?.isAllDay, false)
        XCTAssertEqual(retrieved?.recurrenceRule, "FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR")
        XCTAssertEqual(retrieved?.status, "confirmed")
    }

    func testGetEventByEventKitId() throws {
        try database.initialize()

        let calendar = StoredCalendar(id: "cal-test", title: "Test")
        try database.upsertCalendar(calendar)

        let event = StoredEvent(
            id: "event-ek-test",
            eventkitId: "EK-UNIQUE-ID-456",
            calendarId: "cal-test",
            startDateUtc: 1736150400,
            endDateUtc: 1736154000
        )

        try database.upsertEvent(event)

        let retrieved = try database.getEvent(eventkitId: "EK-UNIQUE-ID-456")

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, "event-ek-test")
    }

    func testGetEventsInDateRange() throws {
        try database.initialize()

        let calendar = StoredCalendar(id: "cal-range", title: "Range Test")
        try database.upsertCalendar(calendar)

        // Create events at different times
        let events = [
            StoredEvent(id: "e1", calendarId: "cal-range", summary: "Event 1",
                       startDateUtc: 1736100000, endDateUtc: 1736103600),  // Jan 5, 2025
            StoredEvent(id: "e2", calendarId: "cal-range", summary: "Event 2",
                       startDateUtc: 1736150400, endDateUtc: 1736154000),  // Jan 6, 2025
            StoredEvent(id: "e3", calendarId: "cal-range", summary: "Event 3",
                       startDateUtc: 1736200800, endDateUtc: 1736204400),  // Jan 7, 2025
            StoredEvent(id: "e4", calendarId: "cal-range", summary: "Event 4",
                       startDateUtc: 1736300000, endDateUtc: 1736303600),  // Jan 8, 2025
        ]

        try database.upsertEvents(events)

        // Query for Jan 6-7
        let start = Date(timeIntervalSince1970: 1736150000)
        let end = Date(timeIntervalSince1970: 1736210000)

        let results = try database.getEvents(from: start, to: end)

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains { $0.id == "e2" })
        XCTAssertTrue(results.contains { $0.id == "e3" })
    }

    func testGetUpcomingEvents() throws {
        try database.initialize()

        let calendar = StoredCalendar(id: "cal-upcoming", title: "Upcoming Test")
        try database.upsertCalendar(calendar)

        let now = Int(Date().timeIntervalSince1970)
        let pastEvent = StoredEvent(
            id: "past",
            calendarId: "cal-upcoming",
            summary: "Past Event",
            startDateUtc: now - 86400, // Yesterday
            endDateUtc: now - 82800
        )

        let futureEvent1 = StoredEvent(
            id: "future1",
            calendarId: "cal-upcoming",
            summary: "Tomorrow Meeting",
            startDateUtc: now + 86400, // Tomorrow
            endDateUtc: now + 90000
        )

        let futureEvent2 = StoredEvent(
            id: "future2",
            calendarId: "cal-upcoming",
            summary: "Next Week Meeting",
            startDateUtc: now + 604800, // Next week
            endDateUtc: now + 608400
        )

        try database.upsertEvent(pastEvent)
        try database.upsertEvent(futureEvent1)
        try database.upsertEvent(futureEvent2)

        let upcoming = try database.getUpcomingEvents(limit: 10)

        XCTAssertEqual(upcoming.count, 2)
        XCTAssertEqual(upcoming[0].id, "future1") // Ordered by start date
        XCTAssertEqual(upcoming[1].id, "future2")
    }

    func testDeleteEvent() throws {
        try database.initialize()

        let calendar = StoredCalendar(id: "cal-del", title: "Delete Test")
        try database.upsertCalendar(calendar)

        let event = StoredEvent(
            id: "event-to-delete",
            calendarId: "cal-del",
            startDateUtc: 1736150400,
            endDateUtc: 1736154000
        )

        try database.upsertEvent(event)

        let deleted = try database.deleteEvent(id: "event-to-delete")

        XCTAssertTrue(deleted)

        let retrieved = try database.getEvent(id: "event-to-delete")
        XCTAssertNil(retrieved)
    }

    func testDeleteEventsNotInSet() throws {
        try database.initialize()

        let calendar = StoredCalendar(id: "cal-cleanup", title: "Cleanup Test")
        try database.upsertCalendar(calendar)

        let events = [
            StoredEvent(id: "keep-1", calendarId: "cal-cleanup", startDateUtc: 1, endDateUtc: 2),
            StoredEvent(id: "keep-2", calendarId: "cal-cleanup", startDateUtc: 3, endDateUtc: 4),
            StoredEvent(id: "delete-1", calendarId: "cal-cleanup", startDateUtc: 5, endDateUtc: 6),
            StoredEvent(id: "delete-2", calendarId: "cal-cleanup", startDateUtc: 7, endDateUtc: 8),
        ]

        try database.upsertEvents(events)

        let keepIds: Set<String> = ["keep-1", "keep-2"]
        let deletedCount = try database.deleteEventsNotIn(ids: keepIds, forCalendar: "cal-cleanup")

        XCTAssertEqual(deletedCount, 2)

        let remaining = try database.getEventCount()
        XCTAssertEqual(remaining, 2)
    }

    // MARK: - Attendee Operations

    func testAttendeeOperations() throws {
        try database.initialize()

        let calendar = StoredCalendar(id: "cal-att", title: "Attendee Test")
        try database.upsertCalendar(calendar)

        let event = StoredEvent(
            id: "event-with-attendees",
            calendarId: "cal-att",
            summary: "Team Meeting",
            startDateUtc: 1736150400,
            endDateUtc: 1736154000
        )
        try database.upsertEvent(event)

        let attendees = [
            StoredAttendee(eventId: "event-with-attendees", name: "Alice", email: "alice@example.com",
                          responseStatus: "accepted", isOrganizer: true, isOptional: false),
            StoredAttendee(eventId: "event-with-attendees", name: "Bob", email: "bob@example.com",
                          responseStatus: "tentative", isOrganizer: false, isOptional: false),
            StoredAttendee(eventId: "event-with-attendees", name: "Charlie", email: "charlie@example.com",
                          responseStatus: "needs-action", isOrganizer: false, isOptional: true),
        ]

        for attendee in attendees {
            try database.upsertAttendee(attendee)
        }

        let retrieved = try database.getAttendees(eventId: "event-with-attendees")

        XCTAssertEqual(retrieved.count, 3)
        XCTAssertTrue(retrieved.contains { $0.email == "alice@example.com" && $0.isOrganizer })
        XCTAssertTrue(retrieved.contains { $0.email == "bob@example.com" && $0.responseStatus == "tentative" })
        XCTAssertTrue(retrieved.contains { $0.email == "charlie@example.com" && $0.isOptional })
    }

    func testReplaceAttendees() throws {
        try database.initialize()

        let calendar = StoredCalendar(id: "cal-replace", title: "Replace Test")
        try database.upsertCalendar(calendar)

        let event = StoredEvent(
            id: "event-replace-att",
            calendarId: "cal-replace",
            startDateUtc: 1736150400,
            endDateUtc: 1736154000
        )
        try database.upsertEvent(event)

        // Add initial attendees
        let initialAttendees = [
            StoredAttendee(eventId: "event-replace-att", name: "Old Attendee", email: "old@example.com"),
        ]
        for att in initialAttendees {
            try database.upsertAttendee(att)
        }

        // Replace with new attendees
        let newAttendees = [
            StoredAttendee(eventId: "event-replace-att", name: "New Attendee 1", email: "new1@example.com"),
            StoredAttendee(eventId: "event-replace-att", name: "New Attendee 2", email: "new2@example.com"),
        ]
        try database.replaceAttendees(eventId: "event-replace-att", attendees: newAttendees)

        let retrieved = try database.getAttendees(eventId: "event-replace-att")

        XCTAssertEqual(retrieved.count, 2)
        XCTAssertFalse(retrieved.contains { $0.email == "old@example.com" })
        XCTAssertTrue(retrieved.contains { $0.email == "new1@example.com" })
        XCTAssertTrue(retrieved.contains { $0.email == "new2@example.com" })
    }

    func testAttendeeCascadeDelete() throws {
        try database.initialize()

        let calendar = StoredCalendar(id: "cal-cascade", title: "Cascade Test")
        try database.upsertCalendar(calendar)

        let event = StoredEvent(
            id: "event-cascade",
            calendarId: "cal-cascade",
            startDateUtc: 1736150400,
            endDateUtc: 1736154000
        )
        try database.upsertEvent(event)

        let attendee = StoredAttendee(
            eventId: "event-cascade",
            name: "Test Attendee",
            email: "cascade@example.com"
        )
        try database.upsertAttendee(attendee)

        // Verify attendee exists
        var attendees = try database.getAttendees(eventId: "event-cascade")
        XCTAssertEqual(attendees.count, 1)

        // Delete the event
        _ = try database.deleteEvent(id: "event-cascade")

        // Attendees should be cascade deleted
        attendees = try database.getAttendees(eventId: "event-cascade")
        XCTAssertEqual(attendees.count, 0)
    }

    // MARK: - FTS Search

    func testFTSSearch() throws {
        try database.initialize()

        let calendar = StoredCalendar(id: "cal-fts", title: "FTS Test")
        try database.upsertCalendar(calendar)

        let events = [
            StoredEvent(id: "fts-1", calendarId: "cal-fts", summary: "Project Planning Meeting",
                       eventDescription: "Discuss Q1 roadmap", startDateUtc: 1, endDateUtc: 2),
            StoredEvent(id: "fts-2", calendarId: "cal-fts", summary: "Team Standup",
                       eventDescription: "Daily sync", startDateUtc: 3, endDateUtc: 4),
            StoredEvent(id: "fts-3", calendarId: "cal-fts", summary: "Code Review",
                       location: "Conference Room Planning", startDateUtc: 5, endDateUtc: 6),
        ]

        try database.upsertEvents(events)

        // Search for "planning" - should match summary and location
        let results = try database.searchEvents(query: "planning")

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains { $0.id == "fts-1" })
        XCTAssertTrue(results.contains { $0.id == "fts-3" })
    }

    func testFTSSearchDescription() throws {
        try database.initialize()

        let calendar = StoredCalendar(id: "cal-fts-desc", title: "FTS Desc Test")
        try database.upsertCalendar(calendar)

        let event = StoredEvent(
            id: "fts-desc-1",
            calendarId: "cal-fts-desc",
            summary: "Meeting",
            eventDescription: "Discuss the quarterly budget review",
            startDateUtc: 1,
            endDateUtc: 2
        )

        try database.upsertEvent(event)

        let results = try database.searchEvents(query: "quarterly budget")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "fts-desc-1")
    }

    // MARK: - Sync Status

    func testSyncStatusOperations() throws {
        try database.initialize()

        try database.setSyncStatus(key: "test_key", value: "test_value")

        let value = try database.getSyncStatus(key: "test_key")

        XCTAssertEqual(value, "test_value")
    }

    func testSyncStatusUpdate() throws {
        try database.initialize()

        try database.setSyncStatus(key: "update_key", value: "original")
        try database.setSyncStatus(key: "update_key", value: "updated")

        let value = try database.getSyncStatus(key: "update_key")

        XCTAssertEqual(value, "updated")
    }

    func testLastSyncTime() throws {
        try database.initialize()

        let now = Date()
        try database.setLastSyncTime(now)

        let retrieved = try database.getLastSyncTime()

        XCTAssertNotNil(retrieved)
        // Allow 1 second tolerance for timestamp conversion
        XCTAssertEqual(retrieved!.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1.0)
    }

    // MARK: - Statistics

    func testEventCount() throws {
        try database.initialize()

        let calendar = StoredCalendar(id: "cal-count", title: "Count Test")
        try database.upsertCalendar(calendar)

        XCTAssertEqual(try database.getEventCount(), 0)

        let events = [
            StoredEvent(id: "c1", calendarId: "cal-count", startDateUtc: 1, endDateUtc: 2),
            StoredEvent(id: "c2", calendarId: "cal-count", startDateUtc: 3, endDateUtc: 4),
            StoredEvent(id: "c3", calendarId: "cal-count", startDateUtc: 5, endDateUtc: 6),
        ]
        try database.upsertEvents(events)

        XCTAssertEqual(try database.getEventCount(), 3)
    }

    func testCalendarCount() throws {
        try database.initialize()

        XCTAssertEqual(try database.getCalendarCount(), 0)

        try database.upsertCalendar(StoredCalendar(id: "cc1", title: "Cal 1"))
        try database.upsertCalendar(StoredCalendar(id: "cc2", title: "Cal 2"))

        XCTAssertEqual(try database.getCalendarCount(), 2)
    }

    // MARK: - All-Day Events

    func testAllDayEvent() throws {
        try database.initialize()

        let calendar = StoredCalendar(id: "cal-allday", title: "All Day Test")
        try database.upsertCalendar(calendar)

        let allDayEvent = StoredEvent(
            id: "allday-1",
            calendarId: "cal-allday",
            summary: "Company Holiday",
            startDateUtc: 1736121600, // Midnight UTC
            endDateUtc: 1736208000,   // Next midnight UTC
            isAllDay: true
        )

        try database.upsertEvent(allDayEvent)

        let retrieved = try database.getEvent(id: "allday-1")

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.isAllDay, true)
    }

    // MARK: - Recurring Events

    func testRecurringEventWithMaster() throws {
        try database.initialize()

        let calendar = StoredCalendar(id: "cal-recur", title: "Recurring Test")
        try database.upsertCalendar(calendar)

        // Master event
        let masterEvent = StoredEvent(
            id: "master-123",
            calendarId: "cal-recur",
            summary: "Weekly Standup",
            startDateUtc: 1736150400,
            endDateUtc: 1736154000,
            recurrenceRule: "FREQ=WEEKLY;BYDAY=MO"
        )
        try database.upsertEvent(masterEvent)

        // Occurrence
        let occurrence = StoredEvent(
            id: "occur-123-1",
            calendarId: "cal-recur",
            summary: "Weekly Standup",
            startDateUtc: 1736755200, // Next week
            endDateUtc: 1736758800,
            masterEventId: "master-123",
            occurrenceDate: 1736755200
        )
        try database.upsertEvent(occurrence)

        let masterRetrieved = try database.getEvent(id: "master-123")
        let occurrenceRetrieved = try database.getEvent(id: "occur-123-1")

        XCTAssertNotNil(masterRetrieved)
        XCTAssertEqual(masterRetrieved?.recurrenceRule, "FREQ=WEEKLY;BYDAY=MO")

        XCTAssertNotNil(occurrenceRetrieved)
        XCTAssertEqual(occurrenceRetrieved?.masterEventId, "master-123")
        XCTAssertEqual(occurrenceRetrieved?.occurrenceDate, 1736755200)
    }

    // MARK: - Error Handling

    func testQueryWithoutInitialization() throws {
        // Don't initialize database

        XCTAssertThrowsError(try database.getAllCalendars()) { error in
            XCTAssertTrue(error is CalendarDatabaseError)
            if case CalendarDatabaseError.notInitialized = error {
                // Expected
            } else {
                XCTFail("Expected notInitialized error")
            }
        }
    }
}
