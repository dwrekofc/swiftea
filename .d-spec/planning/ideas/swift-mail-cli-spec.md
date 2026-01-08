# SwiftEA Mail Module - Technical Specification

> **Part of SwiftEA**: This document specifies the Mail Module within the SwiftEA unified CLI tool. For overall architecture and cross-module features, see `swiftea-architecture.md`.

## Executive Summary
The SwiftEA Mail Module provides programmatic access to Apple Mail by interfacing directly with its SQLite database and .emlx files. As part of the larger SwiftEA system, it enables ClaudEA (and users) to read, search, export, and later take actions on emails within a unified knowledge graph that spans mail, calendar, contacts, and more. Phase 1 focuses on read/search/export with near-real-time sync; AppleScript actions are deferred to Phase 2.

## Module Goals
- **Universal Email Access**: Read and search emails via direct SQLite access
- **Data Liberation**: Export emails to markdown and JSON for ClaudEA workflows
- **Automation (Phase 2)**: Execute email actions (send, reply, archive, etc.) via AppleScript
- **Intelligence Layer**: Maintain custom metadata and AI insights (using SwiftEA's unified metadata system)
- **Search Excellence**: Provide fast, ranked full-text search (integrates with SwiftEA's cross-module search)
- **Cross-Module Integration**: Enable linking emails to calendar events, contacts, tasks, and projects

## Phase 1 Scope (Read/Export/Watch)
- Read and mirror Apple Mail data into libSQL (read-only source access)
- Full-text search across subject/from/to/body_text
- Markdown and JSON export formats
- `sync --watch` as a launchd agent with near-real-time updates
- No AppleScript actions in Phase 1 (Phase 2+)

## Architecture Overview

> **Note**: This module operates within the SwiftEA framework. It uses SwiftEA Core services (database, search, sync, export) and contributes email data to the unified knowledge graph. See `swiftea-architecture.md` for the complete system architecture.

### Mail Module Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  SwiftEA Mail Module                        │
│              (Part of SwiftEA Unified CLI)                  │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐     ┌──────────────┐     ┌──────────────┐
│  Read Layer   │     │ Content Layer│     │ Action Layer │
│   (SQLite)    │     │   (.emlx)    │     │ (AppleScript)│
└───────────────┘     └──────────────┘     └──────────────┘
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐     ┌──────────────┐     ┌──────────────┐
│ Envelope Index│     │  .emlx Files │     │  Mail.app    │
│ → SwiftEA DB  │     │  File System │     │  Automation  │
│ + FTS5 Index  │     │              │     │              │
└───────────────┘     └──────────────┘     └──────────────┘
                │
                ▼
        ┌──────────────────┐
        │   SwiftEA Core   │
        │ • Unified Search │
        │ • Metadata       │
        │ • Links          │
        │ • Export         │
        └──────────────────┘
```

### Layer 1: Read Layer (SQLite Database Access)

**Source**: `~/Library/Mail/V[x]/MailData/Envelope Index`

**Components**:
1. **Mirror Database**: Real-time synchronized copy of Apple Mail's Envelope Index
2. **Custom Metadata Table**: User-defined fields joined to message ROWIDs
3. **FTS5 Index**: Full-text search index for fast, ranked queries

**Capabilities**:
- List emails with metadata (subject, sender, date, status)
- Fast keyword search across email content
- Query by structured fields (from, to, date ranges, flags)
- Track custom metadata (AI summaries, priorities, task associations)

**Requirements**:
- Full Disk Access permission in macOS System Settings
- Read-only access to source database (never write to Apple's DB)
- Near-real-time synchronization (hybrid approach)

### Layer 2: Content Layer (.emlx File Access)

**Source**: `~/Library/Mail/V[x]/[AccountID]/[Mailbox]/Messages/`

**File Format**: `.emlx` (RFC822/MIME email with byte-count header + XML plist)

**Capabilities**:
- Read full email body (plain text and HTML)
- Parse email headers and metadata
- Extract and handle attachments
- Export to markdown and JSON formats

**Implementation**:
- Use directory_id from SQLite to construct file path
- Parse .emlx structure (header, MIME content, plist metadata)
- Convert HTML to markdown for export
- Preserve formatting and structure

### Layer 3: Action Layer (AppleScript Automation, Phase 2)

**Interface**: Apple Mail Scripting Dictionary via osascript

**Capabilities**:
- Send, reply, draft emails
- Archive, delete, move emails between mailboxes
- Flag, label, mark read/unread
- Create filters and rules
- Search with Mail.app's native query syntax

**Requirements**:
- Mail.app must be running for actions
- Pre-built AppleScript templates for common actions
- Error handling for failed automation

**Future Enhancement**: Push rules to email server (Exchange/Gmail/IMAP) when possible

---

## Core Features

### 1. Database Mirroring & Synchronization

**Mirror Strategy**: Query-and-rebuild from Apple Mail's SQLite source into a libSQL mirror database (no file-level copying of the source DB)

**Sync Methods**:
1. **File System Watcher** (FSEvents API): Real-time detection of Envelope Index changes
2. **Periodic Validation**: Full sync every N minutes to catch missed changes
3. **Manual Refresh**: User/ClaudEA-triggered sync on demand

**Sync Commands**:
```bash
swiftea mail sync                    # Sync mail module
swiftea mail sync --watch            # Start background watcher
swiftea mail sync --validate         # Full validation sync
swiftea mail sync --status           # Show sync status

# Or use global sync (syncs all modules):
swiftea sync                         # Sync all modules including mail
```

**Mirror Database Schema**:
- Core tables: Mirrored from Envelope Index (messages, subjects, addresses)
- Custom tables: User-defined metadata (see below)
- FTS5 tables: Full-text search index

### 2. Custom Metadata Schema

**Architecture**: Separate joined table(s) that reference original message ROWIDs

**Initial Custom Metadata Table**:
```sql
CREATE TABLE custom_metadata (
  message_rowid INTEGER PRIMARY KEY,
  ai_summary TEXT,                 -- ClaudEA-generated summary
  ai_insights TEXT,                -- Extracted action items, key points
  priority_score INTEGER,          -- 1-10 custom priority rating
  processing_status TEXT,          -- 'unprocessed', 'reviewed', 'needs-response', 'waiting', 'archived'
  linked_tasks TEXT,               -- JSON array of task IDs
  linked_projects TEXT,            -- JSON array of project IDs
  custom_tags TEXT,                -- JSON array of user tags
  notes TEXT,                      -- User/ClaudEA notes
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  FOREIGN KEY (message_rowid) REFERENCES messages(ROWID)
);
```

**Ad-Hoc Column Addition**:
```bash
# Feature: Dynamically add custom columns without migration files
swiftea meta add-field --name "urgency_level" --type TEXT
swiftea meta add-field --name "response_deadline" --type TIMESTAMP
swiftea meta list-fields           # Show all custom fields

# Note: This uses SwiftEA's unified metadata system
# Fields work across all modules (mail, calendar, contacts, etc.)
```

**Metadata Management**:
```bash
swiftea meta set --id mail:12345 --field priority_score --value 9
swiftea meta set --id mail:12345 --field processing_status --value "needs-response"
swiftea meta get --id mail:12345
swiftea meta update --id mail:12345 --json '{"priority_score": 9, "custom_tags": ["urgent", "finance"]}'

# Also works with module-specific commands:
swiftea mail meta set --id 12345 --field priority_score --value 9
```

### 3. Full-Text Search (FTS5)

**Index Structure**:
```sql
CREATE VIRTUAL TABLE email_search USING fts5(
  message_rowid UNINDEXED,
  subject,
  sender,
  recipients,
  body_text,
  body_html,
  attachment_names,
  tokenize='porter unicode61 remove_diacritics 1'
);
```

**Search Capabilities**:
- **Keyword search**: Fast full-text queries
- **Phrase matching**: "exact phrase" in quotes
- **Boolean operators**: AND, OR, NOT
- **Relevance ranking**: BM25 algorithm
- **Snippet generation**: Context preview around matches

**Search Commands**:
```bash
# Module-specific search (mail only):
swiftea mail search "project alpha"                    # Basic keyword search
swiftea mail search "budget AND Q1"                    # Boolean operators
swiftea mail search '"exact phrase"'                   # Phrase search
swiftea mail search "urgent" --from "boss@company.com" # Combined with filters
swiftea mail search "meeting" --ranked --limit 20      # Ranked results
swiftea mail search "invoice" --snippet                # Show context snippets

# Cross-module search (searches all modules):
swiftea search "project alpha"                         # Search mail + calendar + contacts
swiftea search "project alpha" --mail                  # Limit to mail module
swiftea search "meeting" --mail --calendar             # Search mail and calendar
```

**JSON Output (Search/Query/Get)**:
When `--json` is used, responses are wrapped in an envelope:
```json
{
  "version": "1",
  "query": "from:bob is:unread",
  "total": 2,
  "items": [ /* results */ ],
  "warnings": []
}
```

**Index Management**:
```bash
swiftea mail index rebuild         # Rebuild mail index
swiftea mail index refresh         # Incremental update
swiftea mail index optimize        # Optimize for performance
swiftea mail index stats           # Show index statistics

# Or use global index commands:
swiftea index rebuild --mail       # Same as above
```

**Performance Target**: < 1 second for queries across 10k-100k emails

### 4. Email Export

#### Markdown Export

**Format**: YAML frontmatter + markdown body

**Template**:
```markdown
---
id: mail:abc123
subject: Project Update
from: Bob <bob@example.com>
date: 2026-01-06T10:30:00Z
aliases:
  - Project Update
---

# Project Update

Email body content converted to markdown...

- Preserves lists
- **Preserves formatting**
- Converts HTML to clean markdown when plain text is unavailable

## Quoted Replies

> Original message text preserved
```

**Export Commands**:
```bash
swiftea mail export --id 12345 --format markdown
swiftea mail export --id 12345 --format markdown --output ~/vault/emails/
swiftea mail export --from "bob@example.com" --format markdown  # Batch export
swiftea mail export --query "unread AND after:2026-01-01" --format markdown
swiftea mail export --id 12345 --format markdown --include-attachments

# Or use global export (with ID prefix):
swiftea export --id mail:12345 --format markdown
```

#### JSON Export

**Architecture**: Hybrid approach
- **Individual files**: Default for single-email exports (Obsidian-friendly)
- **Array format**: Available for batch exports and programmatic processing

**Individual Email JSON Structure**:
```json
{
  "id": "mail:abc123",
  "rowid": 12345,
  "messageId": "<abc@example.com>",
  "from": {
    "name": "Bob",
    "email": "bob@example.com"
  },
  "to": [
    {
      "name": "You",
      "email": "you@example.com"
    }
  ],
  "cc": [],
  "bcc": [],
  "subject": "Project Update",
  "date": "2026-01-06T10:30:00Z",
  "body": {
    "text": "Plain text version...",
    "html": "<html>...</html>"
  },
  "metadata": {
    "isRead": true,
    "isFlagged": false,
    "labels": ["work", "urgent"],
    "mailbox": "INBOX"
  },
  "customMetadata": {
    "aiSummary": "...",
    "aiInsights": "...",
    "priority": 8,
    "status": "needs-response",
    "linkedTasks": ["TASK-123"],
    "linkedProjects": ["ProjectAlpha"],
    "customTags": ["urgent", "finance"],
    "notes": "..."
  },
  "attachments": [
    {
      "filename": "document.pdf",
      "size": 102400,
      "mimeType": "application/pdf",
      "path": "/path/to/attachment"
    }
  ],
  "thread": {
    "threadId": "thread-xyz",
    "position": 3,
    "total": 5
  }
}
```

**Array Export** (for batch operations):
```json
{
  "query": "from:bob@example.com after:2026-01-01",
  "total": 42,
  "emails": [
    { /* email object */ },
    { /* email object */ },
    ...
  ]
}
```

**Export Commands**:
```bash
swiftea mail export --id 12345 --format json                     # Single file
swiftea mail export --id 12345 --format json --output email.json
swiftea mail export --query "unread" --format json --array       # Array format
swiftea mail export --from "bob" --format json --batch           # Multiple individual files
```

**Use Cases**:
- Individual JSON files: Obsidian plugin reads/displays emails
- Array format: ClaudEA batch processing, data analysis
- Pipeline integration: Feed JSON to other CLI tools

### 5. Email Actions (AppleScript Layer, Phase 2)

**Core Actions**:

#### Send/Reply/Draft
```bash
swiftea mail send --to "bob@example.com" --subject "Hello" --body "Message text"
swiftea mail send --to "bob@example.com" --subject "Hello" --body-file ~/message.txt
swiftea mail reply --id 12345 --body "Reply text"
swiftea mail reply --id 12345 --body-file ~/reply.md --all  # Reply-all
swiftea mail draft --to "bob@example.com" --subject "Draft" --body "..."
```

#### Archive/Delete/Move
```bash
swiftea mail archive --id 12345
swiftea mail archive --query "from:newsletter@*"              # Batch archive
swiftea mail delete --id 12345
swiftea mail delete --query "before:2024-01-01" --confirm     # Batch with confirmation
swiftea mail move --id 12345 --to "Archive/2026"
swiftea mail move --query "from:bob" --to "Projects/Alpha"
```

#### Flag/Label/Mark
```bash
swiftea mail flag --id 12345
swiftea mail unflag --id 12345
swiftea mail mark-read --id 12345
swiftea mail mark-unread --id 12345
swiftea mail label --id 12345 --add "urgent,work"
swiftea mail label --id 12345 --remove "todo"
```

#### Rules & Filters
```bash
swiftea mail rule create --name "Archive Newsletters" \
  --condition "from contains newsletter" \
  --action "move to Archive/Newsletters"

swiftea mail rule create --name "Flag Boss Emails" \
  --condition "from is boss@company.com" \
  --action "flag and mark-important"

swiftea mail rule list
swiftea mail rule delete --name "Archive Newsletters"
swiftea mail rule export --output ~/mail-rules.json          # Export rules
swiftea mail rule import --file ~/mail-rules.json            # Import rules
```

**Future Enhancement**: Push rules to email server (Exchange/Gmail/IMAP filters)

### 6. Batch Operations

**Philosophy**: Support both individual and batch operations for all commands

**Batch Export**:
```bash
# Export all unread emails from last week
swiftea mail export --query "unread AND after:2026-01-01" --format markdown

# Export specific sender's emails
swiftea mail export --from "important@client.com" --format json --array

# Export entire mailbox
swiftea mail export --mailbox "INBOX" --format markdown --output ~/vault/emails/inbox/
```

**Batch Actions**:
```bash
# Archive all newsletters
swiftea mail archive --query "from:*@newsletter.com"

# Flag all emails from boss
swiftea mail flag --query "from:boss@company.com"

# Delete old emails (with confirmation)
swiftea mail delete --query "before:2024-01-01" --confirm
```

**Pipeline Support** (stdin/stdout):
```bash
# Find unread, export as JSON, filter with jq
swiftea mail search "urgent" --unread --json | jq '.[] | select(.priority > 7)'

# Get email IDs from search, then batch export
swiftea mail search "project alpha" --ids-only | swiftea mail export --stdin --format markdown

# Chain multiple operations
swiftea mail search "newsletter" --ids-only | swiftea mail archive --stdin

# Integration with other tools
swiftea mail export --query "unread" --format json | \
  jq -r '.[] | .subject' | \
  claudea-summarize > daily-email-brief.md

# Cross-module integration
swiftea search "project alpha" --json | \
  jq '.[] | select(.module == "mail")' | \
  swiftea export --stdin --format markdown
```

**Performance Considerations**:
- Progress indicators for batch operations (> 10 emails)
- Parallel processing where safe (exports)
- Rate limiting for actions (avoid Mail.app overload)
- Dry-run mode: `--dry-run` flag shows what would happen without executing

### 7. Query Language

**Structured Queries** (CLI flags):
```bash
swiftea mail query --from "bob@example.com"
swiftea mail query --to "me@example.com"
swiftea mail query --subject "project alpha"
swiftea mail query --after "2026-01-01"
swiftea mail query --before "2026-12-31"
swiftea mail query --unread
swiftea mail query --flagged
swiftea mail query --has-attachment
swiftea mail query --mailbox "INBOX"

# Combine multiple filters
swiftea mail query --from "bob" --after "2026-01-01" --unread --has-attachment
```

**Advanced Search String** (Gmail-style):
```bash
swiftea mail search "from:bob@example.com subject:urgent after:2026-01-01"
swiftea mail search "has:attachment is:unread from:client.com"
swiftea mail search "to:me OR to:team@company.com"
swiftea mail search "subject:(project OR budget) -from:spam.com"
```

**Custom Metadata Queries**:
```bash
# Module-specific (mail only):
swiftea mail query --meta-field priority_score --meta-value ">7"
swiftea mail query --meta-field processing_status --meta-value "needs-response"
swiftea mail query --meta-field linked_projects --meta-contains "ProjectAlpha"

# Or use global query (works across all modules):
swiftea query --meta priority_score ">7" --mail
```

**Saved Queries**:
```bash
swiftea mail query save --name "urgent-unread" --query "is:unread priority:>7"
swiftea mail query run --name "urgent-unread"
swiftea mail query list
```

### 8. Error Handling

**Strategy**: Graceful degradation with comprehensive logging

**Principles**:
1. Continue processing when possible
2. Log all errors with context
3. Provide actionable error messages
4. Return summary of successes/failures

**Error Categories**:

**Permission Errors**:
```bash
ERROR: Cannot access Envelope Index
→ Grant Full Disk Access: System Settings > Privacy & Security > Full Disk Access
→ Add Terminal (or your terminal app) to the allowed list
```

**Sync Errors**:
```bash
WARNING: File system watcher failed to start
→ Falling back to periodic sync mode
→ Run 'swiftmail sync --watch' to retry
```

**Batch Operation Errors**:
```bash
Processed 50 emails:
  ✓ 47 succeeded
  ✗ 3 failed
    - Email 12345: File not found (.emlx missing)
    - Email 12346: Permission denied
    - Email 12347: Parse error (corrupted .emlx)

Run with --verbose to see detailed error log
```

**AppleScript Errors**:
```bash
ERROR: Mail.app automation failed
→ Ensure Mail.app is running
→ Grant Terminal automation permissions: System Settings > Privacy & Security > Automation
→ Error details: "Mail got an error: Can't get message id 12345"
```

**Logging**:
```bash
swiftmail --log-level debug     # Verbose logging
swiftmail --log-file ~/logs/swiftmail.log
swiftmail logs show             # View recent logs
swiftmail logs clear            # Clear log file
```

---

## CLI Interface Design

> **Note**: As a SwiftEA module, mail commands follow the pattern `swiftea mail <subcommand>`. However, many operations can also be performed using global SwiftEA commands (e.g., `swiftea search`, `swiftea export`) that work across all modules.

### Command Structure

**Module-Specific Format**: `swiftea mail <command> [options]`
**Global Format**: `swiftea <command> [options]` (works across modules)

### Mail Module Commands

```bash
# Sync & Status
swiftea mail sync [--watch|--validate|--status]
swiftea mail status                 # Mail module status

# Search & Query
swiftea mail search <query> [options]
swiftea mail query [--from|--to|--subject|--after|--before|...]
swiftea mail get --id <id> [--format json|text]

# Export
swiftea mail export --id <id> --format <md|json> [options]
swiftea mail export --query <query> --format <md|json> [options]

# Metadata (also available via global `swiftea meta`)
swiftea mail meta set --id <id> --field <field> --value <value>
swiftea mail meta get --id <id>

# Actions (Phase 2)
swiftea mail send --to <email> --subject <subject> --body <text>
swiftea mail reply --id <id> --body <text>
swiftea mail archive --id <id>
swiftea mail delete --id <id>
swiftea mail move --id <id> --to <mailbox>
swiftea mail flag --id <id>
swiftea mail mark-read --id <id>
swiftea mail label --id <id> --add <labels>

# Rules
swiftea mail rule create --name <name> --condition <condition> --action <action>
swiftea mail rule list
swiftea mail rule delete --name <name>

# Index Management
swiftea mail index rebuild|refresh|optimize|stats
```

### Global Commands (Cross-Module)

```bash
# These commands work across all SwiftEA modules (mail, calendar, contacts, etc.)
swiftea search <query> [--mail|--calendar|--contacts]
swiftea export --id <module:id> --format <md|json>
swiftea meta set --id <module:id> --field <field> --value <value>
swiftea link --email mail:123 --event cal:456
swiftea context --project "ProjectAlpha" --json
swiftea sync [--all|--mail|--calendar]
```

### Global Options

```bash
--verbose, -v          # Verbose output
--quiet, -q            # Minimal output
--json                 # JSON output format
--dry-run              # Show what would happen without executing
--log-level <level>    # debug|info|warn|error
--log-file <path>      # Log file location
--config <path>        # Custom config file
```

### Common Option Patterns

```bash
# ID selection
--id <id>              # Single email ID (stable hash, e.g., mail:abc123)
--ids <id1,id2,id3>    # Multiple IDs
--stdin                # Read IDs from stdin

# Query/filter
--query <query>        # Search query
--from <email>
--to <email>
--subject <text>
--after <date>
--before <date>
--unread
--flagged
--has-attachment

# Output control
--format <md|json>
--output <path>
--array                # JSON array format
--batch                # Batch mode (multiple files)

# Confirmation
--confirm              # Require confirmation for destructive actions
--force                # Skip confirmations (dangerous)
```

---

## Configuration

> **Note**: Mail module configuration is part of the global SwiftEA config file. Module-specific settings are under the `modules.mail` section.

### Config File Location

`~/.config/swiftea/config.json`

### Mail Module Config Structure

```json
{
  "swiftea": {
    "version": "1.0.0",
    "database": "~/.config/swiftea/swiftea.db"
  },
  "modules": {
    "mail": {
      "enabled": true,
      "envelopeIndexPath": "~/Library/Mail/V10/MailData/Envelope Index",
      "mailVersion": 10
    }
  },
  "sync": {
    "method": "hybrid",
    "watcherEnabled": true,
    "periodicIntervalMinutes": 5,
    "autoSyncOnQuery": true
  },
  "search": {
    "defaultLimit": 100,
    "enableRanking": true,
    "enableSnippets": true,
    "snippetLength": 200
  },
  "export": {
    "defaultFormat": "markdown",
    "markdownTemplate": "frontmatter-body",
    "outputDirectory": "~/Documents/emails",
    "preserveStructure": true
  },
  "actions": {
    "requireConfirmation": true,
    "batchSizeLimit": 100,
    "rateLimit": 10
  },
  "logging": {
    "level": "info",
    "file": "~/.config/swiftmail/swiftmail.log",
    "maxSizeMB": 10,
    "rotateCount": 3
  }
}
```

**Auto-detection**: If `modules.mail.envelopeIndexPath` is not set, SwiftEA SHALL auto-detect the latest `~/Library/Mail/V*/MailData/Envelope Index` and set it at runtime.

### Config Commands

```bash
swiftea config list
swiftea config get modules.mail.envelopeIndexPath
swiftea config set modules.mail.enabled true
swiftea config set sync.periodicIntervalMinutes 10
swiftea config reset --mail           # Reset mail module config
swiftea config edit                   # Open in editor
```

---

## Implementation Phases

### Phase 1: Core Read & Export (MVP)

**Goal**: Get email data out of Apple Mail and into ClaudEA workflows

**Features**:
- ✅ Query-and-rebuild mirror into libSQL (read-only source)
- ✅ Manual sync + launchd-based `sync --watch`
- ✅ FTS5 indexing across subject/from/to/body_text
- ✅ Search commands (keyword + structured)
- ✅ Export to markdown and JSON
- ✅ Batch export
- ✅ Pipeline support (JSON envelope output)
- ✅ Attachment metadata indexing (no extraction by default)

**Deliverables**:
- `swiftea mail sync`
- `swiftea mail sync --watch`
- `swiftea mail search`
- `swiftea mail query`
- `swiftea mail get`
- `swiftea mail export`
- `swiftea mail index`

**Success Criteria**:
- Can export all emails from last 6 months as markdown
- Search across 50k emails in < 1 second
- ClaudEA can import emails into Obsidian vault

### Phase 2: Actions & Automation

**Goal**: Enable ClaudEA to take actions on emails

**Features**:
- ✅ AppleScript action layer
- ✅ Send, reply, draft
- ✅ Archive, delete, move
- ✅ Flag, label, mark read/unread
- ✅ Batch actions
- ✅ Rule creation

**Deliverables**:
- `swiftmail send/reply/draft`
- `swiftmail archive/delete/move`
- `swiftmail flag/label/mark-*`
- `swiftmail rule`

**Success Criteria**:
- ClaudEA can auto-archive newsletters
- ClaudEA can draft replies to emails
- Rules can be created programmatically

### Phase 3: Advanced Metadata & Workflows

**Goal**: Full ClaudEA integration and intelligence layer

**Features**:
- ✅ Ad-hoc column addition
- ✅ Advanced metadata queries
- ✅ File system watcher (real-time sync)
- ✅ Saved queries
- ✅ Enhanced error handling
- ✅ Performance optimization

**Deliverables**:
- `swiftmail meta add-column`
- `swiftmail sync --watch`
- `swiftmail query save/run`
- Optimized indexing for 100k+ emails

**Success Criteria**:
- ClaudEA can add custom metadata on the fly
- Sync latency < 5 seconds
- Complex queries execute in < 500ms

### Phase 4: Semantic Search & Advanced Features (Future)

**Goal**: AI-powered email intelligence

**Features**:
- 🔮 Semantic/vector search
- 🔮 Thread analysis and summarization
- 🔮 Automatic categorization
- 🔮 Smart triage and prioritization
- 🔮 Email server rule sync (Exchange/Gmail)
- 🔮 Attachment indexing and search

**Technologies**:
- sqlite-vss for vector storage
- Embeddings API (OpenAI/Anthropic) or local (Ollama)
- Enhanced NLP processing

**Success Criteria**:
- "Find emails about budget discussions" works semantically
- ClaudEA can auto-triage inbox with 95%+ accuracy
- Rules sync bidirectionally with email servers

---

## Technical Considerations

### Security & Permissions

**Required macOS Permissions**:
1. **Full Disk Access**: Access to `~/Library/Mail/`
2. **Automation**: Control Mail.app via AppleScript

**Security Principles**:
- Read-only access to Apple's Envelope Index (never write)
- All writes go to mirror database only
- No credentials stored (rely on Mail.app authentication)
- Log files exclude email content by default

### Performance Optimization

**Database**:
- SQLite WAL mode for concurrent access
- Indexes on frequently queried fields (from, to, date, status)
- FTS5 with porter stemming and unicode normalization
- Periodic VACUUM and ANALYZE

**Search**:
- Query result caching (5-minute TTL)
- Lazy loading for large result sets
- Parallel .emlx file reading for batch exports

**Sync**:
- Incremental sync (only changed rows)
- Debouncing for file system events
- Background thread for watcher

**Target Performance**:
- Sync latency: < 5 seconds
- Search query: < 1 second (100k emails)
- Export single email: < 100ms
- Batch export (1000 emails): < 30 seconds

### Data Integrity

**Strategies**:
1. **Mirror validation**: Periodic checksums against source
2. **Transaction safety**: All writes in SQLite transactions
3. **Backup**: Auto-backup before destructive operations
4. **Recovery**: Rebuild mirror from source if corrupted

**Validation Commands**:
```bash
swiftmail validate                    # Check mirror integrity
swiftmail repair                      # Rebuild corrupted tables
swiftmail backup --output ~/backup.db # Manual backup
```

### Error Recovery

**Sync Failures**:
- Automatic retry with exponential backoff
- Fall back to periodic sync if watcher fails
- Manual resync option

**Parse Failures**:
- Skip corrupted .emlx files, log error
- Continue processing remaining emails
- Report failed emails at end

**AppleScript Failures**:
- Retry up to 3 times
- Check if Mail.app is running
- Provide detailed error context

---

## Integration with ClaudEA

> **Note**: As part of SwiftEA, the mail module integrates seamlessly with other modules (calendar, contacts) to provide ClaudEA with comprehensive context. These examples show mail-specific workflows; see `swiftea-architecture.md` for cross-module integration patterns.

### Use Cases

**1. Daily Email Triage**
```bash
# ClaudEA morning routine
swiftea mail search "is:unread" --json | claudea triage-emails

# ClaudEA auto-archives newsletters
swiftea mail archive --query "from:*newsletter.com"

# ClaudEA flags urgent emails
swiftea meta set --query "is:unread from:boss.com" --mail --field priority_score --value 10
```

**2. Project Context Gathering**
```bash
# Export all emails for a project
swiftea mail export --query "project alpha" --format markdown --output ~/vault/projects/alpha/emails/

# ClaudEA summarizes project communications
swiftea mail search "project alpha" --json | claudea summarize-project

# Or use cross-module context (includes calendar events, contacts, etc.):
swiftea context --project "ProjectAlpha" --json | claudea analyze-project
```

**3. Task Extraction**
```bash
# Find emails needing response
swiftea mail query --meta-field processing_status --meta-value "needs-response"

# ClaudEA extracts tasks from emails
swiftea mail search "action item OR to-do" --json | claudea extract-tasks

# Link emails to tasks (cross-module)
swiftea link --email mail:12345 --task task:789
swiftea meta set --id mail:12345 --field linked_tasks --value '["task:789"]'
```

**4. Knowledge Base Population**
```bash
# Initial vault setup: export last 6 months
swiftea mail export --after "2025-07-01" --format markdown --output ~/vault/emails/

# Continuous sync to Obsidian
swiftea sync --watch &  # Syncs all modules including mail
swiftea mail monitor-new | claudea process-new-emails
```

**5. Automated Responses**
```bash
# ClaudEA drafts replies
claudea draft-reply --email-id mail:12345 | swiftea mail send --stdin

# Auto-respond to common requests
swiftea mail search "out of office request" --unread | claudea auto-respond
```

**6. Cross-Module Intelligence** (SwiftEA advantage)
```bash
# Link email to calendar event
swiftea mail get --id 12345 --json | claudea detect-event | swiftea link --stdin

# Find all communications with a contact
swiftea search "from:bob@example.com" --all --json
# Returns: emails, calendar events with Bob as attendee, Bob's contact info
```

### API for ClaudEA (Future)

**Swift Package**: `SwiftEAKit` (with MailModule)

```swift
import SwiftEAKit

let swiftea = SwiftEAClient()
let mail = swiftea.mail  // Access mail module

// Search emails
let emails = try await mail.search("project alpha", unread: true)

// Cross-module search
let results = try await swiftea.search("project alpha", modules: [.mail, .calendar])

// Get metadata (works across modules)
let metadata = try await swiftea.metadata.get(itemId: "mail:12345")

// Update metadata
try await swiftea.metadata.set(itemId: "mail:12345", field: "priority_score", value: 9)

// Export
try await mail.export(emailId: 12345, format: .markdown, output: "/path/to/file.md")

// Actions
try await mail.send(to: "bob@example.com", subject: "Hello", body: "Message")
try await mail.archive(emailIds: [12345, 12346, 12347])

// Cross-module linking
try await swiftea.link(from: "mail:12345", to: "cal:789", type: .related)

// Context gathering
let context = try await swiftea.context(project: "ProjectAlpha")
// Returns: emails, events, contacts, tasks
```

---

## Testing Strategy

### Unit Tests
- SQLite query builders
- .emlx parsers
- Markdown/JSON formatters
- AppleScript generators

### Integration Tests
- Sync operations against test database
- Search accuracy and ranking
- Export format validation
- Action execution (with mock Mail.app)

### Performance Tests
- Search benchmarks (10k, 50k, 100k emails)
- Sync latency measurements
- Batch export throughput
- Memory usage profiling

### User Acceptance Tests
- ClaudEA workflows end-to-end
- Obsidian vault integration
- Real-world email corpus testing

---

## Documentation Plan

### User Documentation
- Installation and setup guide
- Permission configuration walkthrough
- Command reference with examples
- ClaudEA integration cookbook
- Troubleshooting guide

### Developer Documentation
- Architecture overview
- Database schema documentation
- AppleScript templates
- Extension/plugin guide
- Contributing guidelines

### ClaudEA Integration Guide
- Workflow examples
- Skill/command templates
- Best practices
- Performance tuning

---

## Success Metrics

### Phase 1 (MVP)
- ✅ 100% of emails accessible via SQLite
- ✅ Search results in < 1 second (50k emails)
- ✅ Export preserves all metadata and formatting
- ✅ ClaudEA can import 10k emails into Obsidian vault

### Phase 2 (Actions)
- ✅ All core actions working (send, archive, flag, etc.)
- ✅ Batch operations handle 100+ emails reliably
- ✅ Rule creation working for common patterns
- ✅ ClaudEA can automate 80% of email triage

### Phase 3 (Advanced)
- ✅ Sync latency < 5 seconds
- ✅ Custom metadata queries in < 500ms
- ✅ Zero data loss during sync
- ✅ ClaudEA creates custom workflows with ad-hoc metadata

### Long-term
- 🔮 10k+ active users
- 🔮 Integration with other email clients (Outlook, Gmail)
- 🔮 Obsidian plugin with 1k+ downloads
- 🔮 ClaudEA email management rated 9+/10 by users

---

## Appendices

### Appendix A: Apple Mail Database Schema

**Key Tables** (Envelope Index):
- `messages`: Core message data (ROWID, date_sent, date_received, etc.)
- `subjects`: Email subjects (subject_id, subject text)
- `addresses`: Email addresses (address_id, address, comment)
- `mailboxes`: Mailbox structure
- `message_data`: Additional message metadata

**Useful Joins**:
```sql
SELECT
  m.ROWID,
  s.subject,
  addr_from.address as from_email,
  addr_from.comment as from_name,
  m.date_received
FROM messages m
JOIN subjects s ON m.subject = s.ROWID
JOIN addresses addr_from ON m.sender = addr_from.ROWID
WHERE m.date_received > strftime('%s', 'now', '-7 days')
```

### Appendix B: .emlx File Format

**Structure**:
```
[byte count]\n
[Raw RFC822/MIME email content]
[XML plist with metadata]
```

**Example**:
```
12345
From: bob@example.com
To: you@example.com
Subject: Hello
Content-Type: text/plain

Email body here
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist...>
<plist version="1.0">
  <dict>
    <key>flags</key>
    <integer>8589934592</integer>
  </dict>
</plist>
```

### Appendix C: AppleScript Examples

**Send Email**:
```applescript
tell application "Mail"
  set theMessage to make new outgoing message with properties {subject:"Hello", content:"Body text", visible:true}
  tell theMessage
    make new to recipient with properties {address:"bob@example.com"}
    send
  end tell
end tell
```

**Archive Email**:
```applescript
tell application "Mail"
  set theMessage to message id "12345@mail.local"
  move theMessage to mailbox "Archive"
end tell
```

### Appendix D: Performance Benchmarks (Targets)

| Operation | 10k emails | 50k emails | 100k emails |
|-----------|------------|------------|-------------|
| Full sync | 5s | 20s | 45s |
| Incremental sync | < 1s | < 2s | < 5s |
| Keyword search | < 100ms | < 500ms | < 1s |
| Ranked search | < 200ms | < 700ms | < 1.5s |
| Export single | < 50ms | < 100ms | < 150ms |
| Batch export (100) | 3s | 5s | 10s |
| Batch archive (100) | 5s | 8s | 15s |

### Appendix E: Future Enhancements

**Short-term (6 months)**:
- Attachment extraction and indexing
- Thread collapsing and analysis
- Email templates for common responses
- Smart folder/label suggestions

**Medium-term (1 year)**:
- Semantic search with embeddings
- Automatic email categorization
- Integration with task managers (Things, Todoist)
- Calendar event extraction

**Long-term (2+ years)**:
- Multi-client support (Outlook, Thunderbird)
- Web interface for remote access
- Mobile app integration
- AI-powered email composition

---

## Conclusion

The SwiftEA Mail Module provides the foundation for ClaudEA's email intelligence, while integrating seamlessly with the broader SwiftEA ecosystem (calendar, contacts, tasks, notes). By combining direct database access, full-text search, custom metadata, and automation capabilities within a unified knowledge graph, it enables workflows that are impossible with traditional email clients or standalone tools.

**Key Differentiators**:
- **No API limitations**: Direct access to all email data
- **Unified knowledge graph**: Emails linked to events, contacts, tasks, projects
- **Cross-module intelligence**: Search and analyze across all data types
- **Custom metadata**: Shared metadata system works across all modules
- **CLI-first**: Scriptable, automatable, ClaudEA-friendly
- **Privacy-preserving**: All data stays local, you control everything
- **Modular architecture**: Part of SwiftEA but can evolve independently

**Integration Benefits**:
- Single command to search emails + calendar + contacts
- Link emails to calendar events automatically
- Unified project context gathering
- Consistent metadata and tagging across all modules
- One database, one search index, one sync engine

**Next Steps**:
1. Review and approve this specification
2. Align with `swiftea-architecture.md`
3. Set up SwiftEA development environment
4. Begin Phase 1 implementation (Mail Module + Core)
5. Iterate based on real-world ClaudEA usage

**See Also**:
- `swiftea-architecture.md` - Overall SwiftEA architecture and cross-module features
- `swift-mail-cli-idea.md` - Original idea document

---

**Document Version**: 2.0 (Updated for SwiftEA)
**Last Updated**: 2026-01-06
**Status**: Approved as SwiftEA Mail Module Specification
