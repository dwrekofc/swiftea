# d-spec Planning Summary

**Analysis Date:** 2026-01-15

## Overview

The `.d-spec/planning/` directory contains the ideation, proposal, and specification pipeline for SwiftEA development. This document summarizes existing ideas, change proposals, and planning artifacts organized by status and feature area.

## Planning Workflow

**Workflow:** Idea → Interview → Change Proposal → Approval → Ralph-TUI Beads → Implementation

**Directory Structure:**
- Ideas (active): `.d-spec/planning/ideas/`
- Ideas (processed): `.d-spec/planning/ideas/archive/`
- Change proposals (active): `.d-spec/planning/changes/`
- Change proposals (archived): `.d-spec/planning/archive/`
- Capability specs: `.d-spec/planning/specs/`

---

## Active Change Proposals

### Calendar Module Foundation

**Location:** `.d-spec/planning/changes/add-calendar-module-foundation-2026-01-09/`

**Status:** Draft

**Goal Alignment:**
- SG-1 (Unified PIM Access)
- SG-2 (Cross-Module Intelligence)
- SG-4 (ClaudEA-Ready Output)
- SG-6 (Modular Extensibility)

**Scope:**
- EventKit data access with permission handling
- libSQL mirror for calendars, events, attendees, reminders
- Stable event ID generation (iCalendar UID primary, hash fallback)
- FTS5 search on event summary, description, location, attendee names
- CLI commands: `sync`, `search`, `show`, `list`, `export`
- Export formats: Markdown (YAML frontmatter), JSON (ClaudEA-ready), ICS
- Incremental sync and watch mode

**Files:**
- `proposal.md` - Change proposal with goal alignment and scope
- `design.md` - Architecture and design decisions
- `tasks.md` - Parallel track execution model (Phases 0-3)
- `research-swift-eventkit-patterns.md` - EventKit research findings
- `specs/calendar/spec.md` - Calendar capability specification

**Dependencies:**
- GRDB.swift (SQLite persistence with FTS5)
- ICalendarKit (ICS export per RFC 5545)
- RWMRecurrenceRule (RRULE parsing, optional)

**Beads Epic:** Not yet created (awaiting approval)

**Key Feature Areas:**
- Multi-ID strategy (eventkit_id, external_id, fallback hash)
- UTC timestamp storage with timezone preservation
- Attendee tracking for ClaudEA people CRM
- Meeting prep support with `--with-attendees` flag
- Cross-module linking foundation (events ↔ emails ↔ contacts)

---

## Archived Ideas

### Swift Mail CLI Foundation

**Location:** `.d-spec/planning/ideas/archive/swift-mail-cli-idea.md`

**Status:** Processed (2026-01-09)

**Description:** Original vision for accessing Apple Mail programmatically via SQLite database and .emlx files. Introduced the three-layer architecture: Read (SQLite), Content (.emlx), Action (AppleScript).

**Related Changes:**
- `add-mail-read-export` (Beads: swiftea-7im) - SQL + content layer
- `add-mail-actions-applescript` (Beads: swiftea-01t) - Action layer
- `add-threading` (Beads: swiftea-az6) - Email conversation threading

**Roadmap:** Phase 1 focus - establishes foundation for Mail module

---

### Swift Mail Threads UI

**Location:** `.d-spec/planning/ideas/archive/swift-mail-threads_UI.md`

**Status:** Archived (future GUI work)

**Description:** GUI features for thread visualization (expandable conversation trees, thread timeline, participant activity). Parked for Phase 7 (GUI Layer) per CLI-first architecture philosophy.

---

## Archived Change Proposals

### Add Email Threading Support

**Location:** `.d-spec/planning/archive/2026-01-09-add-threading.md`

**Status:** Archived (2026-01-09)

**Beads Epic:** swiftea-az6

**Goal Alignment:** SG-2 (Cross-Module Intelligence)

**Key Decisions:**
- BREAKING schema changes for thread metadata (threads table, thread_messages junction)
- Header-based threading via Message-ID, References, In-Reply-To headers
- New CLI commands: `swiftea mail threads`, `swiftea mail thread --id`
- Thread-aware markdown/JSON exports with conversation grouping
- Performance targets: <5s detection for 100k emails, <2s queries

**Files:**
- `proposal.md` - Approved change proposal
- `design.md` - Threading algorithm design
- `tasks.md` - Task breakdown for Beads epic
- `specs/mail/spec.md` - Mail spec delta with threading requirements

**Progress:** 0/30 tasks closed (not started)

---

### Add Mail Read/Export/Watch Foundation

**Location:** `.d-spec/planning/archive/changes/add-mail-read-export/`

**Status:** Archived

**Beads Epic:** swiftea-7im

**Goal Alignment:**
- SG-1 (Unified PIM Access)
- SG-3 (Data Liberation)
- SG-5 (Local-First Architecture)

