# Mail Module

The mail module provides read-only access to Apple Mail data with sync, search, and export capabilities.

## Quick Start

Getting started with mail sync involves three steps:

```bash
# 1. Initialize a vault (if not already done)
swea init

# 2. Sync mail from Apple Mail to the local database
swea mail sync

# 3. Export messages to markdown files (for use in Obsidian, etc.)
swea mail export
```

For automatic sync, use watch mode to keep your mail mirror up to date:

```bash
# Start automatic sync (syncs every 5 minutes + on system wake)
swea mail sync --watch

# For near-realtime sync, use a shorter interval (minimum 30 seconds)
swea mail sync --watch --interval 60

# Check sync status
swea mail sync --status

# Stop automatic sync
swea mail sync --stop
```

**Key commands at a glance:**

| Command | Purpose |
|---------|---------|
| `swea mail sync` | Sync mail data (incremental by default) |
| `swea mail sync --full` | Full resync from scratch |
| `swea mail sync --watch` | Start automatic background sync |
| `swea mail search "query"` | Search synced messages |
| `swea mail show <id>` | View a single message |
| `swea mail export` | Export messages to markdown/JSON files |
| `swea mail threads` | List all email threads/conversations |
| `swea mail thread <id>` | View a specific conversation thread |
| `swea mail export-threads` | Export entire threads as single files |

## Understanding the Workflow

The mail module works in two stages:

1. **Sync** (`swea mail sync`) - Reads Apple Mail's database and mirrors message metadata and content to a local SQLite database at `<vault>/.swiftea/mail.db`. This is fast and gives you search capabilities.

2. **Export** (`swea mail export`) - Writes individual `.md` or `.json` files from the synced database to `<vault>/Swiftea/Mail/` (or a custom location). Use this when you want files you can open in Obsidian or other tools.

**Why two steps?** The sync step is designed to run frequently (even automatically with `--watch`). The export step is heavier and creates files, so you run it when you actually need the files.

## Phase 1 Scope

Phase 1 implements a **read-only mail mirror** with the following capabilities:

| Feature | Status |
|---------|--------|
| Mail sync from Apple Mail | Implemented |
| Watch daemon with sleep/wake detection | Implemented |
| Full-text search with structured filters | Implemented |
| Markdown and JSON export | Implemented |
| Attachment extraction | Implemented |
| Configuration via `swea config` | Implemented |
| Mail actions (archive/delete/move/flag) | Placeholder only |
| Email threading | Implemented |

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
- Does not sync with IMAP servers directly (uses Apple Mail as source)

## Prerequisites

### Full Disk Access

The mail module requires **Full Disk Access** permission to read Apple Mail's database.

To grant permission:

1. Open **System Settings** > **Privacy & Security** > **Full Disk Access**
2. Click the **+** button
3. Navigate to and select the `swea` executable (or Terminal.app if running from terminal)
4. Toggle the permission **on**

If permission is missing, sync commands will fail with a permission error and guidance.

## Commands

### swea mail sync

Sync mail data from Apple Mail to the local mirror database.

```bash
# Incremental sync (default - only new/changed messages)
swea mail sync

# Full resync (first time or to refresh everything)
swea mail sync --full

# Verbose output (shows progress)
swea mail sync --verbose
```

**Note**: Sync is incremental by default - it only processes messages that changed since the last sync. Use `--full` to resync everything from scratch.

### swea mail sync --watch (Recommended for Regular Use)

For hands-off sync, install the watch daemon. It runs in the background and keeps your mail mirror up to date automatically.

```bash
# Start automatic sync daemon (default: every 5 minutes)
swea mail sync --watch

# Near-realtime sync (every 1 minute)
swea mail sync --watch --interval 60

# Near-realtime sync (every 30 seconds - minimum)
swea mail sync --watch --interval 30

# Check daemon status and last sync time
swea mail sync --status

# Stop the daemon
swea mail sync --stop
```

**The `--interval` option:**
- Configures how often the daemon syncs (in seconds)
- Default: 300 seconds (5 minutes)
- Minimum: 30 seconds
- For near-realtime sync, use `--interval 60` (1 minute) or `--interval 30` (30 seconds)
- Shorter intervals mean faster updates but more CPU/disk usage

**What the watch daemon does:**
- Runs as a macOS LaunchAgent (`com.swiftea.mail.sync`)
- Performs incremental sync at the configured interval
- Syncs immediately when your Mac wakes from sleep (catches up on new mail)
- Handles transient errors with automatic retry
- Logs activity to `<vault>/.swiftea/logs/mail-sync.log`

**When to use watch mode:**
- You want your mail database always up to date
- You use the search feature frequently
- You run periodic exports (e.g., via cron or manually)

