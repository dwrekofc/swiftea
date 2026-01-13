# SwiftEA Comprehensive Code Review (Staff Engineer Audit)

Scope: repo-wide audit of SwiftEA as of current working tree. Focused on architecture, idempotency, observability, security/multi-tenancy, performance, and extensibility. This document collates all findings to date. It intentionally contains **no recommendations** or fixes.

## Objective (as implemented)
SwiftEA is a macOS CLI that mirrors Apple Mail (and eventually Calendar/Contacts) into a local vault and provides search/export/action workflows from a unified command surface. The current implemented scope is primarily Mail. Core flow is: create vault → bind accounts → sync Apple data into a local libSQL DB → search/show/export via CLI. Mail actions are stubbed for future AppleScript execution.

## Tech Stack (as implemented)
- Language/runtime: Swift 6, macOS 14 target.
- CLI: swift-argument-parser.
- Storage: libSQL (via libsql-swift) for mirror DB; direct read-only SQLite3 access to Apple Mail’s “Envelope Index”.
- OS integration: AppleScript (Mail/Calendar account discovery), LaunchAgents for sync daemon.
- Parsing: custom .emlx parsing (RFC822/quoted-printable/base64 partial implementation).

## Current Status (as implemented)
- Vault system: functional init/status/bind/unbind; registry stored in `~/.config/swiftea/account-bindings.json`.
- Mail sync: implemented (full + incremental), including mailbox discovery, message ingest, status/deletion detection, FTS5 indexing.
- Mail search/show/export: implemented and wired to mirror DB.
- Mail actions (archive/delete/move/flag/mark/reply/compose): present but stubbed (no AppleScript execution).
- Calendar/Contacts/Search/Export/Status/Config commands: mostly placeholders.

## Happy Path (current)
1. `swiftea vault init`
2. `swiftea vault bind`
3. `swiftea mail sync [--incremental]`
4. `swiftea mail search <query>` / `swiftea mail show <message-id>`
5. `swiftea mail export [--id <id> | --query <q> | --limit N]`

---

# Findings

## [BLOCKER] Non-atomic, partial-state sync (inconsistent mirror DB on failure)
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`, `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
- **What**: `MailSync.sync()` streams writes directly to the mirror without transactional boundaries. A crash or forced termination mid-sync leaves partially updated state. Incremental sync trusts `lastSyncTime` and assumes a consistent mirror, but the mirror can be corrupt.
- **Impact**: Partial updates persist, and incremental sync may never repair missing or inconsistent data.
- **Future post-mortem**: “A mid-sync crash during a full rebuild left a partial mirror; incremental syncs after that never re-added missing messages, causing permanent data loss in exports.”

## [BLOCKER] SQL injection & corruption risk from string-interpolated queries
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
- **What**: SQL queries are built with string interpolation. `escapeSql` only replaces single quotes and is used inconsistently. FTS `MATCH` uses interpolated query text. Untrusted mail data (subject/body/sender) and user input (search query) can break SQL or cause undefined behavior.
- **Impact**: Sync crashes, failed reads, or index corruption from malformed or adversarial input.
- **Future post-mortem**: “A crafted email subject caused SQL parse errors during sync, aborting mail mirroring and leaving the database unusable until manual repair.”

## [BLOCKER] Incremental sync can silently miss or misclassify changes
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- **What**: Incremental sync uses `date_received > lastSyncTime` for new messages. Backfilled messages or moved messages with old dates are skipped. Deletion detection relies on `ROWID` existence only, which can be reused or behave unexpectedly across mailbox migrations.
- **Impact**: Silent data loss in mirror; status appears “success”.
- **Future post-mortem**: “A user’s migrated mailbox had older date_received values; incremental sync never ingested them, and exports silently omitted thousands of emails.”

## [BLOCKER] AppleScript discovery errors are swallowed
- **Where**: `Sources/SwiftEAKit/Core/AccountDiscovery.swift`
- **What**: `discoverAllAccounts()` catches and ignores errors for Mail/Calendar discovery. Permission or AppleScript failures are hidden and silently result in empty accounts.
- **Impact**: The system proceeds with an empty or incomplete account list without actionable diagnostics.
- **Future post-mortem**: “The on-call could not diagnose missing accounts because the system swallowed the AppleScript error, leading to a week of empty syncs and false success reports.”

