# Mail Module

The mail module provides read-only access to Apple Mail data with sync, search, and export capabilities.

## Phase 1 Scope

Phase 1 implements a **read-only mail mirror** with the following capabilities:

| Feature | Status |
|---------|--------|
| Mail sync from Apple Mail | Implemented |
| Watch daemon with sleep/wake detection | Implemented |
| Full-text search with structured filters | Implemented |
| Markdown and JSON export | Implemented |
| Attachment extraction | Implemented |
| Configuration via `swiftea config` | Implemented |
| Mail actions (archive/delete/move/flag) | Placeholder only |
| Email threading | Not yet implemented |

### What Phase 1 Does

- **Mirrors** Apple Mail data into a local libSQL database
- **Syncs** incrementally to track new/changed messages
- **Watches** for changes with a persistent daemon that detects system wake
- **Searches** using FTS5 across subject, sender, recipients, and body text
- **Exports** messages to markdown or JSON format
- **Extracts** attachments when requested

### What Phase 1 Does NOT Do

- Does not modify Apple Mail data (read-only)
- Does not yet implement mail actions (archive, delete, move, flag, reply, compose)
- Does not yet detect email threads/conversations
- Does not sync with IMAP servers directly (uses Apple Mail as source)

## Prerequisites

### Full Disk Access

The mail module requires **Full Disk Access** permission to read Apple Mail's database.

To grant permission:

1. Open **System Settings** > **Privacy & Security** > **Full Disk Access**
2. Click the **+** button
3. Navigate to and select the `swiftea` executable (or Terminal.app if running from terminal)
4. Toggle the permission **on**

If permission is missing, sync commands will fail with a permission error and guidance.

## Commands

### swiftea mail sync

Sync mail data from Apple Mail to the local mirror database.

```bash
# Full sync (first time or refresh)
swiftea mail sync

# Incremental sync (only changed messages)
swiftea mail sync --incremental

# Verbose output
swiftea mail sync --verbose
```

### swiftea mail sync --watch

Install and start a persistent daemon that keeps the mirror in sync.

```bash
# Start the watch daemon
swiftea mail sync --watch

# Check daemon status
swiftea mail sync --status

# Stop the watch daemon
swiftea mail sync --stop
```

The watch daemon:
- Runs as a LaunchAgent (`com.swiftea.mail.sync`)
- Syncs every 5 minutes
- Syncs immediately when the system wakes from sleep
- Retries with exponential backoff on transient errors
- Logs to `<vault>/.swiftea/logs/mail-sync.log`

### swiftea mail search

Search for messages using full-text search and structured filters.

```bash
# Simple text search
swiftea mail search "quarterly report"

# Search with structured filters
swiftea mail search "from:alice@example.com project"
swiftea mail search "is:unread is:flagged"
swiftea mail search "mailbox:INBOX after:2024-01-01"

# Output as JSON
swiftea mail search "budget" --json

# Limit results
swiftea mail search "invoice" --limit 50
```

#### Structured Filters

| Filter | Description | Example |
|--------|-------------|---------|
| `from:` | Sender email or name | `from:alice@example.com` |
| `to:` | Recipient email or name | `to:team@company.com` |
| `subject:` | Subject contains text | `subject:meeting` |
| `mailbox:` | Mailbox name | `mailbox:INBOX` |
| `is:read` | Read messages only | `is:read` |
| `is:unread` | Unread messages only | `is:unread` |
| `is:flagged` | Flagged messages only | `is:flagged` |
| `is:unflagged` | Unflagged messages only | `is:unflagged` |
| `has:attachments` | Messages with attachments | `has:attachments` |
| `after:` | After date (YYYY-MM-DD) | `after:2024-01-01` |
| `before:` | Before date (YYYY-MM-DD) | `before:2024-02-01` |
| `date:` | Specific date (YYYY-MM-DD) | `date:2024-01-15` |

Combine filters in a single query:
```bash
swiftea mail search "from:support is:unread after:2024-01-01 has:attachments"
```

### swiftea mail show

Display a single message by ID.

```bash
# Show message in text format
swiftea mail show abc123def456

# Show HTML body instead of plain text
swiftea mail show abc123def456 --html

# Show raw .emlx content
swiftea mail show abc123def456 --raw

# Output as JSON
swiftea mail show abc123def456 --json
```

### swiftea mail export

Export messages to markdown or JSON format.

