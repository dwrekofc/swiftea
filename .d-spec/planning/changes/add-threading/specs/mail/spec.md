## ADDED Requirements
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