**Key Features:**
- libSQL mirror of Apple Mail SQLite database
- Near-real-time sync with `sync --watch` (launchd agent)
- Deterministic, stable email IDs (hash-based)
- Markdown and JSON export with Obsidian-friendly frontmatter
- Attachment metadata indexing (no extraction by default)

**Files:**
- `proposal.md` - Approved change proposal
- `tasks.md` - Task breakdown
- `specs/mail/spec.md` - Mail capability spec

---

### Add Mail Actions via AppleScript

**Location:** `.d-spec/planning/archive/2026-01-09-add-mail-actions-applescript.md`

**Status:** Archived (2026-01-09)

**Beads Epic:** swiftea-01t

**Goal Alignment:**
- SG-4 (ClaudEA-Ready Output)
- SG-6 (Modular Extensibility)

**Key Features:**
- CLI subcommands: archive, delete, move, flag, mark read/unread, draft, reply, send
- AppleScript execution via OSAKit/Apple Events
- Safety controls: `--yes` for destructive actions, `--dry-run` support
- SwiftEA ID → Mail.app message resolution

**Progress:** 0/8 tasks closed (not started)

---

### Add Vault-Scoped Account Binding

**Location:** `.d-spec/planning/archive/changes/add-vault-scoped-account-binding-2026-01-08/`

**Status:** Archived

**Beads Epic:** swiftea-294

**Key Features:**
- Vault-scoped config at `<vault>/.swiftea/config.json`
- `swiftea vault init --path <vault>` command
- Account binding via multi-select from macOS Internet Accounts
- One-vault-per-account enforcement
- Standardized vault layout: `<vault>/Swiftea/{mail,calendar,contacts,metadata,attachments,logs}`

**Files:**
- `proposal.md` - Approved change proposal
- `design.md` - Vault architecture design
- `tasks.md` - Task breakdown
- `specs/vaults/spec.md` - Vault capability spec

---

### Add Master Folder Structure

**Location:** `.d-spec/planning/archive/2026-01-08-create-master-app-folder-structure.md`

**Status:** Archived (2026-01-08)

**Description:** Created modular monolith layout (Core, Modules, CLI, Tests) per SwiftEA architecture master plan. Ensures Swift Package Manager builds CLI binary and internal modules with clear boundaries.

**Beads Epic:** swiftea-btu

**Spec:** `.d-spec/planning/specs/project-structure/spec.md`

---

## Current Capability Specs

These specs define the stable contracts for SwiftEA capabilities.

### Mail Capability

**Location:** `.d-spec/planning/specs/mail/spec.md`

**Purpose:** Complete technical specification for SwiftEA Mail Module

**Key Sections:**
- Three-layer architecture (Read/Content/Action)
- Database mirroring and sync strategies
- Custom metadata schema
- FTS5 full-text search
- Export formats (Markdown, JSON, ICS)
- Email actions via AppleScript
- CLI command structure
- ClaudEA integration patterns

**Status:** Approved as SwiftEA Mail Module Specification (v2.0)

**Last Updated:** 2026-01-06

---

### Vault Capability

**Location:** `.d-spec/planning/specs/vaults/spec.md`

**Purpose:** Vault-scoped configuration, account binding, and data storage

**Key Features:**
- Vault-local config and database
- Account binding with conflict prevention
- Standardized vault layout
- Multi-vault support

---

### Project Structure Capability

**Location:** `.d-spec/planning/specs/project-structure/spec.md`

**Purpose:** Modular monolith file structure and Swift Package Manager configuration

**Structure:**
```
SwiftEA/
├── Sources/
│   ├── SwiftEAKit/         # Core + Modules
│   │   ├── Core/
│   │   └── Modules/
│   │       ├── MailModule/
│   │       ├── CalendarModule/
│   │       └── ContactsModule/
│   └── SwiftEACLI/         # CLI commands
├── Tests/
└── Package.swift
```

---

## Active Ideas

### Swift Mail CLI Spec

**Location:** `.d-spec/planning/ideas/swift-mail-cli-spec.md`

**Status:** Active (living specification)

**Description:** Comprehensive specification for SwiftEA Mail Module. Describes the three-layer architecture, ClaudEA integration patterns, and complete CLI interface.

**Key Topics:**
- Universal email access via SQLite
- Data liberation to markdown/JSON
- AppleScript automation layer
- Cross-module intelligence
- Search excellence with FTS5
- Custom metadata and AI insights

**Note:** This appears to be a duplicate of the mail spec. May need consolidation with `.d-spec/planning/specs/mail/spec.md`.

---

## Planning Themes & Feature Areas

### Phase 1: Foundation (Mail + Core)

**Status:** In progress

**Focus Areas:**
- Vault bootstrap (swiftea-294)
- Core infrastructure (database, sync, search, export)
- Mail module read/export (swiftea-7im)
- Threading support (swiftea-az6) - **completed**
- Apple Mail actions (swiftea-01t)

**Beads Epics:**
- swiftea-btu (Master folder structure)
- swiftea-294 (Vault-scoped account binding)
- swiftea-7im (Mail read/export/watch)
- swiftea-az6 (Email threading) - 0/30 tasks
- swiftea-01t (Mail actions AppleScript) - 0/8 tasks

