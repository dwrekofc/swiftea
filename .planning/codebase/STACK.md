# Technology Stack

**Analysis Date:** 2026-01-15

## Languages

**Primary:**
- Swift 6.0+ - All application code (CLI, core library, tests)

**Secondary:**
- AppleScript - Mail.app and Calendar.app automation via `Sources/SwiftEAKit/Modules/MailModule/AppleScriptService.swift` and `Sources/SwiftEAKit/Core/AccountDiscovery.swift`
- SQL - Database schema migrations and queries in `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift` and `Sources/SwiftEAKit/Modules/CalendarModule/CalendarDatabase.swift`

## Runtime

**Environment:**
- macOS 14+ (Sonoma or later)
- Swift 6.2.3 (development), Swift 6.0+ (minimum required per `Package.swift`)

**Package Manager:**
- Swift Package Manager (SPM)
- Lockfile: `Package.resolved` present
- Build configuration: `Package.swift` with swift-tools-version 6.0

## Frameworks

**Core:**
- Swift Standard Library - Foundation framework for core utilities
- EventKit - macOS calendar/reminder data access in `Sources/SwiftEAKit/Modules/CalendarModule/`
- AppKit - macOS GUI integration for Mail.app automation in `Sources/SwiftEACLI/Commands/MailCommand.swift`
- CryptoKit - Hash generation for stable IDs in `Sources/SwiftEAKit/Modules/MailModule/ThreadIDGenerator.swift` and `Sources/SwiftEAKit/Modules/CalendarModule/CalendarIdGenerator.swift`

**Testing:**
- XCTest - Swift's built-in testing framework (24 test files)

**Build/Dev:**
- Make - Build automation via `Makefile` (build, install, test targets)
- swift-build - Native Swift Package Manager build system

## Key Dependencies

**Critical:**
- `libsql-swift` 0.3.0+ - Primary database for mail data, used in `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
  - Turso's libSQL fork of SQLite with enhanced features
  - Connection via `import Libsql`
- `GRDB.swift` 7.0.0+ - Type-safe SQLite wrapper for calendar data in `Sources/SwiftEAKit/Modules/CalendarModule/CalendarDatabase.swift`
  - FTS5 full-text search support
  - Type-safe migrations and queries
- `swift-argument-parser` 1.3.0+ - CLI command-line parsing framework used throughout `Sources/SwiftEACLI/Commands/`
- `icalendarkit` 1.0.0+ - iCalendar format export support in `Sources/SwiftEAKit/Modules/CalendarModule/CalendarExporter.swift`

**Infrastructure:**
- SQLite3 - Direct SQLite3 access for Mail.app's Envelope Index in `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- Foundation - Core data types, file I/O, date/time handling

## Configuration

**Environment:**
- Per-vault config stored in `<vault>/.swiftea/config.json`
- Config structure:
  - `version`: "1.0"
  - `accounts`: array of account bindings
  - `mail`: mail module settings (exportFormat, watchEnabled, watchSyncInterval)
  - `calendar`: calendar settings (dateRangeDays, expandRecurring, exportFormat)
- No environment variables required for core functionality

**Build:**
- `Package.swift` - SPM package manifest (dependencies, targets, platforms)
- `Makefile` - Build shortcuts (PREFIX defaults to `~/.local`)
- WAL mode enabled for SQLite databases (concurrent read/write access)
- Compiler flags: Swift 6.0 language mode

## Platform Requirements

**Development:**
- macOS 14+ with Xcode Command Line Tools or Xcode 15+
- Swift 6.0+ toolchain
- Disk access permissions for Mail.app data (`~/Library/Mail/`)
- Automation permissions for Mail.app and Calendar.app (via System Settings > Privacy & Security > Automation)

**Production:**
- macOS 14+ (deployment target per `Package.swift`)
- Install via `make install` to `~/.local/bin/swea` (or custom PREFIX)
- Access to Mail.app V10 database at `~/Library/Mail/V10/MailData/Envelope Index`
- EventKit calendar access (prompts user for permission on first use)

## CI/CD

**GitHub Actions:**
- `.github/workflows/ci.yml` - Build and test on macos-14 runners with Swift 6.0
- `.github/workflows/benchmarks.yml` - Performance benchmarks on macos-14 with release builds
  - Benchmark comparison between PR and main branch
  - Results posted as PR comments

---

*Stack analysis: 2026-01-15*