## [BLOCKER] Mailbox/account isolation is broken in mirror schema
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`, `MailSync.syncMailboxes()`
- **What**: Mailboxes are inserted with `accountId: ""` and messages don’t enforce account scoping. Apple Mail `mailboxes.ROWID` can collide across accounts; mirror uses ROWID as primary key with no namespace.
- **Impact**: Cross-account mailbox collisions, wrong mailbox attribution, and incorrect exports.
- **Future post-mortem**: “Mailbox ROWID collisions across accounts caused messages to appear in the wrong mailbox, and exports leaked the wrong account’s email threads.”

## [BLOCKER] Migrations are not safely transactional
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
- **What**: Migrations are applied without explicit transaction boundaries; schema versioning is coarse. A failure mid-migration can leave schema half-applied.
- **Impact**: Broken schema or missing triggers with schema_version advanced, causing inconsistent behavior (e.g., empty search results).
- **Future post-mortem**: “A migration failure left the FTS triggers absent but schema_version advanced, causing search to silently return empty results.”

## [BLOCKER] Multi-vault, multi-tenant state is inconsistent
- **Where**: `Sources/SwiftEAKit/Core/BindingRegistry.swift`, `Sources/SwiftEAKit/Core/VaultManager.swift`, `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
- **What**: Account bindings are global but mirror DBs are per-vault. Schema doesn’t consistently store account IDs. If registry is corrupted or edited, same account can be bound to multiple vaults with no detection.
- **Impact**: Multiple vaults can race and diverge; no way to detect which mirror is authoritative.
- **Future post-mortem**: “A user accidentally bound the same Mail account to two vaults; both daemons ran and each overwrote mailbox status, leaving exports inconsistent between vaults.”

## [BLOCKER] Sync is not reentrant or concurrency-safe
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`, `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- **What**: Sync can be triggered by CLI and LaunchAgent; WAL mode is enabled but no advisory lock is used. Multiple syncs can interleave and clobber status markers.
- **Impact**: Inconsistent sync_status; partial or conflicting writes.
- **Future post-mortem**: “Two syncs started concurrently and interleaved writes; the database recorded a ‘success’ with missing messages, and the follow-up incremental skipped them forever.”

## [BLOCKER] Apple Mail schema assumptions are brittle
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- **What**: Hardcoded table/column names (subjects, addresses, messages fields) assume stable schema across macOS versions. No schema detection or compatibility checks.
- **Impact**: macOS updates may break sync (empty results or wrong data), possibly without hard failure.
- **Future post-mortem**: “After a macOS update, Apple Mail schema changed; sync queries returned empty results, and the mirror was cleared and marked ‘success’ with zero messages.”

---

## [DEBT] No idempotency boundaries for exported files
- **Where**: `Sources/SwiftEACLI/Commands/MailCommand.swift` (MailExportCommand)
- **What**: Export overwrites filenames (message.id) and updates DB export_path regardless of partial write. If process crashes mid-export, DB still points to corrupt/truncated file.
- **Impact**: Silent corruption of exported artifacts.

## [DEBT] Vault context is overly strict and brittle
- **Where**: `Sources/SwiftEAKit/Core/VaultContext.swift`
- **What**: Vault must be exact CWD; no parent directory search. Watch daemon sets WorkingDirectory to vault root, but user run from subdir fails.
- **Impact**: Hard-to-debug user errors; inconsistent behavior between daemon and CLI usage.

## [DEBT] Binding registry atomicity and concurrency risks
- **Where**: `Sources/SwiftEAKit/Core/BindingRegistry.swift`
- **What**: `saveRegistry` removes existing registry before move; a failure after remove loses registry. No file locking: concurrent writes can interleave.
- **Impact**: Lost bindings, ghost state, or inconsistent account-vault mapping.

## [DEBT] Observability gaps in sync and parsing
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- **What**: .emlx parse errors are swallowed (no log). Per-message errors are strings without strong context (mailbox/account/path). Sync success is logged even if errors list exists.
- **Impact**: On-call can’t diagnose missing content; users see “success” with missing data.

