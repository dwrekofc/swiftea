# Calendar Capability Spec

## ADDED Requirements

### Requirement: EventKit Data Access
The calendar module SHALL use EventKit framework for accessing macOS calendar data. The system SHALL request calendar access permission on first use and SHALL fail with actionable guidance when permission is denied.

#### Scenario: Permission granted
- **WHEN** the user runs `swiftea cal sync` for the first time
- **AND** grants calendar access permission
- **THEN** the system SHALL discover all accessible calendars
- **AND** SHALL proceed with sync

#### Scenario: Permission denied
- **WHEN** the user runs `swiftea cal sync`
- **AND** calendar access permission is denied
- **THEN** the system SHALL return a permission error
- **AND** SHALL provide steps to grant Calendar access in System Settings > Privacy & Security > Calendars

#### Scenario: Permission not yet requested
- **WHEN** the user runs any `swiftea cal` command for the first time
- **THEN** the system SHALL request full calendar access via EventKit
- **AND** SHALL wait for user response before proceeding

### Requirement: Calendar Mirror Database
The system SHALL mirror EventKit calendar data into a libSQL database. The mirror SHALL include calendars, events, attendees, reminders, and sync status.

#### Scenario: Initial mirror build
- **WHEN** the user runs `swiftea cal sync` for the first time
- **THEN** the system SHALL query all calendars from EventKit
- **AND** SHALL query all events within the configured date range
- **AND** SHALL populate the libSQL mirror with calendar and event data
- **AND** SHALL index events for full-text search

#### Scenario: Incremental mirror update
- **WHEN** an event changes in Apple Calendar
- **AND** the user runs `swiftea cal sync --incremental`
- **THEN** the system SHALL refresh only changed records in the libSQL mirror
- **AND** SHALL update the FTS index for affected events

#### Scenario: Database location
- **WHEN** the calendar module initializes
- **THEN** the system SHALL create `calendar.db` in the vault's data folder
- **AND** SHALL use the same libSQL driver as the mail module

### Requirement: Stable Event Identifiers
Each mirrored event SHALL have a stable, public ID. The system SHALL use the iCalendar UID (`calendarItemExternalIdentifier`) as primary identifier. When unavailable, the system SHALL generate a deterministic hash from calendar_id + summary + start_time.

#### Scenario: ID generation with iCalendar UID
- **WHEN** an event has a valid `calendarItemExternalIdentifier`
- **THEN** the system SHALL use this as the stable public ID
- **AND** SHALL store the EventKit identifier for reverse lookup

#### Scenario: ID generation without iCalendar UID
- **WHEN** an event lacks a `calendarItemExternalIdentifier`
- **THEN** the system SHALL generate a SHA-256 hash from calendar_id + summary + start_time
- **AND** SHALL log a warning about fallback ID generation

#### Scenario: ID persistence across syncs
- **WHEN** the same event is synced multiple times
- **THEN** the system SHALL generate the same stable ID each time
- **AND** SHALL NOT create duplicate event records

### Requirement: Full-Text Search Index
The mirror SHALL include an FTS5 index with columns for summary, description, location, and attendee_names. Search SHALL query all indexed fields by default.

#### Scenario: Search across event fields
- **WHEN** a user runs `swiftea cal search "standup"`
- **THEN** the system SHALL return events matching summary, description, location, or attendees
- **AND** SHALL rank results using FTS5 BM25

#### Scenario: Search with no results
- **WHEN** a user searches for a term with no matches
- **THEN** the system SHALL return an empty result set
- **AND** SHALL NOT return an error

### Requirement: CLI Sync Command
The CLI SHALL provide `swiftea cal sync` with options for calendar filtering, incremental sync, watch mode, and verbosity.

#### Scenario: Full sync
- **WHEN** the user runs `swiftea cal sync`
- **THEN** the system SHALL query all events and rebuild the mirror
- **AND** SHALL report sync progress and statistics

#### Scenario: Incremental sync
- **WHEN** the user runs `swiftea cal sync --incremental`
- **THEN** the system SHALL query only events modified since last sync
- **AND** SHALL update affected records without full rebuild

#### Scenario: Calendar-scoped sync
- **WHEN** the user runs `swiftea cal sync --calendar "Work"`
- **THEN** the system SHALL sync only the specified calendar
- **AND** SHALL skip other calendars

