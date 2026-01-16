# Requirements: SwiftEA

## Overview

Requirements derived from PROJECT.md and the SwiftEA + ClaudEA ecosystem vision. SwiftEA is a unified CLI toolkit providing programmatic access to macOS PIM data, serving as the foundation for ClaudEA AI-powered executive assistant.

**Core Value:** Delegation, not assistance — ClaudEA does the work for you, only escalating what requires your judgment.

## Requirements

### Agent-Readiness (P0 — ClaudEA Blockers)

Critical requirements for enabling autonomous AI agent consumption.

| ID | Requirement | Description | Version |
|----|-------------|-------------|---------|
| AF-01 | JSON output for all commands | Every command must support `--json` flag with defined schemas | v1 |
| AF-02 | Non-interactive mode | Fail immediately on prompts instead of blocking; include recovery hints | v1 |
| AF-03 | Error code taxonomy | Machine-readable error codes (`ERR_AUTH_001`, etc.) with recovery hints | v1 |
| AF-04 | System state inspection | `swiftea inspect --json` for full system state snapshot | v1 |
| AF-05 | Stable ID guarantee | Message IDs survive database rebuilds, migrations, cross-machine sync | v1 |
| AF-06 | Confirmation flags | Replace y/n prompts with `--confirm`, `--yes`, `--force`, `--dry-run` | v1 |

### Agent Performance (P1 — Reliability & Efficiency)

| ID | Requirement | Description | Version |
|----|-------------|-------------|---------|
| AF-07 | Compact mode | Suppress progress output, single-line JSON result, log verbosity to file | v1 |
| AF-08 | Warnings in JSON | Emit warnings even on "success" for swallowed errors, partial syncs | v1 |
| AF-09 | Operation visibility | `swiftea operations --json` to query running/failed operations | v1 |
| AF-10 | ISO 8601 timestamps | All dates must be `2026-01-12T10:30:00Z` format | v1 |
| AF-11 | Delta status output | Show only changes since last check to reduce token usage | v1 |

### Phase 1 Completion

| ID | Requirement | Description | Version |
|----|-------------|-------------|---------|
| P1-01 | Vault bootstrap | `swiftea init --vault <path>` with vault-scoped config and folder layout | v1 |
| P1-02 | Bidirectional mail sync | libSQL ↔ Apple Mail.app bidirectional sync improvements | v1 |
| P1-03 | Permission diagnostics | `swiftea doctor --permissions` to diagnose permission issues | v1 |

### Calendar Module (Phase 2)

| ID | Requirement | Description | Version |
|----|-------------|-------------|---------|
| CAL-01 | Calendar read access | Read events with attendees, location, notes via EventKit | v1 |
| CAL-02 | Calendar search | Search by date/title/attendees with FTS5 | v1 |
| CAL-03 | Calendar export | Export to markdown/JSON with frontmatter | v1 |
| CAL-04 | Calendar actions | Create, update, delete events via AppleScript | v1 |
| CAL-05 | Recurring events | Handle recurring events properly with RRULE parsing | v1 |

### Contacts Module (Phase 2)

| ID | Requirement | Description | Version |
|----|-------------|-------------|---------|
| CON-01 | Contacts read access | Read contacts with all fields from AddressBook | v1 |
| CON-02 | Contacts search | Search by name/email/organization | v1 |
| CON-03 | Contacts export | Export to markdown/JSON | v1 |
| CON-04 | Contacts actions | Create, update, delete; manage groups via AppleScript | v1 |

### Cross-Module Intelligence (Phase 2)

| ID | Requirement | Description | Version |
|----|-------------|-------------|---------|
| LINK-01 | Cross-module linking | Email ↔ event ↔ contact relationships in links table | v1 |
| LINK-02 | Automatic link detection | Detect events in email body, contacts in from field | v1 |
| SEARCH-01 | Unified search | Cross-module ranking and faceted results | v1 |

### Reminders & Context (Phase 3)

| ID | Requirement | Description | Version |
|----|-------------|-------------|---------|
| REM-01 | Reminders read/write | Read/search/export Apple Reminders; create/update/delete | v1 |
| CTX-01 | Context assembly | `swiftea context --project "X" --json` gathers all related items | v1 |
| META-01 | Advanced metadata | Ad-hoc field addition without migrations; bulk operations | v1 |

### Performance & Reliability (Phase 4)

| ID | Requirement | Description | Version |
|----|-------------|-------------|---------|
| PERF-01 | Caching layer | Intelligent caching, parallel processing where safe | v1 |
| PERF-02 | Real-time sync | FSEvents watchers with incremental updates | v1 |
| PERF-03 | Large dataset handling | 100k+ items with sub-second queries | v1 |
| PERF-04 | Error recovery | Exponential backoff retry, resilience | v1 |
| PERF-05 | Conflict resolution | Configurable strategy (last-write-wins default) | v1 |

