---
title: Add Mail Actions via AppleScript
area: mail
status: archived
created: 2026-01-07
processed_date: 2026-01-09
d-spec_change_id: add-mail-actions-applescript
beads_epic_id: swiftea-01t
goals:
  - SG-4  # ClaudEA-Ready Output
  - SG-6  # Modular Extensibility
decision_summary:
  - New CLI subcommands: archive/delete/move/flag/mark read/unread/draft/reply/send
  - AppleScript execution via OSAKit / Apple Events for Mail.app automation
  - Safety controls: `--yes` required for destructive actions, `--dry-run` support
  - Robust SwiftEA ID → Mail.app message resolution with clear failure modes
  - Requires macOS Automation permission for controlling Mail.app
---

## Why
Reading and exporting mail is not enough for day-to-day workflows. SwiftEA needs safe, scriptable "write" operations to enable executive-assistant routines and ClaudEA-driven automation.

## What
- New mail CLI subcommands for common actions (archive/delete/move/flag/mark read/unread, draft/reply/send)
- AppleScript execution layer for Mail.app automation (OSAKit / Apple Events)
- Safety controls for destructive actions (confirmation flags, dry-run)
- Robust mapping from SwiftEA email IDs to Mail.app messages (with clear failure modes)

## Follow-ups (Beads)
- Epic: swiftea-01t (Add Mail Actions via AppleScript)
- Progress: 0/8 tasks closed (not started)
