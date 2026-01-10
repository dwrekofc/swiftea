---
title: Add Calendar Module Foundation
goals:
  - SG-1  # Unified PIM Access
  - SG-2  # Cross-Module Intelligence
  - SG-4  # ClaudEA-Ready Output
  - SG-6  # Modular Extensibility
status: draft
created: 2026-01-09
---

# Add Calendar Module Foundation

## Goal Alignment

This change advances:

- **SG-1 (Unified PIM Access)**: Adds calendar events to SwiftEA's unified CLI interface, enabling `swiftea cal` commands alongside `swiftea mail`
- **SG-2 (Cross-Module Intelligence)**: Establishes foundation for linking events to emails and contacts via attendee data and shared identifiers
- **SG-4 (ClaudEA-Ready Output)**: JSON output format designed for ClaudEA consumption - daily briefings, meeting prep, and task creation
- **SG-6 (Modular Extensibility)**: Follows the established Mail Module pattern, proving the modular monolith architecture works across data types

## Why

SwiftEA currently provides mail access but lacks calendar integration. ClaudEA's daily workflow depends on calendar data for:
- Morning briefing agenda generation
- Meeting prep with attendee context
- Task creation from calendar commitments
- People CRM enrichment from attendees

Without calendar access, ClaudEA cannot function as a complete executive assistant. This module fills that gap by providing programmatic CLI access to macOS calendar data via EventKit.

## What Changes

- New `CalendarModule` under `Sources/SwiftEAKit/Modules/`
- New CLI commands: `swiftea cal sync|search|show|list|export`
- libSQL mirror database for calendars, events, attendees, reminders
- FTS5 search index on event summary, description, location, attendee names
- Stable event ID generation (iCalendar UID primary, hash fallback)
- Export formats: Markdown (Obsidian), JSON (ClaudEA), ICS (RFC 5545)
- Incremental sync and watch mode via LaunchAgent

## Scope

### In Scope

- EventKit data access with permission handling
- libSQL mirror (calendars, events, attendees, reminders, sync_status)
- Stable ID generation (iCalendar UID primary, hash fallback)
- FTS5 search on summary, description, location, attendee names
- CLI commands: `sync`, `search`, `show`, `list`, `export`
- Export formats: Markdown (YAML frontmatter), JSON (ClaudEA-ready), ICS
- Incremental sync and watch mode
- ClaudEA integration: JSON output compatible with `ce` CLI consumption
- Attendee export: Name, email, response status for people CRM
- Meeting prep support: `--with-attendees` flag for briefing generation

### Out of Scope

- Cross-module linking in SwiftEA (ClaudEA handles via `links` table)
- Event creation/modification (AppleScript actions - separate proposal)
- Reminder-specific CLI commands (Phase 3)
- Direct Obsidian plugin (ClaudEA intermediates)

## ClaudEA Integration

### Data Flow

```
Apple Calendar → EventKit → SwiftEA (mirror DB) → JSON/MD → ClaudEA → Obsidian
```

### Consumption Patterns

| ClaudEA Feature | SwiftEA Provides |
|-----------------|------------------|
| Morning briefing agenda | `swiftea cal list --upcoming --json` |
| Meeting prep `[[prep→]]` | `swiftea cal show <id> --json` (with attendees) |
| Task creation from events | Stable event IDs for `tasks.source_ref` |
| Meeting notes linking | Stable IDs for `meeting_notes.calendar_event_ref` |
| People CRM enrichment | Attendee names/emails for `people` table |

### Critical Contract: Stable Event IDs

ClaudEA's `meeting_notes.calendar_event_ref` and `tasks.source_ref` reference SwiftEA's stable calendar event IDs. These IDs must:
- Remain stable across sync cycles
- Survive calendar app restarts
- Enable reverse lookup (ID → full event details)

## Impact

- **Files/modules affected**: New `CalendarModule/` under `Sources/SwiftEAKit/Modules/`, new CLI commands in `SwiftEACLI/`
- **Breaking changes**: None (new module)
- **Migration needed**: None (new module)
- **Existing code reuse**: VaultContext, database patterns from MailDatabase, CLI command structure from MailCommand

## References

- Master plan: `.d-spec/swiftea-architecture-master-plan.md` (Phase 2 - Calendar)
- Roadmap: `.d-spec/roadmap.md` (Phase 2 - Calendar & Unified Search)
- Mail spec (pattern to follow): `.d-spec/planning/specs/mail/spec.md`
- ClaudEA workflows: `.d-spec/planning/claudea-workflows-user-journey-master-vision.md`
- ClaudEA architecture: `.d-spec/planning/claudea-architecture-data-vision.md`
