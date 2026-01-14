import XCTest
@testable import SwiftEAKit

final class CalendarIdGeneratorTests: XCTestCase {
    var generator: CalendarIdGenerator!

    override func setUp() {
        super.setUp()
        generator = CalendarIdGenerator()
    }

    override func tearDown() {
        generator = nil
        super.tearDown()
    }

    // MARK: - Public ID Generation

    func testPublicIdWithExternalIdentifier() {
        let identity = EventKitIdentity(
            eventIdentifier: "EK-LOCAL-123",
            externalIdentifier: "EXTERNAL-UUID-456",
            calendarIdentifier: "CAL-789"
        )

        let id = generator.generatePublicId(
            identity: identity,
            summary: "Team Meeting",
            startDate: Date()
        )

        // Should use external ID directly (normalized)
        XCTAssertEqual(id, "EXTERNAL-UUID-456")
    }

    func testPublicIdFallbackWhenNoExternalId() {
        let identity = EventKitIdentity(
            eventIdentifier: "EK-LOCAL-123",
            externalIdentifier: nil,
            calendarIdentifier: "CAL-789"
        )

        let startDate = Date(timeIntervalSince1970: 1736150400)
        let id = generator.generatePublicId(
            identity: identity,
            summary: "Team Meeting",
            startDate: startDate
        )

        // Should generate a hash-based ID
        XCTAssertTrue(generator.isValidId(id))
        XCTAssertEqual(id.count, 32)
    }

    func testPublicIdConsistency() {
        let identity = EventKitIdentity(
            eventIdentifier: nil,
            externalIdentifier: nil,
            calendarIdentifier: "CAL-789"
        )
        let startDate = Date(timeIntervalSince1970: 1736150400)

        let id1 = generator.generatePublicId(
            identity: identity,
            summary: "Team Meeting",
            startDate: startDate
        )

        let id2 = generator.generatePublicId(
            identity: identity,
            summary: "Team Meeting",
            startDate: startDate
        )

        // Same inputs should produce same ID
        XCTAssertEqual(id1, id2)
    }

    func testPublicIdDifferentSummaries() {
        let identity = EventKitIdentity(
            eventIdentifier: nil,
            externalIdentifier: nil,
            calendarIdentifier: "CAL-789"
        )
        let startDate = Date(timeIntervalSince1970: 1736150400)

        let id1 = generator.generatePublicId(
            identity: identity,
            summary: "Team Meeting",
            startDate: startDate
        )

        let id2 = generator.generatePublicId(
            identity: identity,
            summary: "Different Meeting",
            startDate: startDate
        )

        // Different summaries should produce different IDs
        XCTAssertNotEqual(id1, id2)
    }

    func testPublicIdDifferentStartTimes() {
        let identity = EventKitIdentity(
            eventIdentifier: nil,
            externalIdentifier: nil,
            calendarIdentifier: "CAL-789"
        )

        let id1 = generator.generatePublicId(
            identity: identity,
            summary: "Team Meeting",
            startDate: Date(timeIntervalSince1970: 1736150400)
        )

        let id2 = generator.generatePublicId(
            identity: identity,
            summary: "Team Meeting",
            startDate: Date(timeIntervalSince1970: 1736236800)
        )

        // Different start times should produce different IDs
        XCTAssertNotEqual(id1, id2)
    }

    // MARK: - Recurring Event IDs

    func testRecurringInstanceIdWithExternalId() {
        let identity = EventKitIdentity(
            eventIdentifier: "EK-MASTER",
            externalIdentifier: "EXTERNAL-MASTER-ID",
            calendarIdentifier: "CAL-789"
        )
        let occurrenceDate = Date(timeIntervalSince1970: 1736755200)

        let id = generator.generatePublicId(
            identity: identity,
            summary: "Weekly Standup",
            startDate: Date(timeIntervalSince1970: 1736150400),
            occurrenceDate: occurrenceDate
        )

        // Should generate a hash combining external ID and occurrence
        XCTAssertTrue(generator.isValidId(id))
    }

    func testRecurringInstanceIdsDiffer() {
        let identity = EventKitIdentity(
            eventIdentifier: "EK-MASTER",
            externalIdentifier: "EXTERNAL-MASTER-ID",
            calendarIdentifier: "CAL-789"
        )

        let id1 = generator.generatePublicId(
            identity: identity,
            summary: "Weekly Standup",
            startDate: Date(timeIntervalSince1970: 1736150400),
            occurrenceDate: Date(timeIntervalSince1970: 1736755200)
        )

        let id2 = generator.generatePublicId(
            identity: identity,
            summary: "Weekly Standup",
            startDate: Date(timeIntervalSince1970: 1736150400),
            occurrenceDate: Date(timeIntervalSince1970: 1737360000)
        )

        // Different occurrences should have different IDs
        XCTAssertNotEqual(id1, id2)
    }

