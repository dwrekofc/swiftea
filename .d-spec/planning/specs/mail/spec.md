# Mail Capability Spec

## Requirements

### Requirement: Read-only Source Access
The mail module SHALL read Apple Mail data without writing to Apple-managed databases or files. The system SHALL require Full Disk Access for `~/Library/Mail/` and SHALL fail with actionable guidance when permissions are missing.

#### Scenario: Missing permission
- **WHEN** the user runs `swiftea mail sync`
- **AND** Full Disk Access is not granted
- **THEN** the system SHALL return a permission error
- **AND** SHALL provide steps to grant Full Disk Access

### Requirement: Mail Mirror Database
The system SHALL mirror Apple Mail data into a libSQL database using a query-and-rebuild approach from the source SQLite database and `.emlx` files. The mirror SHALL include core message metadata, headers, body text, and attachment metadata.

#### Scenario: Initial mirror build
- **WHEN** the user runs `swiftea mail sync` for the first time
- **THEN** the system SHALL discover the current Apple Mail Envelope Index path
- **AND** SHALL ingest all accounts and mailboxes
- **AND** SHALL populate the libSQL mirror with message metadata and body text

#### Scenario: Incremental mirror update
- **WHEN** a message changes in Apple Mail
- **THEN** the system SHALL refresh only the changed records in the libSQL mirror
- **AND** SHALL update the FTS index for affected messages

### Requirement: Stable Email Identifiers
Each mirrored email SHALL have a stable, public ID based on a deterministic hash. The system SHALL also store the Apple Mail rowid and the RFC822 Message-ID when available.

#### Scenario: ID generation with Message-ID
- **WHEN** an email has a valid Message-ID header
- **THEN** the system SHALL use a stable hash derived from the Message-ID as the public ID
- **AND** SHALL store the original Message-ID in the mirror

#### Scenario: ID generation without Message-ID
- **WHEN** an email lacks a Message-ID header
- **THEN** the system SHALL generate a deterministic hash from a fallback header digest
- **AND** SHALL store the Apple Mail rowid for reverse lookup

### Requirement: Watch Mode
The system SHALL provide `swiftea mail sync --watch` to install and run a LaunchAgent that keeps the mirror in near-real-time sync. On start and wake, the watch process SHALL run an incremental sync. On transient errors, it SHALL retry with backoff.

#### Scenario: Watch startup
- **WHEN** the user runs `swiftea mail sync --watch`
- **THEN** the system SHALL install and start a LaunchAgent
- **AND** SHALL run an incremental sync before entering watch mode

#### Scenario: Transient error
- **WHEN** the watch process encounters a locked source database
- **THEN** the system SHALL log a warning
- **AND** SHALL retry after a backoff interval

### Requirement: Full-Text Search Index
The mirror SHALL include an FTS5 index with separate columns for `subject`, `from`, `to`, and `body_text`. Search SHALL query all indexed fields by default.

#### Scenario: Search across headers and body
- **WHEN** a user runs `swiftea mail search "budget"`
- **THEN** the system SHALL return messages matching `subject`, `from`, `to`, or `body_text`
- **AND** SHALL rank results using FTS5 BM25

### Requirement: Body Parsing and Selection
The system SHALL parse `.emlx` files to extract headers and body content. For export and indexing, the system SHALL prefer the plain-text body when available and SHALL only convert HTML to markdown when no plain-text body exists.

#### Scenario: Plain text preferred
- **WHEN** a message contains both plain text and HTML parts
- **THEN** the system SHALL use the plain-text body for export and indexing

#### Scenario: HTML fallback
- **WHEN** a message contains only HTML
- **THEN** the system SHALL convert HTML to markdown for export
- **AND** SHALL store plain-text equivalents for indexing

### Requirement: Markdown Export Format
The system SHALL export emails to markdown with a minimal YAML frontmatter containing: `id`, `subject`, `from`, `date`, and `aliases`. `aliases` SHALL contain the subject for Obsidian compatibility. Markdown filenames SHALL be `<id>.md` in a flat output folder and SHALL overwrite existing files.

