# Calendar Module

SwiftEA Calendar Module provides read-only access to Apple Calendar (EventKit) data with local database mirroring, full-text search, and multi-format export.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLI Commands                              │
│  swiftea cal [calendars|list|show|search|export|sync]           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       CalendarSync                               │
│  Orchestrates sync from EventKit → GRDB mirror                  │
│  - Full sync / Incremental sync                                 │
│  - Progress reporting                                           │
│  - Error handling & recovery                                    │
└─────────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ CalendarData    │  │ CalendarId      │  │ CalendarDatabase│
│ Access          │  │ Generator       │  │                 │
│                 │  │                 │  │ GRDB + FTS5     │
│ EventKit API    │  │ Stable IDs      │  │ SQLite mirror   │
│ - Calendars     │  │ - External ID   │  │ - Events        │
│ - Events        │  │ - Hash fallback │  │ - Calendars     │
│ - Reminders     │  │ - Recurring IDs │  │ - Attendees     │
└─────────────────┘  └─────────────────┘  └─────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ CalendarExporter│
                    │ - Markdown      │
                    │ - JSON          │
                    │ - ICS (RFC 5545)│
                    └─────────────────┘
```

## Components

| File | Purpose |
|------|---------|
| `CalendarDataAccess.swift` | EventKit wrapper with permission handling |
| `CalendarDatabase.swift` | GRDB database with FTS5 search |
| `CalendarModels.swift` | Data models (StoredEvent, StoredCalendar, etc.) |
| `CalendarIdGenerator.swift` | Stable ID generation for cross-system references |
| `CalendarExporter.swift` | Multi-format export (Markdown, JSON, ICS) |
| `CalendarSync.swift` | Sync engine from EventKit to database |

## Permission Requirements

### Required Entitlements

For a signed app bundle, add to your entitlements:
```xml
<key>com.apple.security.personal-information.calendars</key>
<true/>
```

### Info.plist Keys

```xml
<key>NSCalendarsFullAccessUsageDescription</key>
<string>SwiftEA needs calendar access to sync and export events</string>
<key>NSCalendarsWriteOnlyAccessUsageDescription</key>
<string>SwiftEA needs to add events to your calendar</string>
```

### Permission Request Flow

The module uses macOS version-specific APIs:
- **macOS 14+**: `requestFullAccessToEvents()` - Returns `Bool` directly
- **macOS 13 and earlier**: `requestAccess(to: .event)` - Continuation-based

```swift
// Handled automatically by CalendarDataAccess.requestAccess()
if #available(macOS 14.0, *) {
    return try await eventStore.requestFullAccessToEvents()
} else {
    return try await eventStore.requestAccess(to: .event)
}
```

### Troubleshooting Permission Issues

**"Calendar access denied" error:**

1. Open **System Settings** > **Privacy & Security** > **Calendars**
2. Find SwiftEA (or Terminal if running from terminal)
3. Enable the toggle

**CLI binaries and TCC:**

Unsigned CLI binaries may have inconsistent permission prompt behavior. Options:
- Run from a signed app bundle
- Use Terminal.app (which has its own TCC entry)
- Grant Full Disk Access as fallback (not recommended)

## Multi-ID Strategy

EventKit provides three identifiers for events, each with different stability characteristics:

| Identifier | Source | Stability | Use Case |
|------------|--------|-----------|----------|
| `eventIdentifier` | Local | Stable locally; may change after sync | Fast local lookup |
| `calendarItemExternalIdentifier` | Server | Most stable for CalDAV/iCloud; can be nil | Cross-system references |
| `calendarIdentifier` | Calendar | Stable | Calendar-level operations |

### Why Multiple IDs?

1. **External ID is most stable** but may be `nil` before initial sync
2. **Event ID is fast** but changes when events sync to server
3. **Fallback hash** ensures local-only calendars still have stable IDs

### Public ID Selection

```swift
// Priority order for public-facing ID:
1. calendarItemExternalIdentifier (when non-nil)
2. SHA-256 hash of (calendar_id + summary + start_time)
```

### Recurring Event IDs

Recurring event instances combine the master event ID with occurrence date:
```
{master_event_id}_{occurrence_timestamp}
```

This ensures each occurrence has a unique, stable ID even though EventKit may return the same `eventIdentifier` for all occurrences.

## UTC Time Storage

All timestamps are stored in UTC with original timezone preserved separately.

### Why UTC?

- **Sorting**: UTC timestamps sort correctly regardless of user location
- **Range queries**: No timezone conversion needed for date comparisons
- **Travel safety**: Events don't shift when user changes timezones
- **Standard practice**: Matches how CalDAV servers store data

### Schema Columns

```sql
start_date_utc INTEGER,    -- Unix timestamp in UTC
end_date_utc INTEGER,      -- Unix timestamp in UTC
start_timezone TEXT,       -- Original timezone (e.g., "America/New_York")
end_timezone TEXT,         -- Original timezone for end (may differ)
is_all_day INTEGER         -- All-day events store date only
```

### Display Conversion

Timezone conversion happens only at display time:
```swift
// In CalendarDateFormatter
func formatRange(start: Int, end: Int, isAllDay: Bool, timezone: String?) -> String {
    // Convert UTC → display timezone for user-facing output
}
```

## Known Issues

### macOS 15.4+ Calendar Regression

Apple introduced a bug in macOS 15.4 (Sequoia) that may cause calendar access failures when attempting to modify calendars. This module is read-only and should not be affected, but be aware of this if extending with write operations.

**Workaround**: Stick to read-only operations until Apple fixes the regression.

### Siri Suggestions Calendar

The "Siri Suggestions" calendar is a system calendar with invalid identifiers that can crash EventKit queries.

**Mitigation**: `CalendarDataAccess` filters out calendars where:
- `calendarIdentifier` is empty or invalid
- Source is "Siri Suggestions"

```swift
// In getAllCalendars()
calendars.filter { calendar in
    !calendar.calendarIdentifier.isEmpty &&
    calendar.source?.title != "Siri Suggestions"
}
```

### Exchange (EWS) Calendars

Exchange Web Services calendars have different behavior:
- Events are stored on server, not as local files
- External identifiers may have different format
- Some metadata fields may be unavailable

The module handles these gracefully but export features may have limited data for EWS events.

## Configuration

Calendar settings are stored in the vault's `config.json`:

```json
{
  "calendar": {
    "defaultCalendar": null,
    "dateRangeDays": 365,
    "syncIntervalMinutes": 5,
    "expandRecurring": true,
    "exportFormat": "markdown",
    "exportOutputDir": null
  }
}
```

| Setting | Default | Description |
|---------|---------|-------------|
| `defaultCalendar` | `null` | Default calendar for new events (system default if null) |
| `dateRangeDays` | `365` | How far forward to sync events (1-3650 days) |
| `syncIntervalMinutes` | `5` | Watch daemon sync interval (1+ minutes) |
| `expandRecurring` | `true` | Whether to expand recurring events during sync |
| `exportFormat` | `"markdown"` | Default export format (markdown, json, ics) |
| `exportOutputDir` | `null` | Default export directory |

## Watch Mode

The calendar sync daemon supports continuous synchronization:

```bash
# Install and start watch daemon
swiftea cal sync --watch

