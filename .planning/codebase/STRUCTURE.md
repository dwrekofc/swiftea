# Codebase Structure

**Analysis Date:** 2026-01-15

## Directory Layout

```
swiftea/
├── .swiftea/                 # Vault metadata (created per-vault, not in repo)
├── .d-spec/                  # Planning and ideation documents
│   ├── onboarding/          # Agent workflow guides
│   ├── planning/            # Ideas, changes, specs
│   └── commands/            # Command reference docs
├── .beads/                   # Task tracker database
├── .planning/                # Codebase mapping documents
│   └── codebase/            # Architecture, conventions, testing docs
├── Sources/                  # Swift source code
│   ├── SwiftEA/             # Main executable entry point
│   ├── SwiftEACLI/          # CLI command implementations
│   └── SwiftEAKit/          # Core business logic library
│       ├── Core/            # Shared infrastructure
│       └── Modules/         # PIM data source modules
├── Tests/                    # Test suites
│   ├── SwiftEACLITests/     # CLI command tests
│   └── SwiftEAKitTests/     # Business logic tests
├── test-vault/               # Test data for development
├── docs/                     # Documentation
├── scripts/                  # Build and automation scripts
├── Package.swift             # Swift Package Manager manifest
├── Makefile                  # Build shortcuts
└── CLAUDE.md                 # Agent instructions
```

## Directory Purposes

**Sources/SwiftEA:**
- Purpose: Main executable entry point
- Contains: `main.swift` with top-level command configuration
- Key files: `Sources/SwiftEA/main.swift`

**Sources/SwiftEACLI:**
- Purpose: Command-line interface layer
- Contains: ArgumentParser-based command implementations
- Key files:
  - `Commands/MailCommand.swift`: Mail sync, search, export, actions
  - `Commands/CalendarCommand.swift`: Calendar sync, search, export
  - `Commands/ContactsCommand.swift`: Contacts sync and export
  - `Commands/VaultCommand.swift`: Vault initialization and management
  - `Commands/ConfigCommand.swift`: Configuration management
  - `Commands/SyncCommand.swift`: Unified sync command
  - `Commands/SearchCommand.swift`: Cross-module search
  - `Commands/ExportCommand.swift`: Unified export command
  - `Commands/StatusCommand.swift`: Vault status reporting

**Sources/SwiftEAKit/Core:**
- Purpose: Shared infrastructure for all modules
- Contains: Vault management, account discovery, configuration
- Key files:
  - `VaultManager.swift`: Vault lifecycle (init, detect, config I/O)
  - `VaultContext.swift`: Vault context validation and resolution
  - `AccountDiscovery.swift`: Discover Mail/Calendar accounts via AppleScript
  - `BindingRegistry.swift`: Global account-to-vault binding registry
  - `SwiftEAKit.swift`: Library entry point

**Sources/SwiftEAKit/Modules/MailModule:**
- Purpose: Apple Mail data access and synchronization
- Contains: Sync services, database, parsers, exporters
- Key files:
  - `MailSync.swift`: Primary sync orchestrator (Apple DB → libSQL)
  - `MailSyncBackward.swift`: Bidirectional sync (libSQL → Apple Mail.app)
  - `MailSyncParallel.swift`: Parallel message processing
  - `MailDatabase.swift`: libSQL mirror database with FTS5 search
  - `EmlxParser.swift`: Parse .emlx message files
  - `MailExporter.swift`: Export to markdown files
  - `ThreadDetectionService.swift`: Email threading logic
  - `ThreadIDGenerator.swift`: Generate stable thread IDs
  - `MessageResolver.swift`: Resolve message references
  - `AppleScriptService.swift`: Execute AppleScript for write operations
  - `EnvelopeIndexDiscovery.swift`: Locate Apple's Envelope.index database

**Sources/SwiftEAKit/Modules/CalendarModule:**
- Purpose: Apple Calendar data access and synchronization
- Contains: Sync services, database, exporters
- Key files:
  - `CalendarSync.swift`: EventKit-based sync orchestrator
  - `CalendarDatabase.swift`: GRDB database for calendar events
  - `CalendarDataAccess.swift`: EventKit API wrapper
  - `CalendarExporter.swift`: Export to ICS or markdown
  - `CalendarModels.swift`: GRDB record types
  - `CalendarIdGenerator.swift`: Generate stable event IDs

**Sources/SwiftEAKit/Modules/ContactsModule:**
- Purpose: Apple Contacts data access (placeholder)
- Contains: `.gitkeep` (not yet implemented)

**Tests/SwiftEAKitTests:**
- Purpose: Unit and integration tests for business logic
- Contains: Tests for sync, database, parsers, core services
- Key files:
  - `MailSyncBackwardTests.swift`
  - `AppleScriptServiceTests.swift`

**Tests/SwiftEACLITests:**
- Purpose: CLI command integration tests
- Contains: Tests for command parsing and execution

**Tests/TestData:**
- Purpose: Fixtures for test execution
- Contains: Sample .emlx files for parser tests

