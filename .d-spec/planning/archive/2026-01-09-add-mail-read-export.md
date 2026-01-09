---
title: Add Mail Read/Export/Watch Foundation
area: mail
status: archived
created: 2026-01-07
processed_date: 2026-01-09
d-spec_change_id: add-mail-read-export
beads_epic_id: swiftea-7im
goals:
  - SG-1  # Unified PIM Access
  - SG-3  # Data Liberation
  - SG-5  # Local-First Architecture
decision_summary:
  - libSQL mirror database derived from Apple Mail SQLite (query-and-rebuild sync)
  - Near-real-time sync with `--watch` mode via launchd agent
  - Deterministic hash-based email IDs (Message-ID preferred, header digest fallback)
  - Markdown + JSON export with Obsidian-friendly YAML frontmatter
  - FTS5 full-text search across subject/from/to/body
---

## Why
SwiftEA needs a reliable, read-only mail foundation before higher-level workflows. This change establishes the mirror database, search index, and export formats so users and ClaudEA can read and process emails with near-real-time updates.

## What
- New mail capability for read/search/export with a libSQL mirror
- Near-real-time sync with `sync --watch` as a launchd agent
- Deterministic, stable email IDs plus source identifiers
- Markdown and JSON export formats
- Attachment metadata indexing (names/mime/size) without extraction by default

## Follow-ups (Beads)
- Epic: swiftea-7im (Add Mail Read/Export/Watch Foundation)
- Progress: 16/31 tasks closed