**Choosing an interval:**
- **5 minutes (default)**: Good balance for most users
- **1 minute**: Near-realtime for active email monitoring
- **30 seconds**: Fastest updates, slightly higher resource usage

### swea mail search

Search for messages using full-text search and structured filters.

```bash
# Simple text search
swea mail search "quarterly report"

# Search with structured filters
swea mail search "from:alice@example.com project"
swea mail search "is:unread is:flagged"
swea mail search "mailbox:INBOX after:2024-01-01"

# Output as JSON
swea mail search "budget" --json

# Limit results
swea mail search "invoice" --limit 50
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
swea mail search "from:support is:unread after:2024-01-01 has:attachments"
```

### swea mail show

Display a single message by ID.

```bash
# Show message in text format
swea mail show abc123def456

# Show HTML body instead of plain text
swea mail show abc123def456 --html

# Show raw .emlx content
swea mail show abc123def456 --raw

# Output as JSON
swea mail show abc123def456 --json
```

### swea mail export

Export messages from the synced database to markdown or JSON files.

**Important**: This command creates the actual `.md` files. Running `swea mail sync` alone only populates the database - you must run `swea mail export` to get files you can open in Obsidian or other tools.

Default export location: `<vault>/exports/mail/`

```bash
# Export all synced messages to markdown files
swea mail export

# Export a specific message
swea mail export --id abc123def456

# Export messages matching a query
swea mail export --query "from:alice"

# Export to JSON format
swea mail export --format json

# Export to custom directory (e.g., your Obsidian vault)
swea mail export --output ~/Documents/Obsidian/Mail

# Include attachment extraction
swea mail export --include-attachments

# Limit export count
swea mail export --limit 500
```

**Tip**: For Obsidian users, export directly to your vault:
```bash
swea mail export --output ~/Documents/ObsidianVault/Mail
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

JSON exports include full message metadata with thread information:

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
  "bodyHtml": "...",
  "thread_id": "a1b2c3d4e5f6789012345678901234567"
}
```

**Thread Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `thread_id` | string | 32-character hex thread ID (present if message is threaded) |
| `thread_position` | integer | 1-indexed position within thread (present in thread exports) |
| `thread_total` | integer | Total messages in thread (present in thread exports) |

#### Thread Export

Export a complete thread with nested messages:

```bash
swea mail export --format json --thread <thread-id>
```

Thread exports create a single JSON file with full thread structure:

```json
{
  "thread_id": "a1b2c3d4e5f6789012345678901234567",
  "subject": "Weekly Status Update",
  "participant_count": 3,
  "message_count": 5,
  "first_date": "2024-01-15T10:30:00Z",
  "last_date": "2024-01-17T14:20:00Z",
  "messages": [
    {
      "id": "msg1",
      "messageId": "<original@example.com>",
      "subject": "Weekly Status Update",
      "from": { "name": "Alice", "email": "alice@example.com" },
      "date": "2024-01-15T10:30:00Z",
      "thread_id": "a1b2c3d4e5f6789012345678901234567",
      "thread_position": 1,
      "thread_total": 5,
      "bodyText": "..."
    },
    {
      "id": "msg2",
      "messageId": "<reply1@example.com>",
      "subject": "Re: Weekly Status Update",
      "from": { "name": "Bob", "email": "bob@example.com" },
      "date": "2024-01-15T11:00:00Z",
      "thread_id": "a1b2c3d4e5f6789012345678901234567",
      "thread_position": 2,
      "thread_total": 5,
      "bodyText": "..."
    }
  ]
}
```

**Thread Export Schema:**

| Field | Type | Description |
|-------|------|-------------|
| `thread_id` | string | 32-character hex thread ID |
| `subject` | string | Thread subject (from first message) |
| `participant_count` | integer | Number of unique participants |
| `message_count` | integer | Total messages in thread |
| `first_date` | string | ISO 8601 date of first message |
| `last_date` | string | ISO 8601 date of last message |
| `messages` | array | Nested array of message objects (sorted by date) |

Each message in the `messages` array includes all standard message fields plus `thread_position` and `thread_total`.

#### Attachment Extraction

When using `--include-attachments`, attachments are saved to:
```
<output>/attachments/<message-id>/<filename>
```

### swea mail threads

List all email threads (conversations) in the database.

```bash
# List recent threads (default limit: 50)
swea mail threads

# List more threads
swea mail threads --limit 100

# Paginate through threads
swea mail threads --limit 50 --offset 50

# Output as JSON
swea mail threads --json
```

**Output includes:**
- Thread ID (for use with `swea mail thread <id>`)
- Subject line
- Number of participants
- Number of messages
- Date range (first to last message)

### swea mail thread

Display all messages in a specific email thread, ordered chronologically.