```bash
# Export all synced messages to markdown
swiftea mail export

# Export a specific message
swiftea mail export --id abc123def456

# Export messages matching a query
swiftea mail export --query "from:alice"

# Export to JSON format
swiftea mail export --format json

# Export to custom directory
swiftea mail export --output ~/Documents/mail-exports

# Include attachment extraction
swiftea mail export --include-attachments

# Limit export count
swiftea mail export --limit 500
```

#### Export Format: Markdown

Markdown exports include YAML frontmatter for Obsidian compatibility:

```markdown
---
id: "abc123def456"
subject: "Weekly Status Update"
from: "Alice <alice@example.com>"
date: 2024-01-15T10:30:00Z
aliases:
  - "Weekly Status Update"
---

# Weekly Status Update

[Message body here...]
```

#### Export Format: JSON

JSON exports include full message metadata:

```json
{
  "id": "abc123def456",
  "messageId": "<unique@message.id>",
  "subject": "Weekly Status Update",
  "from": {
    "name": "Alice",
    "email": "alice@example.com"
  },
  "date": "2024-01-15T10:30:00Z",
  "mailbox": "INBOX",
  "isRead": true,
  "isFlagged": false,
  "hasAttachments": false,
  "bodyText": "...",
  "bodyHtml": "..."
}
```

#### Attachment Extraction

When using `--include-attachments`, attachments are saved to:
```
<output>/attachments/<message-id>/<filename>
```

## Configuration

Use `swiftea config` to manage mail settings.

```bash
# View current mail settings
swiftea config get modules.mail

# Set custom Envelope Index path
swiftea config set modules.mail.envelopeIndexPath "/path/to/Envelope Index"

# Set default export format
swiftea config set modules.mail.exportFormat "json"
```

### Configuration Keys

| Key | Description | Default |
|-----|-------------|---------|
| `modules.mail.envelopeIndexPath` | Custom path to Apple Mail's Envelope Index | Auto-detected |
| `modules.mail.exportFormat` | Default export format (`markdown` or `json`) | `markdown` |
| `modules.mail.syncIntervalSeconds` | Watch daemon sync interval | `300` (5 min) |

## Database Location

The mail mirror database is stored at:
```
<vault>/.swiftea/mail.db
```

This is a libSQL database with FTS5 search indexing.

## Stable Message IDs

Each message has a stable ID generated from:
1. The RFC822 Message-ID header (preferred)
2. A hash of subject + sender + date (fallback)
3. The Apple Mail rowid (last resort)

These IDs remain stable across re-syncs, allowing reliable references in exports and integrations.

## Troubleshooting

### "Permission denied" errors

Ensure Full Disk Access is granted. See [Prerequisites](#full-disk-access).

### "Envelope Index not found"

Apple Mail may use a different version directory. Check:
```bash
ls ~/Library/Mail/
```

If you see `V10`, `V11`, etc., the auto-detection should find it. If not, set the path manually:
```bash
swiftea config set modules.mail.envelopeIndexPath "~/Library/Mail/V10/MailData/Envelope Index"
```

### "Database is locked"

The watch daemon uses retry with backoff for transient lock errors. If you see repeated lock errors:
1. Check if Mail.app is performing a large operation
2. Wait and try again
3. Stop other processes accessing the mail database

### Watch daemon not running

Check status:
```bash
swiftea mail sync --status
```

If the daemon crashed, restart it:
```bash
swiftea mail sync --stop
swiftea mail sync --watch
```

Check logs:
```bash
tail -50 <vault>/.swiftea/logs/mail-sync.log
```

### Exchange (EWS) messages

Exchange messages stored in cloud accounts may not have local `.emlx` files. These messages:
- Are synced with metadata from the Envelope Index
- Cannot be viewed with `--raw` flag
- May have limited body content if not cached locally

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Apple Mail                              │
│  ~/Library/Mail/V*/MailData/Envelope Index (SQLite)         │
│  ~/Library/Mail/V*/.../Messages/*.emlx                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ Read-only sync
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    SwiftEA Mail Module                       │
│  EnvelopeIndexDiscovery → MailSync → MailDatabase           │
│                              │                               │
│                              ▼                               │
│  <vault>/.swiftea/mail.db (libSQL with FTS5)                │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ Query / Export
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        CLI Commands                          │
│  mail search / mail show / mail export                       │
└─────────────────────────────────────────────────────────────┘
```

## Future: Phase 2+

Planned features for future phases:
- Email threading and conversation detection
- Mail actions via AppleScript (archive, delete, move, flag, reply, compose)
- Rich thread export formats
- Automation permission handling
