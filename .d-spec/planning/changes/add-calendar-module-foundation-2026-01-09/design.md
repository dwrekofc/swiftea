# Calendar Module Design

## Context

SwiftEA Phase 2 introduces Calendar as the second PIM module. The Mail Module established patterns for data mirroring, FTS search, and export. Calendar extends these patterns but differs in data source (EventKit vs SQLite) and data model (recurring events, attendees, all-day events).

Calendar is a critical dependency for ClaudEA's daily workflow - morning briefings, meeting prep, and task creation all require calendar data.

## Research Context

This design incorporates patterns from [research-swift-eventkit-patterns.md](./research-swift-eventkit-patterns.md):

- **EventKit wrappers**: Shift library patterns for async/await, MainActor isolation
- **CLI tools**: plan.swift JSON export format, ArgumentParser async commands
- **SQLite schemas**: GRDB.swift for persistence, FTS5 external content tables, google-calendar-to-sqlite schema reference

## Goals / Non-Goals

### Goals

- Establish EventKit as the reliable calendar data source
- Mirror to libSQL with schema compatible for future cross-module queries
- Provide FTS5 search matching Mail Module capabilities
- Support three export formats (Markdown, JSON, ICS)
- Design JSON output for ClaudEA consumption (briefings, meeting prep)
- Export attendees with sufficient detail for people CRM integration

### Non-Goals

- Build a complete calendar client
- Handle all edge cases of iCalendar spec
- Support write operations in this phase
- Implement cross-module linking (ClaudEA handles this)

## Key Decisions

### 1. EventKit over Direct SQLite

**Decision**: Use EventKit framework instead of direct SQLite database access.

**Rationale**:

| Factor | Direct SQLite | EventKit |
|--------|--------------|----------|
| macOS Sequoia | Calendar Cache file may not exist | Stable API |
| iCloud Sync | Unreliable, laggy updates | Handled transparently |
| Schema stability | Undocumented, changes between versions | Documented, versioned |
| Recurring events | Complex manual expansion | Built-in expansion |
| Permission | Full Disk Access | One-time user consent |

**Trade-off**: EventKit requires a user permission prompt on first use. This is acceptable because:
- It's a one-time prompt
- It provides a clear privacy boundary
- It's the Apple-recommended approach

**Implementation Notes** (from research):
- Use `requestFullAccessToEvents()` on macOS 14+, fall back to `requestAccess(to: .event)` on earlier versions
- Keep a singleton `EKEventStore` throughout app lifecycle
- Use `@MainActor` isolation for state updates after permission callbacks
- Subscribe to `EKEventStoreChangedNotification` for watch mode

**Required Info.plist Keys**:
```xml
<key>NSCalendarsFullAccessUsageDescription</key>
<string>SwiftEA needs calendar access to sync and export events</string>
<key>NSCalendarsWriteOnlyAccessUsageDescription</key>
<string>SwiftEA needs to add events to your calendar</string>
```

**Gotcha**: TCC/permissions behave differently for unsigned CLI binaries. For reliable permission prompts, prefer a signed app bundle target or follow `macos-calendar-events` patterns.

### 2. Stable ID Strategy

**Decision**: Store multiple identifiers and use a tiered lookup strategy.

**EventKit provides three identifiers** (from research):

| Identifier | Use Case | Stability |
|------------|----------|-----------|
| `eventIdentifier` | Local event lookup | Stable locally; may change after sync |
| `calendarItemExternalIdentifier` | Server-provided ID | Most stable for CalDAV/iCloud; can be nil before sync |
| `calendarIdentifier` | Calendar-level ID | Stable |

**Storage Strategy** (multi-ID approach):
```swift
struct StoredEventIdentity: Codable, Hashable {
    var eventIdentifier: String?                 // EKEvent.eventIdentifier (fast local lookup)
    var externalIdentifier: String?              // calendarItemExternalIdentifier (most stable)
    var calendarIdentifier: String               // EKCalendar.calendarIdentifier
}
```

**Public ID Selection**:
1. **Primary**: `calendarItemExternalIdentifier` when available (non-nil)
2. **Fallback**: SHA-256 hash of `calendar_id + summary + start_time` for local-only calendars

**For recurring events**: Combine UID with `occurrenceDate` or `RECURRENCE-ID` to uniquely identify instances.

**Schema Columns**:
- `id` TEXT PRIMARY KEY (stable public ID for external references)
- `eventkit_id` TEXT (EKEvent.eventIdentifier for fast local lookup)
- `external_id` TEXT (calendarItemExternalIdentifier when available)