```bash
# View a thread by ID
swea mail thread abc123def456

# Output as JSON
swea mail thread abc123def456 --json

# Show HTML body instead of plain text
swea mail thread abc123def456 --html
```

**Text output format:**
```
Thread: Weekly Status Update
======================================================================

Thread ID: abc123def456789012345678901234567
Participants: 3
Messages: 5
Date Range: January 15, 2024 at 10:30 AM → January 17, 2024 at 2:20 PM

======================================================================

[1/5] Weekly Status Update
------------------------------------------------------------
From: Alice <alice@example.com>
Date: January 15, 2024 at 10:30:00 AM PST
Mailbox: INBOX

Message body here...

[2/5] Re: Weekly Status Update
------------------------------------------------------------
From: Bob <bob@example.com>
Date: January 15, 2024 at 11:00:00 AM PST
...
```

### swea mail export-threads

Export complete email threads as single files (markdown or JSON).

```bash
# Export all threads (up to limit)
swea mail export-threads

# Export a specific thread
swea mail export-threads --thread-id abc123def456

# Export as JSON
swea mail export-threads --format json

# Export to custom directory
swea mail export-threads --output ~/Documents/Threads

# Limit number of threads to export
swea mail export-threads --limit 50
```

**Markdown export format:**

Each thread is exported as a single `.md` file with YAML frontmatter:

```markdown
---
thread_id: "abc123def456789012345678901234567"
subject: "Weekly Status Update"
participant_count: 3
message_count: 5
first_date: 2024-01-15T10:30:00Z
last_date: 2024-01-17T14:20:00Z
---

# Thread: Weekly Status Update

**5 message(s) between 3 participant(s)**

---

## Message 1 of 5

**From:** Alice <alice@example.com>
**Date:** 2024-01-15T10:30:00Z
**Subject:** Weekly Status Update

Message body here...

---

## Message 2 of 5

**From:** Bob <bob@example.com>
**Date:** 2024-01-15T11:00:00Z
**Subject:** Re: Weekly Status Update

Reply body here...
```

**Default output directory:** `<vault>/Swiftea/Threads/`

## Configuration

Use `swea config` to manage mail settings.

```bash
# View current mail settings
swea config get modules.mail

# Set custom Envelope Index path
swea config set modules.mail.envelopeIndexPath "/path/to/Envelope Index"

# Set default export format
swea config set modules.mail.exportFormat "json"
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
swea config set modules.mail.envelopeIndexPath "~/Library/Mail/V10/MailData/Envelope Index"
```

### "Database is locked"

The watch daemon uses retry with backoff for transient lock errors. If you see repeated lock errors:
1. Check if Mail.app is performing a large operation
2. Wait and try again
3. Stop other processes accessing the mail database

### Watch daemon not running

Check status:
```bash
swea mail sync --status
```

If the daemon crashed, restart it:
```bash
swea mail sync --stop
swea mail sync --watch
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

### Threading Issues

#### Messages not grouped into threads

If related messages aren't being grouped together:

1. **Missing threading headers** - Some mail clients don't properly set `References` or `In-Reply-To` headers. SwiftEA falls back to subject-based grouping, but this only works if subjects match after stripping `Re:`/`Fwd:` prefixes.

2. **Modified subject lines** - If someone changed the subject mid-conversation, messages may end up in separate threads.

3. **Resync may help** - Run `swea mail sync --full` to rebuild thread assignments from scratch.

4. **Check headers** - Use `swea mail show <id> --raw` to inspect the actual headers of a message and verify threading headers are present.

#### "Thread not found" error

If `swea mail thread <id>` returns "Thread not found":

1. Verify the thread ID is correct (32-character hex string)
2. Thread IDs are displayed in `swea mail threads` output
3. Run `swea mail sync` to ensure threads are up to date

#### Empty thread list

If `swea mail threads` returns no results:

1. Run `swea mail sync` first - threads are created during sync
2. Check that messages were synced successfully with `swea mail search "*"`
3. Threading requires at least one message with valid headers

#### Single-message threads

It's normal for standalone emails (not part of a conversation) to appear as single-message threads. The threading algorithm creates a thread for every message, even if it's not a reply.

#### Forwarded messages in wrong thread

Forwarded messages may be grouped with the original thread if they contain the original `References` header. This is RFC-compliant behavior. If forwarded messages should start new threads, the forwarding mail client needs to strip threading headers.

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

## Email Threading

SwiftEA implements RFC-compliant email threading to group related messages into conversations. This section documents how the threading algorithm works.

### Threading Headers

Email threading relies on three standard RFC 5322 headers:

| Header | Purpose | Example |
|--------|---------|---------|
| `Message-ID` | Unique identifier for each email | `<abc123@example.com>` |
| `In-Reply-To` | Message-ID of the direct parent message | `<parent@example.com>` |
| `References` | Ordered list of all ancestor Message-IDs | `<root@example.com> <parent@example.com>` |

#### Message-ID

Every email should have a unique Message-ID assigned by the sending mail server. The format is `<local-part@domain>`. SwiftEA normalizes Message-IDs by:

- Extracting the first valid `<...>` pattern from the header
- Trimming whitespace and newlines
- Adding angle brackets if missing but the value contains `@`
- Returning `nil` for completely invalid values

#### In-Reply-To

The In-Reply-To header identifies the immediate parent message. When you reply to an email, your mail client should set this to the Message-ID of the message you're replying to. SwiftEA extracts the first valid Message-ID from this header.

#### References

The References header contains the complete thread ancestry, ordered from oldest (thread root) to newest (immediate parent). For example, in a thread with messages A → B → C → D, message D's References header would be:

```
References: <A@example.com> <B@example.com> <C@example.com>
```

SwiftEA parses all valid Message-IDs from this space-separated list.

### Thread ID Generation Algorithm

SwiftEA generates deterministic thread IDs using the following priority:

1. **Use References[0]** - If the message has a References header, use the **first** Message-ID (the thread root). This ensures all messages in a thread share the same thread ID.

2. **Use In-Reply-To** - If no References but has In-Reply-To, use that. This handles simple two-message reply chains where only In-Reply-To is set.

3. **Use own Message-ID** - If neither References nor In-Reply-To (standalone message), use the message's own Message-ID. It becomes the thread root.

4. **Subject fallback** - If no Message-ID is available (malformed email), fall back to subject-based grouping with normalized subjects.

The thread ID itself is a 32-character hex string (first 128 bits of SHA-256 hash of the thread root).

#### Why References[0]?

The References header is ordered from oldest to newest. By always using the first reference (the original message that started the thread), all messages in a conversation—regardless of how deeply nested or branched—share the same thread ID.

```
Original message (A):     Message-ID: <A@example.com>
                          Thread ID: hash(<A@example.com>)

