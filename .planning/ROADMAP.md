# Roadmap: SwiftEA

## Overview

SwiftEA v1.0 delivers a complete CLI toolkit for macOS PIM data access, optimized for ClaudEA AI agent consumption. The journey starts with agent-readiness (making existing mail features consumable by AI), extends to calendar and contacts modules, adds cross-module intelligence, and finishes with performance optimization and public release.

## Milestones

- 🚧 **v1.0 ClaudEA-Ready CLI** - Phases 1-7 (in progress)
- 📋 **v2.0 AI Features** - Future (semantic search, AI summaries, priority scoring)
- 📋 **v3.0 GUI Layer** - Future (SwiftUI native macOS app)

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [ ] **Phase 1: Agent-Readiness Foundation** - Make SwiftEA consumable by ClaudEA agents
- [ ] **Phase 2: Calendar Module** - EventKit integration for calendar data access
- [ ] **Phase 3: Contacts Module** - AddressBook integration for contacts data access
- [ ] **Phase 4: Cross-Module Intelligence** - Unified search and cross-module linking
- [ ] **Phase 5: Reminders & Context Assembly** - Complete PIM coverage for ClaudEA
- [ ] **Phase 6: Performance & Reliability** - Production-grade performance at scale
- [ ] **Phase 7: Polish & OSS Release** - Public release readiness

## Phase Details

### Phase 1: Agent-Readiness Foundation
**Goal**: Make SwiftEA consumable by ClaudEA agents (score 2/10 → 9/10)
**Depends on**: Nothing (first phase)
**Requirements**: AF-01, AF-02, AF-03, AF-04, AF-05, AF-06, AF-07, AF-08, AF-09, AF-10, AF-11, P1-01, P1-02, P1-03
**Success Criteria** (what must be TRUE):
  1. ClaudEA can execute any command with `--json` and parse structured output
  2. ClaudEA can run in fully non-interactive mode with `--yes`/`--confirm` flags
  3. ClaudEA receives machine-readable error codes with recovery hints
  4. ClaudEA can inspect system state via `swiftea inspect --json`
  5. Message IDs remain stable across Mail.app database rebuilds
**Research**: Unlikely (internal patterns, existing codebase)
**Plans**: TBD

Plans:
- [ ] 01-01: JSON output infrastructure
- [ ] 01-02: Non-interactive mode and confirmation flags
- [ ] 01-03: Error code taxonomy
- [ ] 01-04: System inspection command
- [ ] 01-05: Stable ID improvements

### Phase 2: Calendar Module
**Goal**: EventKit integration for calendar data access
**Depends on**: Phase 1
**Requirements**: CAL-01, CAL-02, CAL-03, CAL-04, CAL-05
**Success Criteria** (what must be TRUE):
  1. User can see calendar events synced to local database
  2. User can search events by date, title, or attendee
  3. User can export events to markdown/JSON with frontmatter
  4. User can create/update/delete events via CLI
**Research**: Likely (EventKit patterns, RRULE parsing)
**Research topics**: EventKit framework, recurring event expansion, iCalendar export
**Plans**: TBD

Plans:
- [ ] 02-01: EventKit data access and sync
- [ ] 02-02: Calendar search and export
- [ ] 02-03: Calendar actions via AppleScript

### Phase 3: Contacts Module
**Goal**: AddressBook integration for contacts data access
**Depends on**: Phase 1
**Requirements**: CON-01, CON-02, CON-03, CON-04
**Success Criteria** (what must be TRUE):
  1. User can see contacts synced to local database
  2. User can search contacts by name/email/organization
  3. User can export contacts to markdown/JSON
**Research**: Likely (Contacts framework patterns)
**Research topics**: Contacts framework, AddressBook API, vCard export
**Plans**: TBD

Plans:
- [ ] 03-01: Contacts data access and sync
- [ ] 03-02: Contacts search and export
- [ ] 03-03: Contacts actions via AppleScript

### Phase 4: Cross-Module Intelligence
**Goal**: Unified search and cross-module linking
**Depends on**: Phase 2, Phase 3
**Requirements**: LINK-01, LINK-02, SEARCH-01
**Success Criteria** (what must be TRUE):
  1. User can search across mail, calendar, contacts in one query
  2. System automatically links emails to related events/contacts
  3. Search results show cross-module relationships
**Research**: Unlikely (internal FTS5, existing patterns)
**Plans**: TBD

Plans:
- [ ] 04-01: Cross-module linking infrastructure
- [ ] 04-02: Unified search command

### Phase 5: Reminders & Context Assembly
**Goal**: Complete PIM coverage for ClaudEA workflows
**Depends on**: Phase 4
**Requirements**: REM-01, CTX-01, META-01
**Success Criteria** (what must be TRUE):
  1. User can access Apple Reminders via CLI
  2. User can gather all context for a project with one command
  3. User can add custom metadata to any item
**Research**: Likely (EventKit Reminders API)
**Research topics**: EventKit reminders, context assembly patterns
**Plans**: TBD

Plans:
- [ ] 05-01: Reminders module
- [ ] 05-02: Context assembly command
- [ ] 05-03: Advanced metadata

### Phase 6: Performance & Reliability
**Goal**: Production-grade performance at scale
**Depends on**: Phase 5
**Requirements**: PERF-01, PERF-02, PERF-03, PERF-04, PERF-05
**Success Criteria** (what must be TRUE):
  1. Search returns results in <1s with 100k+ items
  2. Sync detects changes in real-time via FSEvents
  3. System recovers gracefully from errors with retry
**Research**: Likely (FSEvents, concurrent SQLite)
**Research topics**: FSEvents watchers, SQLite WAL mode optimization, parallel processing
**Plans**: TBD

Plans:
- [ ] 06-01: Performance optimization
- [ ] 06-02: Real-time sync with FSEvents
- [ ] 06-03: Error recovery and resilience

### Phase 7: Polish & OSS Release
**Goal**: Public release readiness
**Depends on**: Phase 6
**Requirements**: DOCS-01, DIST-01, COMM-01
**Success Criteria** (what must be TRUE):
  1. Users can install via `brew install swiftea`
  2. Documentation covers all commands and workflows
  3. Community can report issues and contribute
**Research**: Unlikely (documentation, packaging)
**Plans**: TBD

Plans:
- [ ] 07-01: Documentation and guides
- [ ] 07-02: Homebrew distribution
- [ ] 07-03: Community readiness

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Agent-Readiness Foundation | 0/5 | Not started | - |
| 2. Calendar Module | 0/3 | Not started | - |
| 3. Contacts Module | 0/3 | Not started | - |
| 4. Cross-Module Intelligence | 0/2 | Not started | - |
| 5. Reminders & Context | 0/3 | Not started | - |
| 6. Performance & Reliability | 0/3 | Not started | - |
| 7. Polish & OSS Release | 0/3 | Not started | - |

**Total:** 0/22 plans complete (0%)

---

*Roadmap created: 2026-01-16*