**Reconciliation on Sync**: If `eventkit_id` lookup fails but `external_id` matches, refresh the stored identity.

**Why this matters**: ClaudEA's `meeting_notes.calendar_event_ref` and `tasks.source_ref` reference these IDs. Unstable IDs would break cross-system linking. The multi-ID approach handles sync edge cases gracefully.

### 3. Recurrence Handling

**Decision**: Let EventKit expand recurrences via date-range queries; store occurrences as received.

**Approach** (from research):
- Query EventKit by date range—it returns individual `EKEvent` instances for each occurrence (including exceptions)
- Store returned occurrences as separate rows with `master_event_id` reference to master
- Store `recurrence_rule` (RRULE string) on master event for reference only
- Use RWMRecurrenceRule library only if offline expansion is needed (e.g., caching beyond query window)

**Rationale**:
- EventKit handles exception dates, modifications, and timezone logic correctly
- Users search for individual occurrences ("next standup")
- ClaudEA briefings need specific dates, not rules
- FTS indexes individual occurrences

**Expansion Window**:
- Default: 1 year forward from sync date
- Configurable via `calendar.date_range_days` setting
- **Anti-pattern to avoid**: Never materialize "forever" recurrences—cap by window and regenerate incrementally

**Trade-off**: Some database bloat for recurring events, but configurable expansion window limits this.

### 4. Attendee Storage

**Decision**: Separate `attendees` table with full detail.

**Schema**:
```sql
CREATE TABLE attendees (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT REFERENCES events(id),
    name TEXT,
    email TEXT,
    response_status TEXT,  -- accepted, declined, tentative, none
    is_organizer INTEGER   -- boolean
);
```

**Rationale**:
- Enables FTS on attendee names
- Supports ClaudEA people CRM integration
- Allows future cross-module contact linking
- JSON export includes full attendee detail

### 5. GRDB.swift for Persistence

**Decision**: Use GRDB.swift instead of raw SQLite/libSQL for the calendar mirror database.

**Rationale** (from research):
- MIT licensed, actively maintained
- Built-in FTS5 support with external content table pattern (`synchronize(withTable:)`)
- Type-safe migrations with `DatabaseMigrator`
- Reactive observation for future UI integration
- Well-documented Swift patterns

**Key Patterns to Adopt**:
```swift
// FTS5 with external content table (stays in sync automatically)
try db.create(virtualTable: "events_fts", using: FTS5()) { t in
    t.synchronize(withTable: "events")
    t.tokenizer = .porter()
    t.column("summary")
    t.column("description")
    t.column("location")
}

// Migration with debug schema reset
var migrator = DatabaseMigrator()
#if DEBUG
migrator.eraseDatabaseOnSchemaChange = true
#endif
```

**Alternative Considered**: Raw libSQL (current Mail Module pattern)
- **Trade-off**: GRDB adds a dependency but provides safer FTS5 synchronization and cleaner migrations
- **Decision**: Use GRDB for Calendar; evaluate migrating Mail Module later if beneficial

### 6. Reminders as Separate Entities

**Decision**: Store reminders in separate table, defer CLI commands.

**Approach**:
- EventKit unifies calendars and reminders via EKEventStore
- Store reminders in `reminders` table during sync
- CLI commands for reminders deferred to Phase 3

**Rationale**:
- Reminders have different semantics (due date, completion)
- Mirror now for data availability
- CLI later to avoid scope creep

### 7. All-Day Event Handling

**Decision**: Store with `is_all_day` flag and date-only values.

**Approach**:
- `is_all_day INTEGER` (boolean flag)
- When true, `start_date` and `end_date` store dates (not datetimes)
- Export formats handle display appropriately

**Rationale**:
- Preserves original event semantics
- Avoids timezone complications for date-only events
- ClaudEA can format appropriately for briefings

### 8. UTC Time Storage

**Decision**: Store all timestamps in UTC; convert for display only.

**Rationale** (from research anti-patterns):
- Storing in local timezone causes comparison issues when user travels
- UTC is unambiguous for sorting and range queries
- Display layer handles localization

**Schema Columns**:
- `start_date_utc INTEGER` - Unix timestamp in UTC
- `end_date_utc INTEGER` - Unix timestamp in UTC
- `start_timezone TEXT` - Original timezone (e.g., "America/New_York") for display
- `end_timezone TEXT` - Original timezone for display

**Conversion**: Convert to user's local timezone only in CLI output and export formats.