**.d-spec:**
- Purpose: Planning, ideation, and specifications
- Contains: Master plan, project conventions, roadmap, change proposals
- Key files:
  - `swiftea-architecture-master-plan.md`: North star vision
  - `project.md`: Architecture, tech stack, conventions
  - `roadmap.md`: Implementation roadmap
  - `planning/ideas/`: New feature ideas
  - `planning/changes/`: Approved change proposals

**.beads:**
- Purpose: Ralph-TUI task tracker database
- Contains: SQLite database with user stories and epics
- Generated: Yes
- Committed: No

**.planning/codebase:**
- Purpose: Codebase mapping for GSD commands
- Contains: Architecture, conventions, testing docs
- Generated: Yes (by mapper agents)
- Committed: Yes

**test-vault:**
- Purpose: Development test environment
- Contains: Sample vault with Swiftea/ data folder structure
- Generated: Yes
- Committed: Partially (structure committed, data ignored)

## Key File Locations

**Entry Points:**
- `Sources/SwiftEA/main.swift`: CLI entry point
- `Sources/SwiftEACLI/Commands/*.swift`: Subcommand entry points

**Configuration:**
- `Package.swift`: Swift Package Manager configuration
- `Makefile`: Build and test shortcuts
- `.swiftea/config.json`: Per-vault configuration (not in repo)
- `~/.config/swiftea/account-bindings.json`: Global account registry

**Core Logic:**
- `Sources/SwiftEAKit/Core/VaultManager.swift`: Vault operations
- `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`: Mail sync
- `Sources/SwiftEAKit/Modules/CalendarModule/CalendarSync.swift`: Calendar sync

**Testing:**
- `Tests/SwiftEAKitTests/*.swift`: Business logic tests
- `Tests/SwiftEACLITests/*.swift`: CLI tests
- `Tests/TestData/emlx/*.emlx`: Test fixtures

## Naming Conventions

**Files:**
- Swift files: `PascalCase.swift` (e.g., `MailDatabase.swift`, `VaultManager.swift`)
- Commands: `{Noun}Command.swift` (e.g., `MailCommand.swift`, `ConfigCommand.swift`)
- Tests: `{TargetName}Tests.swift` (e.g., `MailSyncBackwardTests.swift`)

**Directories:**
- Modules: `{PascalCase}Module` (e.g., `MailModule`, `CalendarModule`)
- Core directories: lowercase (e.g., `docs`, `scripts`)
- Hidden/config: dot-prefix (e.g., `.swiftea`, `.d-spec`, `.beads`)

**Types:**
- Structs/Classes: `PascalCase` (e.g., `VaultContext`, `MailDatabase`)
- Protocols: `PascalCase` (e.g., `Sendable`, `ParsableCommand`)
- Enums: `PascalCase` with lowercase cases (e.g., `AccountType.mail`, `SyncPhase.complete`)
- Errors: `{Context}Error` (e.g., `VaultError`, `MailDatabaseError`)

## Where to Add New Code

**New CLI Command:**
- Primary code: `Sources/SwiftEACLI/Commands/{Noun}Command.swift`
- Register in: `Sources/SwiftEA/main.swift` subcommands array
- Tests: `Tests/SwiftEACLITests/{Noun}CommandTests.swift`

**New Module (PIM Data Source):**
- Implementation: `Sources/SwiftEAKit/Modules/{Name}Module/`
- Required files: `{Name}Sync.swift`, `{Name}Database.swift`, `{Name}Exporter.swift`
- Tests: `Tests/SwiftEAKitTests/{Name}*.swift`

**New Core Service:**
- Implementation: `Sources/SwiftEAKit/Core/{Service}.swift`
- Tests: `Tests/SwiftEAKitTests/{Service}Tests.swift`

**Shared Utilities:**
- Shared helpers: `Sources/SwiftEAKit/Core/` (if cross-module)
- Module-specific helpers: `Sources/SwiftEAKit/Modules/{Module}/` (if single-module)

**Configuration Extension:**
- Vault config: Update `VaultConfig` struct in `Sources/SwiftEAKit/Core/VaultManager.swift`
- Module settings: Add `{Module}Settings` struct to `VaultManager.swift`

**Database Schema:**
- Mail: Update migrations in `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
- Calendar: Update migrations in `Sources/SwiftEAKit/Modules/CalendarModule/CalendarDatabase.swift`

## Special Directories

**.swiftea:**
- Purpose: Per-vault metadata directory (created by `swea init`)
- Generated: Yes (per vault)
- Committed: No (vault-specific, not in repo)
- Contents: `config.json` (vault config), `swiftea.db` (libSQL database)

**.build:**
- Purpose: Swift Package Manager build artifacts
- Generated: Yes
- Committed: No

**.swiftpm:**
- Purpose: Swift Package Manager workspace metadata
- Generated: Yes
- Committed: No

**Swiftea/ (within vault):**
- Purpose: User-facing data folder for exports
- Generated: Yes (by `swea init`)
- Committed: No (vault-specific)
- Structure: `Mail/`, `Calendar/`, `Contacts/`, `Exports/`

**.d-spec/planning/archive:**
- Purpose: Archived change proposals and ideas
- Generated: Yes (by archiving workflow)
- Committed: Yes
- Contents: Completed changes with YAML traceability

---

*Structure analysis: 2026-01-15*
