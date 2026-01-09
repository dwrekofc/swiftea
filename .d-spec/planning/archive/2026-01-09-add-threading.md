---
title: Add Email Threading Support
area: mail
status: archived
created: 2026-01-07
processed_date: 2026-01-09
d-spec_change_id: add-threading
beads_epic_id: swiftea-az6
goals:
  - SG-2  # Cross-Module Intelligence
decision_summary:
  - BREAKING schema changes for thread metadata (threads table, thread_messages junction)
  - Header-based threading via Message-ID, References, In-Reply-To headers
  - New CLI commands: `swiftea mail threads` and `swiftea mail thread --id`
  - Thread-aware markdown/JSON exports with conversation grouping
  - Performance targets: <5s detection for 100k emails, <2s queries
---

## Why
Currently, emails are viewed as individual items without conversation context. Users need to see email conversations as threaded discussions to understand context, follow discussions, and make better decisions.

## What
- BREAKING database schema changes to add thread metadata
- New CLI Commands: `swiftea mail threads` and `swiftea mail thread`
- Enhanced Export: Thread-aware markdown and JSON exports
- Thread Detection: Header-based conversation grouping
- Performance: Fast threading for large inboxes (100k+ emails)

## Follow-ups (Beads)
- Epic: swiftea-az6 (Add Email Threading Support)
- Progress: 0/30 tasks closed (not started)