### 9. Sync Strategy

**Decision**: Query-and-merge from EventKit on each sync.

**Full Sync**:
1. Query all calendars from EventKit
2. Query all events within configured date range
3. Transform to mirror schema
4. Upsert to libSQL with stable IDs
5. Mark missing events as deleted (soft delete)

**Incremental Sync**:
1. Query events modified since last sync timestamp
2. Upsert changed events
3. Detect deletions by comparing with previous sync

**EventKit handles change detection** - we query by modification date.

## Database Schema

### Tables

```sql
-- Calendars
CREATE TABLE calendars (
    id TEXT PRIMARY KEY,           -- stable ID (calendarIdentifier)
    eventkit_id TEXT,              -- EventKit identifier (for reverse lookup)
    title TEXT NOT NULL,
    source_type TEXT,              -- local, iCloud, Exchange, caldav, etc.
    color TEXT,                    -- hex color code
    is_subscribed INTEGER,         -- boolean
    is_immutable INTEGER,          -- boolean
    synced_at INTEGER              -- timestamp
);

-- Events (updated per research: multi-ID strategy, UTC timestamps)
CREATE TABLE events (
    id TEXT PRIMARY KEY,           -- stable public ID (external_id or hash)
    eventkit_id TEXT,              -- EKEvent.eventIdentifier (fast local lookup)
    external_id TEXT,              -- calendarItemExternalIdentifier (most stable, can be NULL)
    calendar_id TEXT REFERENCES calendars(id),
    summary TEXT,
    description TEXT,
    location TEXT,
    url TEXT,
    -- UTC timestamps (from research: always store UTC, convert for display)
    start_date_utc INTEGER,        -- Unix timestamp in UTC
    end_date_utc INTEGER,          -- Unix timestamp in UTC
    start_timezone TEXT,           -- Original timezone for display (e.g., "America/New_York")
    end_timezone TEXT,             -- Original timezone for display
    is_all_day INTEGER,            -- boolean
    recurrence_rule TEXT,          -- RRULE string (for reference only)
    master_event_id TEXT,          -- reference to master for occurrences
    occurrence_date INTEGER,       -- for recurring instances (combines with UID for unique ID)
    status TEXT,                   -- confirmed, tentative, cancelled
    created_at INTEGER,
    updated_at INTEGER,
    synced_at INTEGER
);

-- Attendees (normalized per research)
CREATE TABLE attendees (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT REFERENCES events(id) ON DELETE CASCADE,
    name TEXT,
    email TEXT,
    response_status TEXT,          -- accepted, declined, tentative, needsAction
    is_organizer INTEGER,          -- boolean
    is_optional INTEGER DEFAULT 0  -- boolean (from research schema)
);

-- Reminders (for future use)
CREATE TABLE reminders (
    id TEXT PRIMARY KEY,
    eventkit_id TEXT,
    calendar_id TEXT,
    title TEXT,
    notes TEXT,
    due_date INTEGER,
    priority INTEGER,
    is_completed INTEGER,
    completed_at INTEGER,
    synced_at INTEGER
);

-- Sync status (extended per research: support sync tokens)
CREATE TABLE sync_status (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at INTEGER
);

-- Indexes (optimized per research)
CREATE INDEX idx_events_calendar_id ON events(calendar_id);
CREATE INDEX idx_events_external_id ON events(external_id) WHERE external_id IS NOT NULL;

-- Date range queries (common for calendar views)
CREATE INDEX idx_events_date_range ON events(calendar_id, start_date_utc, end_date_utc);

-- Recurring event lookups
CREATE INDEX idx_events_master ON events(master_event_id) WHERE master_event_id IS NOT NULL;

-- Sync queries
CREATE INDEX idx_events_updated ON events(updated_at);

CREATE INDEX idx_attendees_event_id ON attendees(event_id);
CREATE INDEX idx_attendees_email ON attendees(email);

-- FTS5 index (using GRDB synchronize pattern from research)
-- Note: Use GRDB.swift's synchronize(withTable:) for automatic sync
CREATE VIRTUAL TABLE events_fts USING fts5(
    summary,
    description,
    location,
    attendee_names,               -- denormalized for search
    content='events',
    content_rowid='rowid',
    tokenize='porter unicode61'
);
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
        t.column("eventkit_id", .text)
        t.column("title", .text).notNull()
        t.column("source_type", .text)
        t.column("color", .text)
        t.column("is_subscribed", .boolean).notNull().defaults(to: false)
        t.column("is_immutable", .boolean).notNull().defaults(to: false)
        t.column("synced_at", .integer)
    }

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
        t.column("start_date_utc", .integer).notNull()
        t.column("end_date_utc", .integer).notNull()
        t.column("start_timezone", .text)
        t.column("end_timezone", .text)
        t.column("is_all_day", .boolean).notNull().defaults(to: false)
        t.column("recurrence_rule", .text)
        t.column("master_event_id", .text)
        t.column("occurrence_date", .integer)
        t.column("status", .text)
        t.column("created_at", .integer)
        t.column("updated_at", .integer)
        t.column("synced_at", .integer)
    }

    // Indexes
    try db.create(index: "idx_events_date_range",
                  on: "events",
                  columns: ["calendar_id", "start_date_utc", "end_date_utc"])
}

migrator.registerMigration("v2_add_fts") { db in
    try db.create(virtualTable: "events_fts", using: FTS5()) { t in
        t.synchronize(withTable: "events")
        t.tokenizer = .porter()
        t.column("summary")
        t.column("description")
        t.column("location")
    }
}
```

