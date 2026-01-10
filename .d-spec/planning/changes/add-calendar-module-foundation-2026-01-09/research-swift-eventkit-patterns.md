# Calendar Module Bootstrap Research: Swift/EventKit Patterns

> Research conducted 2026-01-09 to find existing Swift code, libraries, and patterns for Calendar module development.

## Executive Summary

Three research areas were explored to accelerate Calendar module development for a macOS CLI tool:

1. **EventKit Wrappers** - Found mature async/await patterns, permission handling, and recurring event support
2. **Calendar CLI Tools** - Found JSON export formats, stable ID strategies, and ICS generation libraries
3. **SQLite Schemas** - Found GRDB.swift for persistence, FTS5 patterns, and sync strategies

---

## 1. EventKit Wrappers & Helpers

### Top Repositories

| Repository | License | Key Features |
|------------|---------|--------------|
| [Shift](https://github.com/vinhnx/Shift) | MIT | Modern async/await, SwiftUI integration, MainActor safety |
| [Clendar](https://github.com/vinhnx/Clendar) | MIT | Real-world macOS calendar app using Shift patterns |
| [RWMRecurrenceRule](https://github.com/rmaddy/RWMRecurrenceRule) | MIT | iCalendar RRULE parsing, date enumeration |
| [Klendario](https://github.com/ThXou/Klendario) | MIT | Fluent API, semi-automatic authorization |
| [macos-calendar-events](https://github.com/zigotica/macos-calendar-events) | Open source | macOS CLI, avoids TCC issues |
| [WWDC23 Sample](https://github.com/gromb57/ios-wwdc23__AccessingCalendarUsingEventKitAndEventKitUI) | Apple | Three permission models, modern patterns |

### Key Code Patterns

#### Modern Permission Handling (macOS 14+)

```swift
func requestCalendarAccess() async throws -> Bool {
    if #available(macOS 14.0, *) {
        return try await eventStore.requestFullAccessToEvents()
    } else {
        return try await eventStore.requestAccess(to: .event)
    }
}
```

#### Async Event Fetching with MainActor

```swift
@MainActor
func fetchEvents(for date: Date) async throws -> [EKEvent] {
    guard try await requestCalendarAccess() else {
        throw CalendarError.accessDenied
    }

    let startOfDay = Calendar.current.startOfDay(for: date)
    let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

    let predicate = eventStore.predicateForEvents(
        withStart: startOfDay,
        end: endOfDay,
        calendars: nil
    )

    return eventStore.events(matching: predicate)
        .sorted { $0.startDate < $1.startDate }
}
```

#### Continuation-Based Wrapper Pattern

```swift
func requestEventStoreAuthorization() async throws -> EKAuthorizationStatus {
    try await withCheckedThrowingContinuation { [weak self] continuation in
        guard let self = self else {
            continuation.resume(throwing: CalendarError.deallocated)
            return
        }

        self.eventStore.requestAccess(to: .event) { granted, error in
            if let error = error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: EKEventStore.authorizationStatus(for: .event))
            }
        }
    }
}
```

#### Request Access Callback Queue Gotcha (Always Hop to MainActor When Needed)

Apple does not guarantee `requestAccess` (and related APIs) invoke their completion handler on the main thread. If any follow-up touches UI state (or `@MainActor` state), hop explicitly:

```swift
func requestAccessAndUpdateState() async throws {
    let granted = try await eventStore.requestAccess(to: .event)
    await MainActor.run {
        self.hasCalendarAccess = granted
    }
}
```

#### “Stable Enough” Event Identity (Store Multiple IDs)

`eventIdentifier` is convenient for fast local lookups, but it may change after sync. Prefer storing multiple identifiers and reconciling:

```swift
struct StoredEventIdentity: Codable, Hashable {
    var eventIdentifier: String?                 // EKEvent.eventIdentifier
    var externalIdentifier: String?              // EKCalendarItem.calendarItemExternalIdentifier
    var calendarIdentifier: String               // EKCalendar.calendarIdentifier
}

func preferredStableID(for event: EKEvent) -> String {
    event.calendarItemExternalIdentifier ?? event.eventIdentifier
}
```

Also useful for refresh/relink:

```swift
if let id = stored.eventIdentifier, let event = eventStore.event(withIdentifier: id) {
    // Found quickly; verify externalIdentifier if present and refresh stored identity if needed.
}
```

#### Recurring Event Date Enumeration

```swift
// From RWMRecurrenceRule - MIT License
let rule = "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH"
let parser = RWMRuleParser()
if let rules = parser.parse(rule: rule) {
    let scheduler = RWMRuleScheduler()
    scheduler.enumerateDates(with: rules, startingFrom: Date()) { date, stop in
        if let date = date {
            // Process each occurrence
        }
    }
}
```

#### EKEventStore Change Notification (Async)

```swift
for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
    await refreshEvents()
}
```

### Architecture Patterns to Adopt

1. **Singleton EKEventStore** - Keep one instance throughout app lifecycle
2. **ObservableObject for SwiftUI** - `@Published` properties for seamless binding
3. **MainActor Isolation** - `@MainActor` on published property updates
4. **Tiered Permission Requests** - Support none/write-only/full access levels
5. **Range Queries Let EventKit Expand Recurrences** - For most CLI needs, query by date range and treat returned `EKEvent`s as occurrences (including exceptions); use RRULE parsing only when caching/expanding offline is required.

### Info.plist Keys Required

```xml
<key>NSCalendarsFullAccessUsageDescription</key>
<string>We need calendar access to display and create events</string>
<key>NSCalendarsWriteOnlyAccessUsageDescription</key>
<string>We need to add events to your calendar</string>
```

### Critical Gotchas

1. **iOS 18.4+/macOS 15.4+ Regression** - Updating event's calendar to another account or detaching recurring events throws "Access denied"
2. **EKSource Selection** - Creating calendars requires valid EKSource; use user's default, iCloud, or local as fallback
3. **Cross-Store Object Usage** - Never save/delete objects from different EKEventStore instances
4. **Siri Suggestions Calendar** - Shows in EKCalendarChooser but has no valid ID
5. **CLI vs App Context** - TCC/permissions behave differently for unsigned CLI binaries; prefer a signed app bundle target for reliable prompting, or follow patterns from `macos-calendar-events`.

---

## 2. Calendar CLI Tools & Data Export

### Top Repositories

| Repository | License | Key Features |
|------------|---------|--------------|
| [plan.swift](https://github.com/oschrenk/plan.swift) | MIT | JSON output, templating, meeting URL extraction |
| [macos-calendar-events](https://github.com/zigotica/macos-calendar-events) | Open | Minimal EventKit wrapper, single-file |
| [iCalKit](https://github.com/kiliankoe/iCalKit) | MIT (archived) | ICS parsing/generation |
| [swift-ical](https://github.com/tbartelmess/swift-ical) | MPL 2.0 | Robust ICS with timezone handling |
| [ICalendarKit](https://github.com/swift-calendar/icalendarkit) | MIT | Active RFC 5545 encoder |
| [iCalendarParser](https://github.com/dmail-me/iCalendarParser) | MIT | RFC 5545 parser (import ICS → internal model) |
| [icalendar-kit](https://github.com/thoven87/icalendar-kit) | MIT | iCalendar toolkit (alternative encoder/decoder surface) |

### Stable ID Strategy

EventKit provides three identifiers with different stability:

| Identifier | Use Case | Stability |
|------------|----------|-----------|
| `eventIdentifier` | Local event lookup | Stable locally; may change after sync |
| `calendarItemExternalIdentifier` | Server-provided ID | Most stable for CalDAV/iCloud; can be nil before sync |
| `calendarIdentifier` | Calendar-level ID | Stable |

**Recommended approach:**
- Store `calendarItemExternalIdentifier` when available (non-nil)
- Fall back to `eventIdentifier` for local-only calendars
- For recurring events, combine UID with `occurrenceDate` or `RECURRENCE-ID`

### JSON Export Format (from plan.swift)

```swift
struct EventExport: Codable {
    let id: String
    let calendar: CalendarInfo
    let title: TitleInfo
    let schedule: ScheduleInfo
    let location: String?
    let notes: String?
    let isAllDay: Bool
    let recurrence: RecurrenceInfo?
}

struct ScheduleInfo: Codable {
    let start: TimePoint
    let end: TimePoint
    let duration: Int  // minutes
}

struct TimePoint: Codable {
    let at: Date      // ISO8601
    let `in`: Int?    // relative minutes from now (optional)
}
```

### CLI Command Structure (ArgumentParser)

```swift
@main
struct CalendarCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cal",
        abstract: "Calendar CLI tool",
        subcommands: [List.self, Export.self, Sync.self]
    )
}

struct List: AsyncParsableCommand {
    @Option(name: .shortAndLong, help: "Number of days to fetch")
    var days: Int = 7

    @Option(name: .shortAndLong, help: "Output format")
    var format: OutputFormat = .json

    func run() async throws {
        // Implementation
    }
}
```

### ICS Generation (ICalendarKit)

```swift
let ical = ICalendar()
ical.append(ICalendarEvent(
    description: "Meeting",
    dtstart: .dateTime(Date()),
    duration: .hours(1),
    rrule: ICalendarRecurrenceRule(frequency: .weekly, byDay: [.monday])
))
print(ical.vEncoded)
```

### Critical Gotchas

1. **EKCalendar is not Sendable** - Cache only identifiers/properties, not objects
2. **calendarItemExternalIdentifier is nil** - Newly created events before sync completes
3. **EKEventStoreChangedNotification** - Has no change metadata; full reload required
4. **Prefer Async CLI Entrypoints** - Use `AsyncParsableCommand` for commands that must request permission or query EventKit asynchronously.

---

## 3. SQLite/libSQL Calendar Schemas

### Top Repositories

| Repository | License | Key Features |
|------------|---------|--------------|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | MIT | FTS5, migrations, reactive observation |
| [SQLiteData (Point-Free)](https://github.com/pointfreeco/sqlite-data) | MIT | SwiftData replacement with CloudKit |
| [SQLiteChangesetSync](https://github.com/gerdemb/SQLiteChangesetSync) | MIT | Git-like changeset sync |
| [google-calendar-to-sqlite](https://github.com/simonw/google-calendar-to-sqlite) | Apache-2.0 | Complete schema reference |
| [libsql-swift (Turso)](https://github.com/tursodatabase/libsql-swift) | MIT | Local-first embedded replicas |

### Calendar Events Schema

```sql
CREATE TABLE calendars (
    id TEXT PRIMARY KEY,
    name TEXT,
    summary TEXT,
    description TEXT,
    timeZone TEXT,
    colorId TEXT,
    backgroundColor TEXT,
    foregroundColor TEXT,
    accessRole TEXT,
    defaultReminders TEXT,  -- JSON
    primary INTEGER
);

CREATE TABLE events (
    id TEXT PRIMARY KEY,
    calendar_id TEXT REFERENCES calendars(id),
    summary TEXT,
    description TEXT,
    location TEXT,
    status TEXT,

    -- Temporal (store in UTC)
    start_dateTime TEXT,
    end_dateTime TEXT,
    start_date TEXT,        -- for all-day events
    end_date TEXT,
    start_timeZone TEXT,
    end_timeZone TEXT,

    -- Recurrence
    recurrence TEXT,        -- RRULE string
    recurringEventId TEXT,  -- parent for instances

    -- Participants (JSON arrays)
    creator TEXT,
    organizer TEXT,
    attendees TEXT,

    -- Sync metadata
    etag TEXT,
    iCalUID TEXT,
    updated TEXT,
    created TEXT
);
```

### Attendee Normalization Schema

```sql
CREATE TABLE attendees (
    id INTEGER PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    display_name TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE event_attendees (
    event_id TEXT REFERENCES events(id) ON DELETE CASCADE,
    attendee_id INTEGER REFERENCES attendees(id),
    response_status TEXT,  -- accepted, declined, tentative, needsAction
    is_organizer INTEGER DEFAULT 0,
    is_optional INTEGER DEFAULT 0,
    PRIMARY KEY (event_id, attendee_id)
);
```

### FTS5 Full-Text Search Setup (GRDB)

```swift
// External content FTS5 table synchronized with events table
try db.create(virtualTable: "events_fts", using: FTS5()) { t in
    t.synchronize(withTable: "events")
    t.tokenizer = .porter()  // English stemming
    t.column("summary")
    t.column("description")
    t.column("location")
}

// Querying with FTS5
let pattern = FTS5Pattern(matchingAllPrefixesIn: searchText)
let results = try Event
    .joining(required: Event.fts.matching(pattern))
    .order(Column.rank)
    .fetchAll(db)
```

### GRDB Migration Pattern

```swift
var migrator = DatabaseMigrator()

#if DEBUG
migrator.eraseDatabaseOnSchemaChange = true
#endif

migrator.registerMigration("v1_initial") { db in
    try db.create(table: "calendars") { t in
        t.column("id", .text).primaryKey()
        t.column("name", .text).notNull()
        t.column("color", .text)
        t.column("is_visible", .boolean).notNull().defaults(to: true)
    }

    try db.create(table: "events") { t in
        t.column("id", .text).primaryKey()
        t.column("calendar_id", .text).notNull()
            .references("calendars", onDelete: .cascade)
        t.column("summary", .text)
        t.column("start_date", .datetime).notNull()
        t.column("end_date", .datetime).notNull()
        t.column("is_all_day", .boolean).notNull().defaults(to: false)
        t.column("recurrence", .text)
        t.column("updated_at", .datetime).notNull()
    }
}

migrator.registerMigration("v2_add_fts") { db in
    try db.create(virtualTable: "events_fts", using: FTS5()) { t in
        t.synchronize(withTable: "events")
        t.tokenizer = .porter()
        t.column("summary")
    }
}
```

### Recommended Indexes

```sql
-- Primary query patterns
CREATE INDEX idx_events_calendar ON events(calendar_id);
CREATE INDEX idx_events_start ON events(start_date_utc);
CREATE INDEX idx_events_end ON events(end_date_utc);

-- Date range queries (common for calendar views)
CREATE INDEX idx_events_date_range ON events(calendar_id, start_date_utc, end_date_utc);

-- Recurring event lookups
CREATE INDEX idx_events_recurring ON events(recurringEventId) WHERE recurringEventId IS NOT NULL;

-- Sync queries
CREATE INDEX idx_events_updated ON events(updated);
```

### Sync Patterns

#### Delta/Incremental Sync with Sync Tokens

```sql
CREATE TABLE sync_state (
    calendar_id TEXT PRIMARY KEY,
    sync_token TEXT,
    last_sync_at TEXT,
    full_sync_required INTEGER DEFAULT 1
);
```

**Flow:**
1. Initial full sync - store returned `syncToken`
2. Subsequent syncs - pass `syncToken` to get only changes
3. On 410 error (token expired) - wipe and full sync

### Critical Anti-Patterns to Avoid

1. **Don't store unbounded recurring instances** - Avoid materializing “forever”; if you cache occurrences, cap by a window (e.g., ±90 days) and regenerate incrementally.
2. **Don't store times in local timezone** - Always store in UTC, convert for display
3. **Don't use standalone FTS tables** - Use `synchronize(withTable:)` to prevent drift
4. **Don't skip sync token handling** - Handle 410/gone errors with full sync fallback
5. **Don't assume FTS5 is always available** - Ensure your SQLite build supports FTS5 (or bundle a build that does) before depending on it for core functionality.
6. **Don't rely on changesets without a migration plan** - `SQLiteChangesetSync` is useful, but be prepared to own schema migration support and conflict resolution policies.

---

## Recommendations for swiftea Calendar Module

### Immediate Adoption

1. **GRDB.swift** for persistence - Best Swift SQLite toolkit, MIT licensed
2. **Shift patterns** for EventKit wrapping - Modern async/await approach
3. **plan.swift JSON format** for CLI export - Well-designed structure

### Architecture Decisions

1. Use singleton `EKEventStore` with `@MainActor` isolation
2. Store UTC times, convert on display
3. Use `calendarItemExternalIdentifier` as stable ID with `eventIdentifier` fallback
4. Implement FTS5 with external content table pattern

### Dependencies to Consider

| Package | Purpose | License |
|---------|---------|---------|
| GRDB.swift | SQLite persistence | MIT |
| RWMRecurrenceRule | RRULE parsing | MIT |
| ICalendarKit | ICS export | MIT |

---

## Sources

### EventKit
- [Shift](https://github.com/vinhnx/Shift)
- [Clendar](https://github.com/vinhnx/Clendar)
- [RWMRecurrenceRule](https://github.com/rmaddy/RWMRecurrenceRule)
- [Klendario](https://github.com/ThXou/Klendario)
- [macos-calendar-events](https://github.com/zigotica/macos-calendar-events)
- [Apple EventKit Documentation](https://developer.apple.com/documentation/eventkit)

### CLI Tools & ICS
- [plan.swift](https://github.com/oschrenk/plan.swift)
- [iCalKit](https://github.com/kiliankoe/iCalKit)
- [swift-ical](https://github.com/tbartelmess/swift-ical)
- [ICalendarKit](https://github.com/swift-calendar/icalendarkit)
- [iCalendarParser](https://github.com/dmail-me/iCalendarParser)
- [icalendar-kit](https://github.com/thoven87/icalendar-kit)

### SQLite & Sync
- [GRDB.swift](https://github.com/groue/GRDB.swift)
- [SQLiteData (Point-Free)](https://github.com/pointfreeco/sqlite-data)
- [SQLiteChangesetSync](https://github.com/gerdemb/SQLiteChangesetSync)
- [google-calendar-to-sqlite](https://github.com/simonw/google-calendar-to-sqlite)
- [libsql-swift](https://github.com/tursodatabase/libsql-swift)
