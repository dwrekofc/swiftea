# Change: Add Mail Actions via AppleScript

## Why
Reading and exporting mail is not enough for day-to-day workflows. SwiftEA needs safe, scriptable “write” operations (archive, delete, move, flag, reply, send) to enable executive-assistant routines and ClaudEA-driven automation.

## What Changes
- New mail CLI subcommands for common actions (archive/delete/move/flag/mark read/unread, draft/reply/send)
- AppleScript execution layer for Mail.app automation (OSAKit / Apple Events)
- Safety controls for destructive actions (confirmation flags, dry-run)
- Robust mapping from SwiftEA email IDs to Mail.app messages (with clear failure modes)

## Impact
- Affected specs: mail capability (new action requirements)
- Affected code: mail module actions, CLI routing, automation execution, error handling/logging
- New constraints: macOS Automation permission required for controlling Mail.app