## [DEBT] LaunchAgent path resolution is brittle
- **Where**: `Sources/SwiftEACLI/Commands/MailCommand.swift`
- **What**: LaunchAgent uses `ProcessInfo.processInfo.arguments[0]` and resolves relative paths against CWD. Running from an unexpected directory can install a non-working daemon path.
- **Impact**: Daemon fails silently; `--status` shows stopped with no root cause.

## [DEBT] Hard-coded macOS filesystem assumptions
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/EnvelopeIndexDiscovery.swift`, `Sources/SwiftEACLI/Commands/MailCommand.swift`
- **What**: Direct reliance on `~/Library/Mail`, `~/Library/LaunchAgents`. No abstraction for alternative paths or platforms.
- **Impact**: Limits portability; future expansion to non-macOS sources requires rewrite.

## [DEBT] O(n^2) status change detection for large mailboxes
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift` (`detectStatusChanges`)
- **What**: For each queried row, code scans `existingMessages.first(where:)`, yielding O(n^2) behavior.
- **Impact**: Degrades badly at large scale (hundreds of thousands of messages).

## [DEBT] Partial RFC support in EMLX parsing
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/EmlxParser.swift`
- **What**: Multipart parsing is simplified; quoted-printable decoding does not properly handle soft line breaks or charset per part. Recursive parsing does not preserve per-part charset.
- **Impact**: Body corruption, missing or garbled output, unreliable exports.

## [DEBT] Lack of storage abstraction
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`, `MailDatabase.swift`
- **What**: MailSync is coupled directly to libSQL schema and query patterns. No storage interface exists.
- **Impact**: Swapping storage backend (Postgres/RDS/Elastic) becomes a rewrite.

## [DEBT] Export formats are incomplete for round-trip or rebuild
- **Where**: `Sources/SwiftEACLI/Commands/MailCommand.swift`
- **What**: Export omits recipients, attachments, full mailbox path, internal rowids. JSON/Markdown output cannot reconstruct message graph or metadata.
- **Impact**: Future re-import, diffing, or analytics are limited.

## [DEBT] Error messages lack operational context
- **Where**: Various (MailSync, MailDatabase, VaultManager, BindingRegistry)
- **What**: Errors typically do not include account ID, mailbox path, or file path context. Sync errors list only `Message <rowid>: <error>`.
- **Impact**: Debugging requires manual forensics.

## [DEBT] Message identity stability assumptions are weak
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/StableIdGenerator.swift`
- **What**: Message-ID is used when present; fallback uses subject/sender/date/rowid. These can change (or collide), producing unstable IDs and duplicates over time.
- **Impact**: Duplicate records or churn in message IDs during incremental sync.

## [DEBT] Mailbox URL to path conversion is a heuristic
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- **What**: `convertMailboxUrlToPath` is simplified and may not handle internal mailbox URL formats. This can generate invalid paths.
- **Impact**: Missing bodies and attachments; false “no body available”.

---

## [OPTIMIZATION] Full sync parses message bodies unconditionally
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- **What**: .emlx parsing is executed for every message, even when body data is not needed by the caller.
- **Impact**: Significant IO and CPU overhead; long sync times.

## [OPTIMIZATION] FTS triggers cause write amplification
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
- **What**: Triggers delete and reinsert FTS rows on any update, even when text fields unchanged.
- **Impact**: Slow incremental syncs and heavy index churn.

## [OPTIMIZATION] Synchronous single-threaded parsing/ingest
- **Where**: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- **What**: For each message, parse/IO and DB writes are done inline on a single thread.
- **Impact**: Poor throughput; encourages users to abort syncs, increasing partial-state risk.

---

# Additional Architectural / Extensibility Notes (non-recommendations)
- Account discovery is tightly coupled to AppleScript for Mail/Calendar only, with no provider abstraction.
- Vault config version exists but no migration/validation logic; future schema evolution will be fragile.
- Sync status tracking is spread across multiple keys and writes, making it internally inconsistent if interrupted.
- Many commands are placeholders (Calendar/Contacts/Search/Export/Status/Config), indicating large planned scope but no scaffolding for shared storage or module boundaries.

---

End of report.
