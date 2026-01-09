---
title: Add Mail Read/Export/Watch Foundation
goals:
  - SG-1  # Unified PIM Access
  - SG-3  # Data Liberation
  - SG-5  # Local-First Architecture
status: approved
beads: swiftea-7im
---

# Change: Add Mail Read/Export/Watch Foundation

## Goal Alignment

This change advances:
- **SG-1 (Unified PIM Access)**: Establishes the foundation for querying email data as part of the unified PIM system
- **SG-3 (Data Liberation)**: Exports email to open formats (markdown, JSON) under user control
- **SG-5 (Local-First Architecture)**: All data stored locally in libSQL mirror, no cloud dependency

## Why
SwiftEA needs a reliable, read-only mail foundation before higher-level workflows. This change establishes the mirror database, search index, and export formats so users and ClaudEA can read and process emails with near-real-time updates.

## What Changes
- New mail capability for read/search/export with a libSQL mirror derived from Apple Mail's SQLite database
- Near-real-time sync with `sync --watch` as a launchd agent
- Deterministic, stable email IDs (hash-based) plus source identifiers for mapping
- Markdown and JSON export formats with a minimal, Obsidian-friendly frontmatter
- Attachment metadata indexing (names/mime/size) without extraction by default

## Impact
- Affected specs: mail capability (new)
- Affected code: core database, mail sync, .emlx parsing, export system, CLI commands
- New constraints: read-only access to Apple databases and file system
