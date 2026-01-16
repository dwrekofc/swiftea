# Architecture

**Analysis Date:** 2026-01-15

## Pattern Overview

**Overall:** Modular Monolith with Layered Architecture

**Key Characteristics:**
- Three-layer architecture: CLI commands, business logic (modules), and core infrastructure
- Module-based organization where each data source (Mail, Calendar, Contacts) is an independent module
- Vault-centric design where all operations require a local vault context
- Mirror database pattern: read from Apple's native SQLite databases, write to libSQL mirrors
- AppleScript bridge for write operations to native macOS apps

## Layers

**CLI Layer (SwiftEACLI):**
- Purpose: Command-line interface and user interaction
- Location: `Sources/SwiftEACLI/Commands/`
- Contains: ArgumentParser-based commands, CLI presentation logic, flag parsing
- Depends on: SwiftEAKit (business logic), ArgumentParser framework
- Used by: Main executable entry point
- Pattern: Command pattern with ParsableCommand protocol

**Business Logic Layer (SwiftEAKit/Modules):**
- Purpose: Domain logic for each PIM data source
- Location: `Sources/SwiftEAKit/Modules/{MailModule,CalendarModule,ContactsModule}/`
- Contains: Sync services, database managers, parsers, exporters, data access services
- Depends on: Core infrastructure, external databases (libSQL, GRDB), native macOS APIs
- Used by: CLI commands
- Pattern: Module pattern with self-contained functionality per data source

**Core Infrastructure Layer (SwiftEAKit/Core):**
- Purpose: Shared infrastructure and cross-module concerns
- Location: `Sources/SwiftEAKit/Core/`
- Contains: Vault management, account discovery, configuration, binding registry
- Depends on: Foundation, AppleScript execution
- Used by: All modules and CLI commands
- Pattern: Service objects with clear responsibilities

## Data Flow

**Mail Sync Flow (Read from Apple → Write to Mirror):**

1. CLI command (`MailCommand.sync`) obtains VaultContext
2. VaultContext provides database path and configuration
3. MailSync connects to Apple's Envelope.index (SQLite, read-only)
4. MailSync queries message metadata from Apple's database
5. EmlxParser reads message content from .emlx files on disk
6. ThreadDetectionService analyzes message headers for threading
7. MailDatabase writes data to libSQL mirror with FTS5 indexing
8. MailExporter generates markdown files in vault's Swiftea/Mail/ directory

**Calendar Sync Flow:**

1. CLI command (`CalendarCommand.sync`) obtains VaultContext
2. CalendarDataAccess uses EventKit framework to query native Calendar.app
3. CalendarDatabase writes events to GRDB database
4. CalendarExporter generates ICS or markdown files

**Vault-Centric Operations:**

1. All commands require VaultContext (via `VaultContext.require()`)
2. VaultContext verifies `.swiftea/` directory exists in current working directory
3. VaultManager provides paths to database, config, and data folders
4. BindingRegistry maps macOS account IDs to vault paths globally

**State Management:**
- VaultConfig stored as JSON in `.swiftea/config.json`
- Mirror databases maintain sync state and timestamps
- No in-memory caching beyond single operation scope

## Key Abstractions

**VaultContext:**
- Purpose: Represents a validated vault environment
- Examples: `Sources/SwiftEAKit/Core/VaultContext.swift`
- Pattern: Context object with validation and path resolution
- Usage: Required entry point for all vault-dependent operations

**Module Services (Sync/Database/Exporter):**
- Purpose: Encapsulate data source operations
- Examples: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`, `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`, `Sources/SwiftEAKit/Modules/MailModule/MailExporter.swift`
- Pattern: Service objects with clear read/write separation
- Usage: CLI commands instantiate and orchestrate these services

**Account Binding:**
- Purpose: Map macOS accounts to vault locations
- Examples: `Sources/SwiftEAKit/Core/BindingRegistry.swift`
- Pattern: Global registry with atomic file operations
- Usage: Prevents duplicate syncing across vaults

**Mirror Database:**
- Purpose: Local queryable copy of Apple's PIM data
- Examples: `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
- Pattern: Schema migration versioning, WAL mode for concurrency
- Usage: FTS5 full-text search, cross-module queries

## Entry Points

**Main Executable:**
- Location: `Sources/SwiftEA/main.swift`
- Triggers: User invokes `swea` command
- Responsibilities: Route to subcommands via ArgumentParser

**CLI Subcommands:**
- Location: `Sources/SwiftEACLI/Commands/{MailCommand,CalendarCommand,ContactsCommand}.swift`
- Triggers: User invokes `swea mail`, `swea cal`, etc.
- Responsibilities: Parse flags, validate context, orchestrate module operations

**Vault Initialization:**
- Location: `Sources/SwiftEAKit/Core/VaultManager.swift#initializeVault()`
- Triggers: User runs `swea init`
- Responsibilities: Create `.swiftea/` directory structure, initialize database, create canonical folders

## Error Handling

**Strategy:** Typed errors with localized descriptions, thrown and propagated up to CLI layer

**Patterns:**
- Custom error enums per domain (e.g., `MailDatabaseError`, `VaultError`, `MailSyncError`)
- Errors include underlying causes and context
- CLI commands catch errors and format for user output
- No silent failures; all errors propagate to user

## Cross-Cutting Concerns

**Logging:** Console output via `print()` and `fputs(stderr)` for errors. No structured logging framework currently.

**Validation:** VaultContext validates vault existence before operations. Account binding prevents duplicate syncs. Database migrations ensure schema compatibility.

**Authentication:** Uses macOS system permissions for database and file access. AppleScript operations may trigger macOS Automation permission prompts.

---

*Architecture analysis: 2026-01-15*