# Check status
swiftea cal sync --status

# Stop daemon
swiftea cal sync --stop
```

The daemon:
- Syncs every 5 minutes (configurable)
- Responds to `EKEventStoreChangedNotification` for immediate updates
- Catches up after system wake from sleep
- Uses LaunchAgent for persistence across restarts

Logs are stored in: `<vault>/Swiftea/logs/cal-sync.log`

## CLI Commands

```bash
# List available calendars
swiftea cal calendars [--json]

# List upcoming events
swiftea cal list [--calendar NAME] [--from DATE] [--to DATE] [--limit N] [--json]

# Show event details
swiftea cal show <event-id> [--with-attendees] [--json] [--ics]

# Search events (FTS5)
swiftea cal search "query" [--calendar NAME] [--from DATE] [--to DATE] [--limit N] [--json]

# Export events
swiftea cal export [--calendar NAME] [--from DATE] [--to DATE] [--format md|json|ics] [--output PATH]

# Sync from EventKit
swiftea cal sync [--incremental] [--verbose]
swiftea cal sync --watch        # Start watch daemon
swiftea cal sync --status       # Check sync status
swiftea cal sync --stop         # Stop watch daemon
```

## JSON Output Format

All JSON output uses a consistent envelope:

```json
{
  "version": "1.0",
  "query": "optional search query",
  "total": 3,
  "items": [
    {
      "id": "cal-abc123",
      "title": "Team Meeting",
      "calendar": "Work",
      "calendarId": "cal-work-123",
      "start": "2026-01-15T10:00:00",
      "end": "2026-01-15T11:00:00",
      "isAllDay": false,
      "location": "Conference Room A",
      "description": "Weekly sync",
      "url": null,
      "status": "confirmed",
      "isRecurring": true,
      "attendees": [
        {
          "name": "Alice Smith",
          "email": "alice@example.com",
          "responseStatus": "accepted",
          "isOrganizer": false
        }
      ]
    }
  ]
}
```

## Performance Targets

| Operation | Target |
|-----------|--------|
| Initial sync (10k events) | < 60 seconds |
| Incremental sync | < 10 seconds |
| FTS search | < 2 seconds |
| Event lookup by ID | < 100ms |

## ClaudEA Integration

The Calendar module is designed for seamless integration with ClaudEA (Claude EA assistant) workflows.

### JSON Contract

ClaudEA expects JSON output from calendar commands with the following guarantees:

1. **Consistent envelope**: All JSON responses wrap items in `{ version, total, items }` envelope
2. **Stable IDs**: Event IDs remain stable across syncs for reliable cross-references
3. **ISO 8601 dates**: All timestamps in ISO 8601 format for easy parsing
4. **Attendee details**: Full attendee info for meeting prep workflows

### Example ClaudEA Workflows

**Morning briefing:**
```bash
# Get today's agenda
swiftea cal list --from $(date +%Y-%m-%d) --to $(date +%Y-%m-%d) --json
```

**Meeting prep:**
```bash
# Get detailed event info including attendees
swiftea cal show cal-abc123 --with-attendees --json
```

**Find available time:**
```bash
# Search for gaps by looking at scheduled events
swiftea cal list --from 2026-01-15 --to 2026-01-15 --json
```

### ID Stability for Cross-System References

ClaudEA uses calendar event IDs as foreign keys in:
- `meeting_notes.calendar_event_ref` - Links meeting notes to source event
- `tasks.source_ref` - Links tasks created from calendar events
- `contacts.last_meeting_ref` - Tracks last meeting with a contact

The multi-ID strategy ensures these references remain valid:

```
Priority: calendarItemExternalIdentifier > hash(calendar_id + summary + start)
```

**Why this matters**: If an event ID changed after sync, all ClaudEA references would break. The fallback hash ensures local-only calendars also have stable IDs.

### Recurring Event Handling

ClaudEA queries individual occurrences, not recurrence rules:

```bash
# "When is my next standup?" queries actual occurrence dates
swiftea cal search "standup" --from today --limit 1 --json
```

Each recurring instance has a unique ID combining master event ID + occurrence date:
```
cal-meeting-abc123_1705312800
```

This allows ClaudEA to reference specific occurrences (e.g., "reschedule next week's standup") without ambiguity.