### AI & Semantic Features (Phase 5)

| ID | Requirement | Description | Version |
|----|-------------|-------------|---------|
| AI-01 | Semantic search | Vector embeddings via sqlite-vss for meaning-based queries | v2 |
| AI-02 | Synonym handling | Automatic synonym expansion in search | v2 |
| AI-03 | AI summaries | AI-generated summaries for emails, meetings, threads | v2 |
| AI-04 | Priority scoring | ML-based prioritization of inbox and tasks | v2 |
| AI-05 | Task extraction | Identify commitments from emails automatically | v2 |
| AI-06 | Auto categorization | Automatic content categorization | v2 |

### Polish & OSS Release (Phase 6)

| ID | Requirement | Description | Version |
|----|-------------|-------------|---------|
| NOTES-01 | Notes module | Apple Notes integration or markdown-only vault | v2 |
| DOCS-01 | Documentation | User guides and API documentation | v1 |
| DIST-01 | Homebrew distribution | `brew tap swiftea/tap && brew install swiftea` | v1 |
| COMM-01 | Community readiness | Issue templates, contributing guide, feedback channels | v1 |

### GUI Layer (Phase 7)

| ID | Requirement | Description | Version |
|----|-------------|-------------|---------|
| GUI-01 | SwiftUI application | Native macOS application | v2 |
| GUI-02 | Menu bar access | Quick access and notifications | v2 |
| GUI-03 | Thread visualization | Expandable conversation trees, timeline | v2 |
| GUI-04 | Unified dashboard | Mail + calendar + contacts in one view | v2 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| AF-01 | Phase 1 | Pending |
| AF-02 | Phase 1 | Pending |
| AF-03 | Phase 1 | Pending |
| AF-04 | Phase 1 | Pending |
| AF-05 | Phase 1 | Pending |
| AF-06 | Phase 1 | Pending |
| AF-07 | Phase 1 | Pending |
| AF-08 | Phase 1 | Pending |
| AF-09 | Phase 1 | Pending |
| AF-10 | Phase 1 | Pending |
| AF-11 | Phase 1 | Pending |
| P1-01 | Phase 1 | Pending |
| P1-02 | Phase 1 | Pending |
| P1-03 | Phase 1 | Pending |
| CAL-01 | Phase 2 | Pending |
| CAL-02 | Phase 2 | Pending |
| CAL-03 | Phase 2 | Pending |
| CAL-04 | Phase 2 | Pending |
| CAL-05 | Phase 2 | Pending |
| CON-01 | Phase 2 | Pending |
| CON-02 | Phase 2 | Pending |
| CON-03 | Phase 2 | Pending |
| CON-04 | Phase 2 | Pending |
| LINK-01 | Phase 2 | Pending |
| LINK-02 | Phase 2 | Pending |
| SEARCH-01 | Phase 2 | Pending |
| REM-01 | Phase 3 | Pending |
| CTX-01 | Phase 3 | Pending |
| META-01 | Phase 3 | Pending |
| PERF-01 | Phase 4 | Pending |
| PERF-02 | Phase 4 | Pending |
| PERF-03 | Phase 4 | Pending |
| PERF-04 | Phase 4 | Pending |
| PERF-05 | Phase 4 | Pending |
| AI-01 | Phase 5 | Pending |
| AI-02 | Phase 5 | Pending |
| AI-03 | Phase 5 | Pending |
| AI-04 | Phase 5 | Pending |
| AI-05 | Phase 5 | Pending |
| AI-06 | Phase 5 | Pending |
| NOTES-01 | Phase 6 | Pending |
| DOCS-01 | Phase 6 | Pending |
| DIST-01 | Phase 6 | Pending |
| COMM-01 | Phase 6 | Pending |
| GUI-01 | Phase 7 | Pending |
| GUI-02 | Phase 7 | Pending |
| GUI-03 | Phase 7 | Pending |
| GUI-04 | Phase 7 | Pending |

**Coverage:**
- v1 requirements: 38 total
- v2 requirements: 10 total
- Mapped to phases: 48
- Unmapped: 0 ✓

## Out of Scope

Per PROJECT.md, explicitly excluded:

| Exclusion | Reason |
|-----------|--------|
| Replace native macOS apps | We read from Mail.app/Calendar.app; Apple handles UI and sync |
| GUI applications (for now) | CLI-first ensures stable foundation; GUI is Phase 7+ |
| Cloud sync or multi-device | macOS single machine; Apple handles cross-device sync |
| Cross-platform support | macOS only to leverage Apple ecosystem APIs |
| Real-time collaboration | Single-user system |
| Modifying Apple's databases | Read-only; writes go through AppleScript |
| Telemetry or data collection | Privacy-first; no data leaves your Mac |

---

*Requirements derived from PROJECT.md — 2026-01-16*