    func testRecurringInstanceIdConsistency() {
        let baseId = "MASTER-EVENT-ID"
        let occurrenceDate = Date(timeIntervalSince1970: 1736755200)

        let id1 = generator.generateRecurringInstanceId(
            baseId: baseId,
            occurrenceDate: occurrenceDate
        )

        let id2 = generator.generateRecurringInstanceId(
            baseId: baseId,
            occurrenceDate: occurrenceDate
        )

        XCTAssertEqual(id1, id2)
    }

    // MARK: - Fallback ID Generation

    func testFallbackIdWithAllComponents() {
        let id = generator.generateFallbackId(
            calendarId: "CAL-123",
            summary: "Important Meeting",
            startDate: Date(timeIntervalSince1970: 1736150400)
        )

        XCTAssertTrue(generator.isValidId(id))
        XCTAssertEqual(id.count, 32)
    }

    func testFallbackIdWithNilSummary() {
        let id = generator.generateFallbackId(
            calendarId: "CAL-123",
            summary: nil,
            startDate: Date(timeIntervalSince1970: 1736150400)
        )

        XCTAssertTrue(generator.isValidId(id))
    }

    func testFallbackIdWithEmptySummary() {
        let id = generator.generateFallbackId(
            calendarId: "CAL-123",
            summary: "",
            startDate: Date(timeIntervalSince1970: 1736150400)
        )

        XCTAssertTrue(generator.isValidId(id))
    }

    // MARK: - ID Reconciliation

    func testReconciliationMatch() {
        let stored = EventKitIdentity(
            eventIdentifier: "EK-123",
            externalIdentifier: "EXT-456",
            calendarIdentifier: "CAL-789"
        )

        let current = EventKitIdentity(
            eventIdentifier: "EK-123",
            externalIdentifier: "EXT-456",
            calendarIdentifier: "CAL-789"
        )

        let result = generator.reconcileIdentity(stored: stored, current: current)

        XCTAssertEqual(result, .match)
    }

    func testReconciliationNewEvent() {
        let current = EventKitIdentity(
            eventIdentifier: "EK-NEW",
            externalIdentifier: "EXT-NEW",
            calendarIdentifier: "CAL-789"
        )

        let result = generator.reconcileIdentity(stored: nil, current: current)

        XCTAssertEqual(result, .newEvent)
    }

    func testReconciliationExternalIdChanged() {
        let stored = EventKitIdentity(
            eventIdentifier: "EK-123",
            externalIdentifier: nil,
            calendarIdentifier: "CAL-789"
        )

        let current = EventKitIdentity(
            eventIdentifier: "EK-123",
            externalIdentifier: "EXT-NEW",
            calendarIdentifier: "CAL-789"
        )

        let result = generator.reconcileIdentity(stored: stored, current: current)

        XCTAssertEqual(result, .externalIdChanged(newExternalId: "EXT-NEW"))
    }

    func testReconciliationEventKitIdChanged() {
        let stored = EventKitIdentity(
            eventIdentifier: "EK-OLD",
            externalIdentifier: "EXT-456",
            calendarIdentifier: "CAL-789"
        )

        let current = EventKitIdentity(
            eventIdentifier: "EK-NEW",
            externalIdentifier: "EXT-456",
            calendarIdentifier: "CAL-789"
        )

        let result = generator.reconcileIdentity(stored: stored, current: current)

        XCTAssertEqual(result, .eventKitIdChanged(newEventKitId: "EK-NEW"))
    }

    func testReconciliationBothIdsChanged() {
        let stored = EventKitIdentity(
            eventIdentifier: "EK-OLD",
            externalIdentifier: "EXT-OLD",
            calendarIdentifier: "CAL-789"
        )

        let current = EventKitIdentity(
            eventIdentifier: "EK-NEW",
            externalIdentifier: "EXT-NEW",
            calendarIdentifier: "CAL-789"
        )

        let result = generator.reconcileIdentity(stored: stored, current: current)

        XCTAssertEqual(result, .bothIdsChanged(newEventKitId: "EK-NEW", newExternalId: "EXT-NEW"))
    }

    func testReconciliationNotFound() {
        let stored = EventKitIdentity(
            eventIdentifier: "EK-OLD",
            externalIdentifier: "EXT-OLD",
            calendarIdentifier: "CAL-OLD"
        )

        let current = EventKitIdentity(
            eventIdentifier: "EK-DIFFERENT",
            externalIdentifier: "EXT-DIFFERENT",
            calendarIdentifier: "CAL-DIFFERENT"
        )

        let result = generator.reconcileIdentity(stored: stored, current: current)

        XCTAssertEqual(result, .notFound)
    }

