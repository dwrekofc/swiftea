---
title: Add Email Threading Support
goals:
  - SG-2  # Cross-Module Intelligence
status: approved
beads: swiftea-az6
---

# Change: Add Email Threading Support

## Goal Alignment

This change advances:
- **SG-2 (Cross-Module Intelligence)**: Threading connects related emails into conversations, enabling search and linking across conversation context

## Why
Currently, emails are viewed as individual items without conversation context. Users need to see email conversations as threaded discussions to understand context, follow discussions, and make better decisions. Email threading is essential for effective email triage and ClaudEA workflows.

## What Changes
- **BREAKING**: Database schema changes to add thread metadata
- **New CLI Commands**: `swiftea mail threads` and `swiftea mail thread`
- **Enhanced Export**: Thread-aware markdown and JSON exports
- **Thread Detection**: Header-based conversation grouping
- **Performance**: Fast threading for large inboxes (100k+ emails)

## Impact
- Affected specs: mail capability (new threading requirements)
- Affected code: mail module database schema, CLI commands, export system
- New capabilities: conversation viewing, thread management
- Future impact: foundation for Obsidian email GUI plugin