#### Scenario: Export to markdown
- **WHEN** the user runs `swiftea mail export --id <id> --format markdown`
- **THEN** the system SHALL write `<id>.md` in the output directory
- **AND** SHALL include the minimal frontmatter fields
- **AND** SHALL overwrite any existing file with the same name

### Requirement: JSON Output Envelope
JSON outputs for `search`, `query`, and `get` SHALL be wrapped in an envelope containing `version`, `query`, `total`, and `items`. The envelope SHALL also include `warnings` when applicable.

#### Scenario: Search JSON output
- **WHEN** the user runs `swiftea mail search "from:bob" --json`
- **THEN** the system SHALL return an envelope with query metadata
- **AND** SHALL include matched items in `items`

### Requirement: Attachment Metadata
The mirror SHALL store attachment metadata (filename, mime type, size) and SHALL include attachment names in the search index. By default, the system SHALL NOT extract attachment files.

#### Scenario: Attachment metadata indexing
- **WHEN** a message contains attachments
- **THEN** the system SHALL record attachment metadata in the mirror
- **AND** SHALL include attachment names in FTS indexing

### Requirement: Export Path Tracking
When exporting markdown or JSON, the system SHALL record the output path for each email in the mirror database.

#### Scenario: Track export path
- **WHEN** the user exports an email
- **THEN** the system SHALL store the export path for that email
- **AND** SHALL update the path on re-export

### Requirement: Envelope Index Auto-Detection
If no path is configured, the system SHALL auto-detect the latest `~/Library/Mail/V*/MailData/Envelope Index` at runtime.

#### Scenario: Auto-detect Envelope Index
- **WHEN** `modules.mail.envelopeIndexPath` is unset
- **THEN** the system SHALL locate the latest `V*` Mail directory
- **AND** SHALL use its `MailData/Envelope Index` as the source database

### Requirement: Email Thread Detection
The mail module SHALL automatically detect and group emails into conversations based on email headers (Message-ID, References, In-Reply-To). Thread detection SHALL occur during email synchronization and SHALL be accurate for standard email clients.

#### Scenario: Thread detection during sync
- **WHEN** new emails are synced from Apple Mail
- **AND** emails have proper threading headers
- **THEN** the system SHALL automatically group them into conversations
- **AND** SHALL assign thread IDs based on Message-ID and References headers
- **AND** SHALL store thread metadata in the database

#### Scenario: Thread detection for existing emails
- **WHEN** a user runs thread detection on existing emails
- **THEN** the system SHALL analyze all emails for threading relationships
- **AND** SHALL update thread metadata for all detected conversations
- **AND** SHALL complete within 5 seconds for 100k emails

#### Scenario: Thread detection with missing headers
- **WHEN** emails lack proper threading headers
- **AND** subject lines indicate conversation relationships
- **THEN** the system SHALL use fallback subject-based grouping
- **AND** SHALL log warnings about missing headers
- **AND** SHALL still attempt to create meaningful thread groupings

### Requirement: Thread CLI Commands
The CLI SHALL provide commands for viewing and managing email conversations. Commands SHALL support various output formats and filtering options.

#### Scenario: List all conversations
- **WHEN** user runs `swiftea mail threads`
- **THEN** the system SHALL display a list of all detected conversations
- **AND** SHALL show for each thread: thread ID, subject, participants, message count, date range
- **AND** SHALL support `--limit N` to limit results
- **AND** SHALL support `--sort date|count|participants` for sorting
- **AND** SHALL support `--participant email@example.com` for filtering
- **AND** SHALL support `--format text|json|markdown` for output format

#### Scenario: View specific conversation
- **WHEN** user runs `swiftea mail thread --id thread-123`
- **THEN** the system SHALL display the full conversation thread
- **AND** SHALL show emails in chronological order
- **AND** SHALL include full email content and metadata
- **AND** SHALL support `--format text|json|markdown` for output format
- **AND** SHALL return error if thread ID not found