Reply (B):                References: <A@example.com>
                          In-Reply-To: <A@example.com>
                          Thread ID: hash(<A@example.com>) ← same!

Reply to reply (C):       References: <A@example.com> <B@example.com>
                          In-Reply-To: <B@example.com>
                          Thread ID: hash(<A@example.com>) ← same!
```

### Subject Normalization

For subject-based fallback threading, SwiftEA strips common reply/forward prefixes:

| Prefix | Language/Origin |
|--------|-----------------|
| `Re:` | English |
| `Fwd:`, `Fw:` | English forward |
| `AW:` | German (Antwort) |
| `SV:` | Swedish/Danish (Svar) |
| `VS:` | Finnish |
| `Antw:` | Dutch |
| `Odp:` | Polish |
| `R:` | Italian |

Nested prefixes like `Re: Re: Fwd: Re:` are fully stripped. Whitespace is normalized and the result is lowercased.

### Edge Cases

#### Missing Headers

| Scenario | Behavior |
|----------|----------|
| No Message-ID, no References, no In-Reply-To | Subject-based grouping |
| No Message-ID, no subject | Unique UUID per message (no threading) |
| Empty References | Falls through to In-Reply-To |
| Malformed Message-ID | Attempts extraction, falls back if invalid |

#### Forwarded Messages

Forwarded messages (detected by `Fwd:`, `Fw:`, `Forwarded:` prefixes) are handled like any other message. If they contain threading headers from the original thread, they'll be grouped with it. Otherwise, they start a new thread.

#### Mailing Lists

Mailing list messages typically preserve the original thread's References, so they're grouped correctly. List-specific headers like `List-Id` are not currently used for grouping.

### Database Schema

Threads are stored in two tables:

**`threads` table:**
| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PRIMARY KEY | 32-char hex thread ID |
| `subject` | TEXT | Normalized subject |
| `participant_count` | INTEGER | Unique senders |
| `message_count` | INTEGER | Messages in thread |
| `first_date` | DATETIME | Earliest message date |
| `last_date` | DATETIME | Latest message date |

**`thread_messages` junction table:**
| Column | Type | Description |
|--------|------|-------------|
| `thread_id` | TEXT | Foreign key to threads |
| `message_id` | TEXT | Foreign key to messages |

This allows efficient queries for messages in a thread and threads containing a message.

### Implementation Files

- `ThreadingHeaderParser.swift` - Parses and normalizes threading headers
- `ThreadIDGenerator.swift` - Generates deterministic thread IDs
- `ThreadDetectionService.swift` - Orchestrates thread detection and database updates

## Future: Phase 2+

Planned features for future phases:
- Mail actions via AppleScript (archive, delete, move, flag, reply, compose)
- Rich thread export formats
- Thread-based search filters
- Automation permission handling