#### Scenario: Verbose output
- **WHEN** the user runs `swiftea cal sync --verbose`
- **THEN** the system SHALL display detailed progress for each phase
- **AND** SHALL report individual event processing

### Requirement: CLI Search Command
The CLI SHALL provide `swiftea cal search` with query string and filtering options.

#### Scenario: Basic search
- **WHEN** the user runs `swiftea cal search "project review"`
- **THEN** the system SHALL return matching events
- **AND** SHALL display event summary, date, and calendar

#### Scenario: Filtered search
- **WHEN** the user runs `swiftea cal search "meeting" --calendar "Work" --date-range 2026-01-01:2026-01-31`
- **THEN** the system SHALL return events matching query within date range for specified calendar

#### Scenario: JSON output
- **WHEN** the user runs `swiftea cal search "meeting" --json`
- **THEN** the system SHALL return results in JSON envelope format
- **AND** SHALL include all event fields and attendees

#### Scenario: Limited results
- **WHEN** the user runs `swiftea cal search "meeting" --limit 10`
- **THEN** the system SHALL return at most 10 results
- **AND** SHALL indicate total count in output

### Requirement: CLI Show Command
The CLI SHALL provide `swiftea cal show` to display a single event by ID.

#### Scenario: Show event details
- **WHEN** the user runs `swiftea cal show <event-id>`
- **THEN** the system SHALL display full event details including summary, dates, location, description, and attendees

#### Scenario: Show as ICS
- **WHEN** the user runs `swiftea cal show <event-id> --ics`
- **THEN** the system SHALL output the event in RFC 5545 ICS format

#### Scenario: Show as JSON
- **WHEN** the user runs `swiftea cal show <event-id> --json`
- **THEN** the system SHALL output the event in ClaudEA-ready JSON format
- **AND** SHALL include full attendee details

#### Scenario: Event not found
- **WHEN** the user runs `swiftea cal show <invalid-id>`
- **THEN** the system SHALL return an error with message "Event not found"
- **AND** SHALL exit with code 3

### Requirement: CLI List Command
The CLI SHALL provide `swiftea cal list` to list events with optional filtering.

#### Scenario: List upcoming events
- **WHEN** the user runs `swiftea cal list --upcoming`
- **THEN** the system SHALL display events from now forward
- **AND** SHALL limit to configured default (e.g., 50)

#### Scenario: List by calendar
- **WHEN** the user runs `swiftea cal list --calendar "Personal"`
- **THEN** the system SHALL display only events from the specified calendar

#### Scenario: List by date range
- **WHEN** the user runs `swiftea cal list --date-range 2026-01-15:2026-01-20`
- **THEN** the system SHALL display events within that date range
- **AND** SHALL include events that span the range boundaries

#### Scenario: List as JSON for ClaudEA briefing
- **WHEN** the user runs `swiftea cal list --upcoming --json`
- **THEN** the system SHALL return events in JSON envelope format
- **AND** SHALL include attendee details for meeting prep

### Requirement: CLI Export Command
The CLI SHALL provide `swiftea cal export` with format and output options.

#### Scenario: Export to Markdown
- **WHEN** the user runs `swiftea cal export --format markdown --output ~/vault/calendar`
- **THEN** the system SHALL export events to Markdown files with YAML frontmatter
- **AND** SHALL include: id, title, start, end, location, description, attendees, calendar
- **AND** SHALL name files `<id>.md`

#### Scenario: Export to JSON
- **WHEN** the user runs `swiftea cal export --format json`
- **THEN** the system SHALL output events as ClaudEA-ready JSON array to stdout

#### Scenario: Export to ICS
- **WHEN** the user runs `swiftea cal export --format ics --output ~/backup.ics`
- **THEN** the system SHALL output events in RFC 5545 ICS format
- **AND** SHALL include all events in a single calendar file

#### Scenario: Export filtered events
- **WHEN** the user runs `swiftea cal export --calendar "Work" --date-range 2026-01-01:2026-12-31 --format markdown --output ~/vault/work-calendar`
- **THEN** the system SHALL export only matching events

### Requirement: CLI Calendars Command
The CLI SHALL provide `swiftea cal calendars` to list available calendars.