    // MARK: - Content Matching

    func testContentMatchesExact() {
        let matches = generator.contentMatches(
            storedSummary: "Team Meeting",
            storedStart: Date(timeIntervalSince1970: 1736150400),
            currentSummary: "Team Meeting",
            currentStart: Date(timeIntervalSince1970: 1736150400)
        )

        XCTAssertTrue(matches)
    }

    func testContentMatchesCaseInsensitive() {
        let matches = generator.contentMatches(
            storedSummary: "Team Meeting",
            storedStart: Date(timeIntervalSince1970: 1736150400),
            currentSummary: "TEAM MEETING",
            currentStart: Date(timeIntervalSince1970: 1736150400)
        )

        XCTAssertTrue(matches)
    }

    func testContentMatchesWithinTolerance() {
        let matches = generator.contentMatches(
            storedSummary: "Team Meeting",
            storedStart: Date(timeIntervalSince1970: 1736150400),
            currentSummary: "Team Meeting",
            currentStart: Date(timeIntervalSince1970: 1736150430), // 30 seconds later
            tolerance: 60
        )

        XCTAssertTrue(matches)
    }

    func testContentMatchesOutsideTolerance() {
        let matches = generator.contentMatches(
            storedSummary: "Team Meeting",
            storedStart: Date(timeIntervalSince1970: 1736150400),
            currentSummary: "Team Meeting",
            currentStart: Date(timeIntervalSince1970: 1736150500), // 100 seconds later
            tolerance: 60
        )

        XCTAssertFalse(matches)
    }

    func testContentMatchesDifferentSummaries() {
        let matches = generator.contentMatches(
            storedSummary: "Team Meeting",
            storedStart: Date(timeIntervalSince1970: 1736150400),
            currentSummary: "Different Meeting",
            currentStart: Date(timeIntervalSince1970: 1736150400)
        )

        XCTAssertFalse(matches)
    }

    func testContentMatchesNilSummaries() {
        let matches = generator.contentMatches(
            storedSummary: nil,
            storedStart: Date(timeIntervalSince1970: 1736150400),
            currentSummary: nil,
            currentStart: Date(timeIntervalSince1970: 1736150400)
        )

        XCTAssertTrue(matches)
    }

    // MARK: - Calendar ID Generation

    func testCalendarIdWithIdentifier() {
        let id = generator.generateCalendarId(
            calendarIdentifier: "CAL-UUID-123",
            title: "Work Calendar",
            source: "iCloud"
        )

        XCTAssertEqual(id, "CAL-UUID-123")
    }

    func testCalendarIdFallback() {
        let id = generator.generateCalendarId(
            calendarIdentifier: nil,
            title: "Work Calendar",
            source: "iCloud"
        )

        XCTAssertTrue(generator.isValidId(id))
    }

    func testCalendarIdFallbackConsistency() {
        let id1 = generator.generateCalendarId(
            calendarIdentifier: nil,
            title: "Work Calendar",
            source: "iCloud"
        )

        let id2 = generator.generateCalendarId(
            calendarIdentifier: nil,
            title: "Work Calendar",
            source: "iCloud"
        )

        XCTAssertEqual(id1, id2)
    }

    // MARK: - Validation

    func testIsValidId() {
        XCTAssertTrue(generator.isValidId("a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"))
        XCTAssertTrue(generator.isValidId("00000000000000000000000000000000"))
        XCTAssertFalse(generator.isValidId("too-short"))
        XCTAssertFalse(generator.isValidId("A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4")) // uppercase
        XCTAssertFalse(generator.isValidId("g1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4")) // invalid hex
        XCTAssertFalse(generator.isValidId("")) // empty
    }

    func testIsExternalId() {
        XCTAssertTrue(generator.isExternalId("EXTERNAL-UUID-123"))
        XCTAssertTrue(generator.isExternalId("CalDAV-Server-ID"))
        XCTAssertFalse(generator.isExternalId("a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4")) // valid hash ID
        XCTAssertFalse(generator.isExternalId(""))
    }

    // MARK: - Convenience Extension

    func testConveniencePublicIdGeneration() {
        let id = generator.generatePublicId(
            externalIdentifier: nil,
            calendarIdentifier: "CAL-789",
            summary: "Quick Meeting",
            startDate: Date(timeIntervalSince1970: 1736150400)
        )

        XCTAssertTrue(generator.isValidId(id))
    }
}
