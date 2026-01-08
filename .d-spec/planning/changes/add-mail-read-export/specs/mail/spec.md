## ADDED Requirements
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
