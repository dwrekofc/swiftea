# Change: Add Email Threading Support

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