#### Scenario: Export conversations
- **WHEN** user runs `swiftea mail export-threads --output ~/vault/`
- **THEN** the system SHALL export all conversations to the specified directory
- **AND** SHALL create markdown files grouped by conversation
- **AND** SHALL include thread metadata in YAML frontmatter
- **AND** SHALL maintain conversation structure in exports
- **AND** SHALL support `--thread-id thread-123` for single thread export

### Requirement: Thread-aware Export Formats
Export formats SHALL preserve conversation structure and metadata. Both markdown and JSON exports SHALL include thread information.

#### Scenario: Markdown export with threads
- **WHEN** user exports emails in markdown format
- **AND** emails are part of conversations
- **THEN** the system SHALL group emails by conversation in the export
- **AND** SHALL include thread metadata in YAML frontmatter
- **AND** SHALL number emails within conversation (e.g., "Message 1/5")
- **AND** SHALL include chronological ordering
- **AND** SHALL create readable conversation flow

#### Scenario: JSON export with threads
- **WHEN** user exports emails in JSON format
- **AND** emails are part of conversations
- **THEN** the system SHALL include thread_id field for each email
- **AND** SHALL include thread_position field indicating email position in thread
- **AND** SHALL include thread_total field indicating total messages in thread
- **AND** SHALL optionally include full thread structure when requested
- **AND** SHALL support `--include-threads` flag for full thread export

### Requirement: Thread Database Schema
The database SHALL store thread metadata separate from email data. Schema SHALL support efficient thread queries and updates.

#### Scenario: Thread table creation
- **WHEN** the mail module initializes
- **THEN** the system SHALL create a `threads` table with columns:
  - `thread_id` TEXT PRIMARY KEY
  - `original_subject` TEXT
  - `normalized_subject` TEXT
  - `participant_emails` TEXT (JSON array)
  - `participant_names` TEXT (JSON array)
  - `start_timestamp` INTEGER
  - `last_timestamp` INTEGER
  - `message_count` INTEGER
  - `is_read` BOOLEAN DEFAULT FALSE
  - `labels` TEXT (JSON array)
  - `metadata` TEXT (JSON for custom fields)

#### Scenario: Email-thread relationship table
- **WHEN** the mail module initializes
- **THEN** the system SHALL create a `thread_messages` table with columns:
  - `thread_id` TEXT FOREIGN KEY REFERENCES threads(thread_id)
  - `email_id` TEXT FOREIGN KEY REFERENCES mail_mirror(email_id)
  - `position` INTEGER
  - PRIMARY KEY (thread_id, email_id)

#### Scenario: Email table thread columns
- **WHEN** the mail module initializes
- **THEN** the system SHALL add to `mail_mirror` table:
  - `thread_id` TEXT
  - `thread_position` INTEGER
  - `thread_total` INTEGER
- **AND** SHALL create indexes on `thread_id` for efficient lookups

### Requirement: Performance for Large Inboxes
Thread detection and querying SHALL perform efficiently for inboxes with 100k+ emails. Operations SHALL complete within reasonable time limits.

#### Scenario: Thread detection performance
- **WHEN** system processes 100k emails for thread detection
- **THEN** thread detection SHALL complete within 5 seconds
- **AND** SHALL use efficient header parsing algorithms
- **AND** SHALL use batch database operations
- **AND** SHALL minimize memory usage

#### Scenario: Thread query performance
- **WHEN** user queries threads in large inbox
- **THEN** thread listing SHALL return within 2 seconds
- **AND** SHALL use database indexes effectively
- **AND** SHALL support pagination for large result sets
- **AND** SHALL cache frequently accessed thread metadata

#### Scenario: Thread export performance
- **WHEN** user exports all threads from large inbox
- **THEN** export SHALL process at rate of 100+ emails per second
- **AND** SHALL use streaming output for memory efficiency
- **AND** SHALL support incremental export for large datasets

