## Context
SwiftEA reads Apple Mail data via direct database/file access, but Mail.app “write” operations must be performed through Apple Events (AppleScript). This change introduces an action layer that is safe for interactive use and suitable for automation.

## Goals / Non-Goals

Goals:
- Provide safe, scriptable mail actions through `swiftea mail ...` commands.
- Use macOS-supported automation (OSAKit / Apple Events) rather than writing to Apple databases.
- Fail safely when message resolution is ambiguous or permissions are missing.

Non-goals:
- Full Mail.app rules management (export/import/edit) in this phase.
- High-throughput bulk destructive operations without explicit user consent.

## Approach

### AppleScript execution
- Prefer OSAKit for execution to avoid shelling out, with a fallback to `/usr/bin/osascript` if needed.
- Normalize errors into actionable CLI messages:
  - missing Automation permission
  - Mail.app not running / not responding
  - message not found
  - message resolution ambiguous

### Message resolution strategy (SwiftEA ID → Mail.app message)
Resolution order:
1. RFC822 `Message-ID` (preferred when available): search for a unique message matching the header ID.
2. Fallback using stable identifiers available in the mirror (e.g., account + mailbox + subject + date window) with strict uniqueness requirements.

If resolution is not unique:
- return an error with guidance to refine selection (e.g., provide `--message-id` or use a narrower query).

### Safety gates
- Destructive actions (`delete`, `move`, `archive`) require explicit confirmation via `--yes` unless `--dry-run` is set.
- All actions support `--dry-run` to print what would be executed (including the resolved message identity) without executing.

## Open Questions
- Exact AppleScript querying strategy for locating a message by RFC822 Message-ID across accounts/mailboxes.
- Whether to expose a low-level `swiftea mail applescript --script <path>` escape hatch (likely out-of-scope).
