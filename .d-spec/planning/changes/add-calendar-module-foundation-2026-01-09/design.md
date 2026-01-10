# Calendar Module Design

## Context

SwiftEA Phase 2 introduces Calendar as the second PIM module. The Mail Module established patterns for data mirroring, FTS search, and export. Calendar extends these patterns but differs in data source (EventKit vs SQLite) and data model (recurring events, attendees, all-day events).

Calendar is a critical dependency for ClaudEA's daily workflow - morning briefings, meeting prep, and task creation all require calendar data.

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

### 2. Stable ID Strategy

**Decision**: Use iCalendar UID as primary ID, with hash fallback.

**Primary**: `calendarItemExternalIdentifier` (iCalendar UID per RFC 5545)
- Stable across sync cycles
- Standard format used by all calendar systems
- Survives calendar app restarts

**Fallback** (when UID unavailable): SHA-256 hash of:
- `calendar_id + summary + start_time`

**Storage**: Store both:
- `id` (stable public ID)
- `eventkit_id` (EventKit's internal identifier for reverse lookup)

**Why this matters**: ClaudEA's `meeting_notes.calendar_event_ref` and `tasks.source_ref` reference these IDs. Unstable IDs would break cross-system linking.

### 3. Recurrence Handling

**Decision**: Store both master events and expanded occurrences.

**Approach**:
- Master event stores `recurrence_rule` (RRULE string)
- Individual occurrences stored as separate rows with `master_event_id` reference
- Expansion limited to configurable window (default: 1 year forward)

**Rationale**:
- Users search for individual occurrences ("next standup")
- ClaudEA briefings need specific dates, not rules
- FTS indexes individual occurrences

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

### 5. Reminders as Separate Entities

**Decision**: Store reminders in separate table, defer CLI commands.

**Approach**:
- EventKit unifies calendars and reminders via EKEventStore
- Store reminders in `reminders` table during sync
- CLI commands for reminders deferred to Phase 3

**Rationale**:
- Reminders have different semantics (due date, completion)
- Mirror now for data availability
- CLI later to avoid scope creep

### 6. All-Day Event Handling

**Decision**: Store with `is_all_day` flag and date-only values.

**Approach**:
- `is_all_day INTEGER` (boolean flag)
- When true, `start_date` and `end_date` store dates (not datetimes)
- Export formats handle display appropriately

**Rationale**:
- Preserves original event semantics
- Avoids timezone complications for date-only events
- ClaudEA can format appropriately for briefings

### 7. Sync Strategy

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
    id TEXT PRIMARY KEY,           -- stable ID
    eventkit_id TEXT,              -- EventKit identifier
    title TEXT NOT NULL,
    source_type TEXT,              -- local, iCloud, Exchange, caldav, etc.
    color TEXT,                    -- hex color code
    is_subscribed INTEGER,         -- boolean
    is_immutable INTEGER,          -- boolean
    synced_at INTEGER              -- timestamp
);

-- Events
CREATE TABLE events (
    id TEXT PRIMARY KEY,           -- stable ID (iCalendar UID or hash)
    eventkit_id TEXT,              -- EventKit identifier
    calendar_id TEXT REFERENCES calendars(id),
    summary TEXT,
    description TEXT,
    location TEXT,
    url TEXT,
    start_date INTEGER,            -- timestamp
    end_date INTEGER,              -- timestamp
    is_all_day INTEGER,            -- boolean
    recurrence_rule TEXT,          -- RRULE string
    master_event_id TEXT,          -- reference to master for occurrences
    status TEXT,                   -- confirmed, tentative, cancelled
    created_at INTEGER,
    updated_at INTEGER,
    synced_at INTEGER
);

-- Attendees
CREATE TABLE attendees (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT REFERENCES events(id),
    name TEXT,
    email TEXT,
    response_status TEXT,          -- accepted, declined, tentative, none
    is_organizer INTEGER           -- boolean
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

-- Sync status
CREATE TABLE sync_status (
    key TEXT PRIMARY KEY,
    value TEXT
);

-- Indexes
CREATE INDEX idx_events_calendar_id ON events(calendar_id);
CREATE INDEX idx_events_start_date ON events(start_date);
CREATE INDEX idx_events_end_date ON events(end_date);
CREATE INDEX idx_events_is_all_day ON events(is_all_day);
CREATE INDEX idx_events_master_event_id ON events(master_event_id);
CREATE INDEX idx_attendees_event_id ON attendees(event_id);
CREATE INDEX idx_attendees_email ON attendees(email);

-- FTS5 index
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

## Performance Targets

- Initial sync (10k events): < 60 seconds
- Incremental sync: < 10 seconds
- FTS search: < 2 seconds
- Event lookup by ID: < 100ms

## Open Questions (Resolved)

1. **Reminder support**: Include read-only reminders data in mirror, defer CLI commands to Phase 3.

2. **All-day event handling**: Store with `is_all_day` flag, let export format handle display.

3. **Attendee privacy**: Index names and emails; privacy is user's responsibility.