#### Scenario: List calendars
- **WHEN** the user runs `swiftea cal calendars`
- **THEN** the system SHALL display all accessible calendars
- **AND** SHALL show: title, source type, color, subscribed status

#### Scenario: List calendars as JSON
- **WHEN** the user runs `swiftea cal calendars --json`
- **THEN** the system SHALL output calendar metadata in JSON format

### Requirement: Watch Mode
The system SHALL provide `swiftea cal sync --watch` to install and run a LaunchAgent that keeps the mirror synchronized.

#### Scenario: Watch startup
- **WHEN** the user runs `swiftea cal sync --watch`
- **THEN** the system SHALL install and start a LaunchAgent
- **AND** SHALL run an incremental sync before entering watch mode

#### Scenario: Periodic sync
- **WHEN** watch mode is active
- **AND** the configured interval (default: 5 minutes) elapses
- **THEN** the system SHALL run an incremental sync

#### Scenario: Watch status
- **WHEN** the user runs `swiftea cal sync --watch-status`
- **THEN** the system SHALL display whether the LaunchAgent is installed and running
- **AND** SHALL show last sync time

#### Scenario: Watch stop
- **WHEN** the user runs `swiftea cal sync --watch-stop`
- **THEN** the system SHALL stop and uninstall the LaunchAgent

### Requirement: Markdown Export Format
Markdown exports SHALL include YAML frontmatter compatible with Obsidian. Frontmatter SHALL contain: id, title, start, end, location, calendar, attendees, aliases (for Obsidian linking).

#### Scenario: Markdown file structure
- **WHEN** the user exports an event to Markdown
- **THEN** the system SHALL write `<id>.md` with YAML frontmatter
- **AND** SHALL include the event description as the body

#### Scenario: Markdown frontmatter
- **WHEN** the system generates YAML frontmatter
- **THEN** the system SHALL include:
  - `id`: stable event ID
  - `title`: event summary
  - `start`: ISO 8601 datetime
  - `end`: ISO 8601 datetime
  - `location`: location string (if present)
  - `calendar`: calendar name
  - `attendees`: list of attendee emails
  - `aliases`: list containing event summary (for Obsidian search)

### Requirement: JSON Output Envelope
JSON outputs for search, list, and export SHALL be wrapped in an envelope containing version, query/filters, total, and items.

#### Scenario: Search JSON output
- **WHEN** the user runs `swiftea cal search "meeting" --json`
- **THEN** the system SHALL return an envelope with:
  - `version`: "1.0"
  - `query`: the search query
  - `total`: number of results
  - `items`: array of event objects

#### Scenario: List JSON output
- **WHEN** the user runs `swiftea cal list --json`
- **THEN** the system SHALL return an envelope with query metadata
- **AND** SHALL include all event fields in items

### Requirement: Attendee Handling
The mirror SHALL store attendee information linked to events. Attendees SHALL include name, email, and response status (accepted, declined, tentative, none).

#### Scenario: Attendee storage
- **WHEN** an event has attendees
- **THEN** the system SHALL store attendee metadata in the attendees table
- **AND** SHALL link attendees to the event by event_id

#### Scenario: Attendee indexing
- **WHEN** an event has attendees
- **THEN** the system SHALL include attendee names in the FTS index
- **AND** SHALL enable search by attendee name

#### Scenario: Attendee JSON export
- **WHEN** the user exports an event with attendees to JSON
- **THEN** the system SHALL include for each attendee:
  - `name`: display name
  - `email`: email address
  - `response_status`: accepted, declined, tentative, or none
  - `is_organizer`: boolean

### Requirement: All-Day Event Handling
The system SHALL correctly handle all-day events. All-day events SHALL be stored with an `is_all_day` flag and date-only start/end values.

#### Scenario: All-day event sync
- **WHEN** an event is marked as all-day in Apple Calendar
- **THEN** the system SHALL store `is_all_day = true`
- **AND** SHALL store start_date and end_date as dates (not datetimes)

#### Scenario: All-day event display
- **WHEN** displaying an all-day event
- **THEN** the system SHALL format dates without time component
- **AND** SHALL indicate the event is all-day

### Requirement: Recurring Event Handling
The system SHALL handle recurring events by storing both the master event and expanded occurrences within the configured date range.

