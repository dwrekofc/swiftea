# External Integrations

**Analysis Date:** 2026-01-15

## APIs & External Services

**macOS System Integration:**
- Mail.app - Email data source via AppleScript automation
  - SDK/Client: AppleScript via `NSAppleScript` (wrapped in `Sources/SwiftEAKit/Modules/MailModule/AppleScriptService.swift`)
  - Auth: macOS Automation permission (System Settings > Privacy & Security > Automation)
  - Data: Message metadata, content, mailbox structure
  - Read-only access to inbox for bidirectional sync via `Sources/SwiftEAKit/Modules/MailModule/MailSyncBackward.swift`

- Calendar.app - Calendar/event data source
  - SDK/Client: EventKit framework (`import EventKit`)
  - Auth: Calendar access permission (automatic prompt via EventKit)
  - Data: Events, calendars, attendees, reminders
  - Access via `Sources/SwiftEAKit/Modules/CalendarModule/CalendarDataAccess.swift`

**No External APIs:**
- No cloud services, REST APIs, or third-party SaaS integrations
- All data processing is local to macOS

## Data Storage

**Databases:**
- libSQL (Mail data)
  - Connection: File path at `<vault>/.swiftea/mail.db`
  - Client: `libsql-swift` 0.3.0+ package
  - Implementation: `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
  - WAL mode enabled for concurrent access
  - Schema versioning with migrations

- GRDB/SQLite (Calendar data)
  - Connection: File path at `<vault>/.swiftea/calendar.db` (inferred from pattern)
  - Client: `GRDB.swift` 7.0.0+ package
  - Implementation: `Sources/SwiftEAKit/Modules/CalendarModule/CalendarDatabase.swift`
  - FTS5 full-text search enabled
  - WAL mode enabled

- Native SQLite3 (Mail.app Envelope Index - read-only)
  - Connection: `~/Library/Mail/V10/MailData/Envelope Index`
  - Client: Direct SQLite3 C API (`import SQLite3`)
  - Implementation: `Sources/SwiftEAKit/Modules/MailModule/EnvelopeIndexDiscovery.swift`
  - Read-only access for message metadata discovery

**File Storage:**
- Local filesystem only
- EMLX file parsing for mail message bodies at `~/Library/Mail/V10/*/Messages/` via `Sources/SwiftEAKit/Modules/MailModule/EmlxParser.swift`
- Export output written to vault directory (Markdown, iCalendar formats)

**Caching:**
- In-memory thread detection cache in `Sources/SwiftEAKit/Modules/MailModule/ThreadCache.swift`
- Database-backed sync state tracking via `sync_status` tables

## Authentication & Identity

**Auth Provider:**
- macOS system-level permissions only
  - Mail.app automation permission (required for AppleScript execution)
  - Calendar.app access permission (required for EventKit)
  - Full Disk Access may be required for Mail.app directory access
  - Implementation: Permission checks in `Sources/SwiftEAKit/Modules/MailModule/AppleScriptService.swift` with error mapping

**No credential storage:**
- No passwords, API keys, or tokens
- Relies on macOS Keychain for mail account credentials (accessed via Mail.app)

## Monitoring & Observability

**Error Tracking:**
- None (local CLI tool)

**Logs:**
- stdout/stderr only
- Structured error types per module:
  - `MailDatabaseError` in `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
  - `CalendarDatabaseError` in `Sources/SwiftEAKit/Modules/CalendarModule/CalendarDatabase.swift`
  - `AppleScriptError` with recovery guidance in `Sources/SwiftEAKit/Modules/MailModule/AppleScriptService.swift`

## CI/CD & Deployment

**Hosting:**
- Local installation only (no cloud hosting)
- Installed to `~/.local/bin/swea` via Makefile

**CI Pipeline:**
- GitHub Actions (`.github/workflows/ci.yml`)
  - Platform: macos-14 runners
  - Swift version: 6.0
  - Jobs: Build, test on push/PR to main branch

**Performance Monitoring:**
- GitHub Actions benchmarks (`.github/workflows/benchmarks.yml`)
  - Runs performance tests on PR and compares to main baseline
  - Posts results as PR comments
  - Manual trigger via workflow_dispatch

## Environment Configuration

**Required env vars:**
- None (all configuration via JSON files)

**Secrets location:**
- No secrets required
- Mail/calendar credentials managed by macOS Keychain (not accessed directly by swea)

**Config files:**
- `<vault>/.swiftea/config.json` - Vault-specific configuration
  - Mail settings: export format, watch interval
  - Calendar settings: date range, recurrence expansion
  - Account bindings
- Example: `test-vault/.swiftea/config.json`

## Webhooks & Callbacks

**Incoming:**
- None (local CLI application)

**Outgoing:**
- None

## File System Integration

**Read Locations:**
- `~/Library/Mail/V10/MailData/Envelope Index` - Mail.app SQLite database (read-only)
- `~/Library/Mail/V10/*/Messages/*.emlx` - Individual email message files (read-only)
- `<vault>/.swiftea/config.json` - Vault configuration

**Write Locations:**
- `<vault>/.swiftea/mail.db` - Mail mirror database
- `<vault>/.swiftea/swiftea.db` - Main vault database (inferred)
- `<vault>/Swiftea/` - Export output directory (Markdown, iCalendar)

**Watch/Polling:**
- Optional mail watch daemon (`watchEnabled` in config)
- Sync interval configurable (default 300 seconds per `test-vault/.swiftea/config.json`)

---

*Integration audit: 2026-01-15*