### Requirement: Automation Permission
The mail module SHALL perform write actions (archive/delete/move/flag/reply/send) via Mail.app automation and SHALL require macOS Automation permission for controlling Mail.app. When permission is missing, the system SHALL fail with actionable guidance.

#### Scenario: Missing Automation permission
- **WHEN** the user runs `swiftea mail archive --id <id>`
- **AND** SwiftEA is not permitted to control Mail.app
- **THEN** the system SHALL return an error indicating Automation permission is required
- **AND** SHALL provide steps to grant the permission in macOS System Settings

### Requirement: Mail Action Commands
The CLI SHALL provide mail action commands that operate on a selected message:
- `swiftea mail archive --id <id>`
- `swiftea mail delete --id <id>`
- `swiftea mail move --id <id> --mailbox <name>`
- `swiftea mail flag --id <id> [--set|--clear]`
- `swiftea mail mark --id <id> --read|--unread`

#### Scenario: Archive a message
- **WHEN** the user runs `swiftea mail archive --id <id> --yes`
- **THEN** the system SHALL archive the target message in Mail.app
- **AND** SHALL return a success result that includes the message id

#### Scenario: Move to mailbox
- **WHEN** the user runs `swiftea mail move --id <id> --mailbox "INBOX/Receipts" --yes`
- **THEN** the system SHALL move the target message to the specified mailbox in Mail.app
- **AND** SHALL return an error if the mailbox does not exist

### Requirement: Drafting and Sending
The CLI SHALL support creating outbound mail content via Mail.app automation:
- `swiftea mail reply --id <id> --body <text> [--send]`
- `swiftea mail compose --to <email> --subject <text> --body <text> [--send]`

If `--send` is not provided, the system SHALL create a draft rather than sending.

#### Scenario: Reply draft
- **WHEN** the user runs `swiftea mail reply --id <id> --body "Thanks, will do."`
- **THEN** the system SHALL create a draft reply in Mail.app
- **AND** SHALL return a success result that includes the draft reference

#### Scenario: Send compose
- **WHEN** the user runs `swiftea mail compose --to bob@example.com --subject "Update" --body "..." --send`
- **THEN** the system SHALL send the message via Mail.app
- **AND** SHALL return a success result that includes the sent message reference when available

### Requirement: Safe Defaults for Destructive Actions
Destructive actions (`archive`, `delete`, `move`) SHALL require explicit confirmation via `--yes` unless `--dry-run` is provided.

#### Scenario: Missing confirmation
- **WHEN** the user runs `swiftea mail delete --id <id>`
- **THEN** the system SHALL refuse to execute
- **AND** SHALL instruct the user to pass `--yes` or `--dry-run`

### Requirement: Dry Run Mode
All mail actions SHALL support `--dry-run` to show what would happen without performing automation.

#### Scenario: Dry run archive
- **WHEN** the user runs `swiftea mail archive --id <id> --dry-run`
- **THEN** the system SHALL not modify Mail.app state
- **AND** SHALL print a description of the intended action and target message

### Requirement: Message Resolution
For any action command that accepts `--id <id>`, the system SHALL resolve the SwiftEA email id to exactly one Mail.app message before executing. If resolution fails or is ambiguous, the system SHALL fail without performing the action.

#### Scenario: Message not found
- **WHEN** the user runs `swiftea mail archive --id <id> --yes`
- **AND** the message cannot be resolved in Mail.app
- **THEN** the system SHALL return a not-found error
- **AND** SHALL suggest running `swiftea mail sync` to refresh the mirror

#### Scenario: Message resolution ambiguous
- **WHEN** the user runs `swiftea mail archive --id <id> --yes`
- **AND** multiple Mail.app messages match the resolved identifiers
- **THEN** the system SHALL return an ambiguity error
- **AND** SHALL instruct the user to refine selection (e.g., use a query or a message-id)