#### Scenario: Recurring event expansion
- **WHEN** a recurring event exists in Apple Calendar
- **THEN** the system SHALL store the recurrence rule on the master event
- **AND** SHALL store individual occurrences as separate rows with reference to master

#### Scenario: Recurring event search
- **WHEN** a user searches for a recurring event
- **THEN** the system SHALL return matching occurrences
- **AND** SHALL indicate which are recurring instances

#### Scenario: Expansion window
- **WHEN** the system expands recurring events
- **THEN** the system SHALL expand only within the configured window (default: 1 year)
- **AND** SHALL NOT create occurrences beyond the window

### Requirement: Database Schema
The mirror database SHALL include the following tables: calendars, events, attendees, reminders, sync_status.

#### Scenario: Events table structure
- **WHEN** the calendar module initializes
- **THEN** the system SHALL create an `events` table with columns:
  - `id` TEXT PRIMARY KEY (stable ID)
  - `eventkit_id` TEXT (EventKit internal identifier)
  - `calendar_id` TEXT FOREIGN KEY
  - `summary` TEXT
  - `description` TEXT
  - `location` TEXT
  - `url` TEXT
  - `start_date` INTEGER (timestamp)
  - `end_date` INTEGER (timestamp)
  - `is_all_day` INTEGER (boolean)
  - `recurrence_rule` TEXT (iCalendar RRULE)
  - `master_event_id` TEXT (for occurrences)
  - `status` TEXT (confirmed, tentative, cancelled)
  - `created_at` INTEGER
  - `updated_at` INTEGER
  - `synced_at` INTEGER

#### Scenario: Calendars table structure
- **WHEN** the calendar module initializes
- **THEN** the system SHALL create a `calendars` table with columns:
  - `id` TEXT PRIMARY KEY
  - `eventkit_id` TEXT
  - `title` TEXT
  - `source_type` TEXT (local, iCloud, Exchange, etc.)
  - `color` TEXT (hex color code)
  - `is_subscribed` INTEGER (boolean)
  - `is_immutable` INTEGER (boolean)
  - `synced_at` INTEGER

#### Scenario: Attendees table structure
- **WHEN** the calendar module initializes
- **THEN** the system SHALL create an `attendees` table with columns:
  - `id` INTEGER PRIMARY KEY AUTOINCREMENT
  - `event_id` TEXT FOREIGN KEY
  - `name` TEXT
  - `email` TEXT
  - `response_status` TEXT (accepted, declined, tentative, none)
  - `is_organizer` INTEGER (boolean)

### Requirement: Performance
Sync and search operations SHALL perform efficiently for calendars with 10k+ events.

#### Scenario: Sync performance
- **WHEN** the system syncs 10k events
- **THEN** initial sync SHALL complete within 60 seconds
- **AND** incremental sync SHALL complete within 10 seconds

#### Scenario: Search performance
- **WHEN** a user searches 10k events
- **THEN** search SHALL return results within 2 seconds
- **AND** SHALL use database indexes effectively

#### Scenario: Event lookup performance
- **WHEN** the user runs `swiftea cal show <id>`
- **THEN** lookup SHALL complete within 100ms

### Requirement: ClaudEA Integration
JSON output SHALL be designed for ClaudEA consumption, supporting daily briefings, meeting prep, and task creation.

#### Scenario: Briefing agenda generation
- **WHEN** ClaudEA runs `swiftea cal list --upcoming --json`
- **THEN** the output SHALL include all fields needed for morning briefing agenda
- **AND** SHALL include attendee names for meeting prep links

#### Scenario: Meeting prep
- **WHEN** ClaudEA runs `swiftea cal show <id> --json`
- **THEN** the output SHALL include full attendee details
- **AND** SHALL include event description for context

#### Scenario: Stable ID for task source
- **WHEN** ClaudEA creates a task from a calendar event
- **THEN** ClaudEA SHALL use the stable event ID for `tasks.source_ref`
- **AND** the ID SHALL enable reverse lookup via `swiftea cal show <id>`

#### Scenario: Stable ID for meeting notes
- **WHEN** ClaudEA creates a meeting note
- **THEN** ClaudEA SHALL use the stable event ID for `meeting_notes.calendar_event_ref`
- **AND** the ID SHALL remain valid across sync cycles