## JSON Output Format

### ClaudEA Contract

All JSON output uses this envelope:

```json
{
  "version": "1.0",
  "query": "<optional filter description>",
  "total": 3,
  "items": [...]
}
```

### Event Item Schema

```json
{
  "id": "cal-abc123",
  "title": "1:1 with Alice",
  "calendar": "Work",
  "calendar_id": "cal-work-123",
  "start": "2026-01-15T10:00:00",
  "end": "2026-01-15T11:00:00",
  "is_all_day": false,
  "location": "Conference Room A",
  "description": "Weekly sync on project status",
  "url": null,
  "status": "confirmed",
  "is_recurring": true,
  "attendees": [
    {
      "name": "Alice Smith",
      "email": "alice@example.com",
      "response_status": "accepted",
      "is_organizer": false
    },
    {
      "name": "You",
      "email": "you@example.com",
      "response_status": "accepted",
      "is_organizer": true
    }
  ]
}
```

### Usage by ClaudEA

- **Briefing agenda**: `swiftea cal list --upcoming --json`
- **Meeting prep**: `swiftea cal show <id> --json`
- **Date range**: `swiftea cal list --date-range 2026-01-15:2026-01-15 --json`

## Risks / Trade-offs

| Risk | Impact | Mitigation |
|------|--------|------------|
| EventKit permission denied | Module non-functional | Clear error message with permission grant instructions |
| Large calendars (10k+ events) | Slow initial sync | Progress reporting, date-range limits, incremental sync |
| Recurring event explosion | Database bloat | Configurable expansion window (default: 1 year) |
| iCloud sync lag | Stale data | Document limitation, provide `--force-refresh` |
| Attendee email privacy | Data exposure | User owns their data; privacy is user's responsibility |
| iOS 18.4+/macOS 15.4+ regression | Access denied when updating calendars | Document limitation; read-only scope mitigates (from research) |
| TCC differences for CLI | Permission prompts unreliable | Consider signed app bundle target; follow `macos-calendar-events` patterns |
| Siri Suggestions calendar | Invalid ID crashes | Filter out calendars with no valid identifier (from research) |
| calendarItemExternalIdentifier nil | Fallback ID needed | Store multiple IDs; use hash fallback for pre-sync events |
| EKCalendar not Sendable | Threading issues | Cache only identifiers/properties, not EKCalendar objects (from research) |

## Anti-Patterns to Avoid

From research findings:

1. **Don't store unbounded recurring instances** - Cap by window (±365 days), regenerate incrementally
2. **Don't store times in local timezone** - Always store UTC, convert for display
3. **Don't use standalone FTS tables** - Use `synchronize(withTable:)` to prevent drift
4. **Don't rely on FTS5 availability** - Ensure SQLite build supports FTS5 before depending on it
5. **Don't save/delete objects from different EKEventStore instances** - Cross-store operations fail
6. **Don't assume requestAccess callback is on main thread** - Hop to MainActor when updating state

## Performance Targets

- Initial sync (10k events): < 60 seconds
- Incremental sync: < 10 seconds
- FTS search: < 2 seconds
- Event lookup by ID: < 100ms

## Open Questions (Resolved)

1. **Reminder support**: Include read-only reminders data in mirror, defer CLI commands to Phase 3.

2. **All-day event handling**: Store with `is_all_day` flag, let export format handle display.

3. **Attendee privacy**: Index names and emails; privacy is user's responsibility.
