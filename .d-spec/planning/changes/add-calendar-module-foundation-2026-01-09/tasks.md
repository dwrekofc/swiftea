# Calendar Module Foundation - Tasks

## 1. EventKit Data Access Layer
- [ ] 1.1 Create `CalendarDataAccess` class with EventKit integration
- [ ] 1.2 Implement permission request flow with `EKEventStore.requestFullAccessToEvents`
- [ ] 1.3 Implement permission error handling with user guidance (System Settings path)
- [ ] 1.4 Implement calendar discovery (list all calendars with metadata: title, source, color)
- [ ] 1.5 Implement event query by date range and calendar filter
- [ ] 1.6 Implement attendee extraction from `EKEvent.attendees`
- [ ] 1.7 Implement reminder query (read-only, for future use)
- [ ] 1.8 Add unit tests for permission handling and data access mocks

## 2. Calendar Mirror Schema
- [ ] 2.1 Create `CalendarDatabase.swift` following `MailDatabase` pattern
- [ ] 2.2 Define `calendars` table (id, eventkit_id, title, source_type, color, is_subscribed, is_immutable, synced_at)
- [ ] 2.3 Define `events` table (id, eventkit_id, calendar_id, summary, description, location, url, start_date, end_date, is_all_day, recurrence_rule, master_event_id, status, created_at, updated_at, synced_at)
- [ ] 2.4 Define `attendees` table (id, event_id, name, email, response_status, is_organizer)
- [ ] 2.5 Define `reminders` table (id, eventkit_id, calendar_id, title, notes, due_date, priority, is_completed, completed_at, synced_at)
- [ ] 2.6 Define `sync_status` table (key, value)
- [ ] 2.7 Add indexes for calendar_id, start_date, end_date, master_event_id, attendee email
- [ ] 2.8 Add FTS5 index for summary, description, location, attendee_names
- [ ] 2.9 Add FTS triggers to keep index in sync on insert/update/delete
- [ ] 2.10 Add migration/init routines for first-run setup
- [ ] 2.11 Add unit tests for schema creation and migrations

## 3. Stable ID Generation
- [ ] 3.1 Create `CalendarIdGenerator.swift` following `StableIdGenerator` pattern
- [ ] 3.2 Implement primary ID using iCalendar UID (`calendarItemExternalIdentifier`)
- [ ] 3.3 Implement fallback hash: SHA-256(calendar_id + summary + start_time)
- [ ] 3.4 Implement ID validation (32 lowercase hex digits)
- [ ] 3.5 Store EventKit identifier for reverse lookup
- [ ] 3.6 Add unit tests for ID generation consistency across sync cycles

## 4. Sync Engine
- [ ] 4.1 Create `CalendarSync.swift` following `MailSync` pattern
- [ ] 4.2 Define `CalendarSyncProgress` struct with phases (discovering, syncing, indexing, complete)
- [ ] 4.3 Define `CalendarSyncResult` struct (eventsProcessed, eventsAdded, eventsUpdated, eventsDeleted, calendarsProcessed, duration, errors)
- [ ] 4.4 Implement full sync: query all calendars and events, rebuild mirror
- [ ] 4.5 Implement calendar sync (upsert calendars table)
- [ ] 4.6 Implement event sync with stable ID generation
- [ ] 4.7 Implement attendee sync (delete existing, insert fresh from EventKit)
- [ ] 4.8 Implement recurring event expansion (configurable window, default 1 year)
- [ ] 4.9 Implement incremental sync: query events modified since last sync
- [ ] 4.10 Implement deletion detection: soft-delete events missing from EventKit
- [ ] 4.11 Implement reminder sync (read-only, separate table)
- [ ] 4.12 Track sync status and last sync time per calendar
- [ ] 4.13 Implement progress callback for CLI feedback
- [ ] 4.14 Add integration tests for sync operations

## 5. Watch Mode (LaunchAgent)
- [ ] 5.1 Implement `swiftea cal sync --watch` LaunchAgent installation
- [ ] 5.2 Create LaunchAgent plist template with configurable interval
- [ ] 5.3 Implement periodic sync loop (default: 5 minutes)
- [ ] 5.4 Implement wake-from-sleep catch-up sync
- [ ] 5.5 Implement `swiftea cal sync --watch-status` to show LaunchAgent state
- [ ] 5.6 Implement `swiftea cal sync --watch-stop` to uninstall LaunchAgent

## 6. Search & Query
- [ ] 6.1 Implement FTS search across summary, description, location, attendee_names
- [ ] 6.2 Implement structured query filters: --calendar, --date-range, --attendee
- [ ] 6.3 Implement date range parsing (YYYY-MM-DD:YYYY-MM-DD format)
- [ ] 6.4 Implement --upcoming filter (events from now forward)
- [ ] 6.5 Implement JSON envelope output for search/query
- [ ] 6.6 Implement BM25 ranking for search relevance
- [ ] 6.7 Add unit tests for search functionality

## 7. CLI Commands
- [ ] 7.1 Create `CalendarCommand.swift` as ParsableCommand with subcommands
- [ ] 7.2 Implement `swiftea cal sync` (--calendar, --incremental, --watch, --verbose)
- [ ] 7.3 Implement `swiftea cal search <query>` (--calendar, --date-range, --attendee, --limit, --json)
- [ ] 7.4 Implement `swiftea cal show <id>` (--ics, --json, --with-attendees)
- [ ] 7.5 Implement `swiftea cal list` (--calendar, --upcoming, --date-range, --limit, --json)
- [ ] 7.6 Implement `swiftea cal export` (--calendar, --date-range, --format, --output)
- [ ] 7.7 Implement `swiftea cal calendars` (list available calendars with metadata)
- [ ] 7.8 Add integration tests for CLI commands

## 8. Export Formats
- [ ] 8.1 Create `CalendarExporter.swift` for format handling
- [ ] 8.2 Implement Markdown export with YAML frontmatter (Obsidian-compatible)
- [ ] 8.3 Implement JSON export with ClaudEA-ready envelope structure
- [ ] 8.4 Implement ICS export (RFC 5545 standard)
- [ ] 8.5 Implement attendee inclusion in all formats
- [ ] 8.6 Implement flat-folder output structure (calendar/meetings/)
- [ ] 8.7 Track export paths in database (optional)
- [ ] 8.8 Add unit tests for export format correctness

## 9. Configuration
- [ ] 9.1 Add calendar module config keys to VaultConfig
- [ ] 9.2 Implement `calendar.default_calendar` setting
- [ ] 9.3 Implement `calendar.date_range_days` setting (default: 365)
- [ ] 9.4 Implement `calendar.sync_interval_minutes` setting (default: 5)
- [ ] 9.5 Implement `calendar.expand_recurring` setting (default: true)
- [ ] 9.6 Implement `swiftea config calendar.*` read/write commands
- [ ] 9.7 Document configuration options in README

## 10. Documentation & Tests
- [ ] 10.1 Write CalendarModule README with usage examples
- [ ] 10.2 Add end-to-end integration tests with test calendar data
- [ ] 10.3 Document permission requirements and troubleshooting
- [ ] 10.4 Document ClaudEA integration patterns (JSON contract, ID stability)
- [ ] 10.5 Update CLI help text with examples
- [ ] 10.6 Add performance benchmarks (10k event sync, search latency)
- [ ] 10.7 Document migration from direct SQLite approach (if applicable)