---

### Phase 2: Calendar & Unified Search

**Status:** Planning (1 active proposal)

**Focus Areas:**
- Calendar module (draft proposal ready)
- Contacts module (future)
- Cross-module linking
- Unified search improvements

**Proposals:**
- `add-calendar-module-foundation-2026-01-09` (draft, awaiting approval)

**Roadmap:** `.d-spec/roadmap.md` Phase 2

---

### Phase 3: Reminders & Advanced Search

**Status:** Future

**Focus Areas:**
- Reminders module
- Context assembly (project-based gathering)
- Advanced metadata
- JSON output for ClaudEA

**Roadmap:** `.d-spec/roadmap.md` Phase 3

---

### Phase 7: GUI Layer

**Status:** Future (CLI-first philosophy)

**Focus Areas:**
- SwiftUI native macOS app
- Thread visualization (priority)
- Unified dashboard
- Cross-module navigation

**Prerequisites:** CLI commands must be stable and feature-complete

**Roadmap:** `.d-spec/roadmap.md` Phase 7

---

## Goal Alignment Summary

All proposals must reference SwiftEA strategic goals from `.d-spec/swiftea-architecture-master-plan.md`.

**Goal Coverage by Active/Recent Changes:**

| Goal | Description | Referenced By |
|------|-------------|---------------|
| SG-1 | Unified PIM Access | Mail read/export, Calendar foundation |
| SG-2 | Cross-Module Intelligence | Threading, Calendar foundation |
| SG-3 | Data Liberation | Mail read/export |
| SG-4 | ClaudEA-Ready Output | Calendar foundation, Mail actions |
| SG-5 | Local-First Architecture | Mail read/export |
| SG-6 | Modular Extensibility | Calendar foundation, Mail actions |

**All core goals are actively being addressed.**

---

## Key Cross-References

**Master Plan:**
- `.d-spec/swiftea-architecture-master-plan.md` - Vision and strategic goals

**Roadmap:**
- `.d-spec/roadmap.md` - Phase-based implementation plan

**Project Standards:**
- `.d-spec/project.md` - Architecture and conventions

**Workflow Documentation:**
- `.d-spec/CLAUDE.md` - d-spec planning workflow
- `.d-spec/onboarding/discovery-to-spec.md` - Creating proposals
- `.d-spec/commands/ralph-tui.md` - Ralph-TUI execution

**ClaudEA Context:**
- `.d-spec/claudea-swiftea-ecosystem-master-plan.md` - Upstream ecosystem vision

---

## Metrics & Progress

**Total Planning Documents:** 34 markdown files

**Active Proposals:** 1 (Calendar module foundation)

**Archived Proposals:** 5 (Mail read/export, Threading, Mail actions, Vault binding, Folder structure)

**Active Beads Epics:** 5 total
- swiftea-btu (Folder structure)
- swiftea-294 (Vault binding)
- swiftea-7im (Mail read/export)
- swiftea-az6 (Threading) - 0/30 tasks
- swiftea-01t (Mail actions) - 0/8 tasks

**Capability Specs:** 3 (Mail, Vaults, Project Structure)

**Ideas Processed:** 2 (Swift Mail CLI Foundation, Swift Mail Threads UI)

---

## Recent Activity Timeline

**2026-01-09:**
- Archived 4 change proposals (Threading, Mail actions, Mail read/export idea duplicates)
- Created Beads epics for approved changes

**2026-01-08:**
- Created vault-scoped account binding proposal
- Created master folder structure proposal

**2026-01-07:**
- Created threading proposal
- Created mail actions proposal

**2026-01-06:**
- Approved mail module specification (v2.0)

---

## Next Steps

### For Current Phase (Phase 1)

1. **Execute active Beads epics:**
   - swiftea-az6 (Threading) - 30 tasks pending
   - swiftea-01t (Mail actions) - 8 tasks pending

2. **Review calendar proposal:**
   - Approve or iterate `add-calendar-module-foundation-2026-01-09`
   - Create Beads epic if approved

### For Planning Pipeline

1. **Validate active ideas:**
   - Consolidate `swift-mail-cli-spec.md` with mail spec if duplicate

2. **Prepare Phase 2 proposals:**
   - Contacts module foundation
   - Cross-module linking
   - Unified search enhancements

3. **Document Phase 1 learnings:**
   - Update conventions based on Mail module implementation
   - Document testing patterns
   - Capture concerns/technical debt

---

## Finding Documents

**To find an idea:**
```bash
ls .d-spec/planning/ideas/
ls .d-spec/planning/ideas/archive/
```

**To find a change proposal:**
```bash
ls .d-spec/planning/changes/
ls .d-spec/planning/archive/changes/
```

**To find capability specs:**
```bash
ls .d-spec/planning/specs/*/spec.md
```

**To track Beads progress:**
```bash
bd list --label ralph
bd show <epic-id>
```

---

*Planning analysis: 2026-01-15*
