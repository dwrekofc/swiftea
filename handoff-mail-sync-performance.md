# Handoff: Mail Sync Performance Overhaul

**Created:** 2026-01-14
**Priority:** P0 (Critical - blocking user testing)
**Context:** Initial mail sync of 124k messages is unacceptably slow (estimated 30+ minutes). User cannot complete basic testing workflow.

---

## Background

The current `swea mail sync` implementation has severe performance issues:

1. **Single-threaded sequential processing** - One message at a time
2. **124k+ individual database operations** - No batching
3. **Redundant queries** - Mailbox lookup happens twice per message
4. **Unnecessary work** - Parses .emlx files for ALL mailboxes (trash, junk, archive, etc.)
5. **No direct SQLite copy** - Data passes through Swift unnecessarily

**Current flow per message:**
- Generate stable ID
- Query DB to check if message exists (124k queries)
- Query mailbox info (124k queries, done TWICE!)
- Read .emlx file from disk (124k disk reads)
- Parse MIME content
- Insert to DB (124k individual inserts)

**Result:** ~500k operations for 124k messages = 30+ minute initial sync

---

## Desired Behavior

### Initial Sync (First Time)
1. **Direct SQLite copy** - Use `ATTACH DATABASE` and `INSERT INTO ... SELECT FROM` to bulk copy metadata from Apple Mail's Envelope Index to vault database
2. **Inbox-only body parsing** - Only parse .emlx files for INBOX mailbox
3. **Skip other mailboxes** - No body parsing for Archive, Trash, Junk, Sent, Drafts, etc.
4. **Parallel processing** - Use Swift concurrency for .emlx parsing
5. **Batch DB operations** - Wrap inserts in transactions, batch 1000+ at a time

### Incremental Sync (Subsequent)
- Already implemented with `--incremental` flag
- Should remain fast (only processes changes)

### On-Demand Body Fetching
- When user views a message from Archive/Trash/etc., fetch and cache body at that time
- Bodies are optional - metadata is always available

---

## Implementation Tasks

Create these as **P0 priority** beads issues. They form a dependency chain:

### Task 1: Direct SQLite Bulk Copy (Highest Impact)
**Title:** `Implement direct SQLite ATTACH/INSERT for initial mail sync`
**Type:** `feature`
**Priority:** `P0`

**Description:**
```markdown
## Goal
Replace the current row-by-row Swift sync with direct SQLite bulk copy for 10-100x speedup on initial sync.

## Approach
1. Use SQLite `ATTACH DATABASE` to connect Apple Mail's Envelope Index
2. Use `INSERT INTO messages SELECT ... FROM attached.messages` for bulk copy
3. Handle schema differences with column mapping
4. Only activate for full (non-incremental) syncs

## Acceptance Criteria
- [ ] Create new `MailSyncBulk.swift` or add bulk mode to existing `MailSync`
- [ ] Implement `ATTACH DATABASE` connection to Envelope Index
- [ ] Map Envelope Index schema to vault schema
- [ ] Bulk copy all message metadata in single transaction
- [ ] Bulk copy all mailbox metadata
- [ ] Add `--bulk` flag or auto-detect first sync
- [ ] Benchmark: Initial sync should complete in <60 seconds for 100k messages
- [ ] Tests pass

## Technical Notes
- Envelope Index path: `~/Library/Mail/V10/MailData/Envelope Index`
- Key tables: `messages`, `mailboxes`, `addresses`
- Vault DB path: `<vault>/.swiftea/mail.db`

## Files to Modify
- `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
- `Sources/SwiftEACLI/Commands/MailCommand.swift`
```

---

### Task 2: Inbox-Only Body Parsing
**Title:** `Limit .emlx body parsing to INBOX only on initial sync`
**Type:** `feature`
**Priority:** `P0`
**Depends on:** Task 1

**Description:**
```markdown
## Goal
Only parse .emlx files for INBOX mailbox during initial sync. Other mailboxes get metadata only.

## Rationale
- User only needs bodies for inbox (actionable messages)
- Archive/Trash/Junk/Sent bodies are rarely needed
- Reduces initial sync I/O by 80-90%

## Acceptance Criteria
- [ ] Identify INBOX mailbox from mailboxes table (url contains "INBOX")
- [ ] Only call `EmlxParser` for messages in INBOX
- [ ] Other mailboxes get metadata only (subject, sender, date, flags)
- [ ] Add `--mailbox <name>` filter flag to sync specific mailboxes
- [ ] Add `--metadata-only` flag to skip all body parsing
- [ ] Document behavior in help text
- [ ] Tests pass

## On-Demand Fetching (Separate Task)
Bodies for non-INBOX messages should be fetchable via `swea mail show <id>` - this is a separate task.

## Files to Modify
- `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- `Sources/SwiftEACLI/Commands/MailCommand.swift`
```

---

### Task 3: Parallel .emlx Parsing
**Title:** `Add parallel processing for .emlx body parsing`
**Type:** `feature`
**Priority:** `P1`
**Depends on:** Task 2

**Description:**
```markdown
## Goal
Use Swift concurrency to parse multiple .emlx files in parallel, utilizing all CPU cores.

## Approach
1. Use `TaskGroup` or `AsyncStream` for parallel file parsing
2. Batch messages into groups of 100-500
3. Parse batch in parallel with `withTaskGroup`
4. Collect results and batch-insert to DB

## Acceptance Criteria
- [ ] Implement parallel parsing using Swift structured concurrency
- [ ] Configurable concurrency level (default: `ProcessInfo.processInfo.activeProcessorCount`)
- [ ] Add `--parallel <n>` flag to control worker count
- [ ] Progress reporting still works (aggregate from workers)
- [ ] No data races or crashes under parallel load
- [ ] Benchmark: 2-4x speedup on multi-core Macs
- [ ] Tests pass

## Technical Notes
- `EmlxParser` must be thread-safe (currently is - stateless)
- DB writes must be serialized (use actor or serial queue)
- File I/O is the bottleneck - parallelize that

## Files to Modify
- `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- `Sources/SwiftEAKit/Modules/MailModule/EmlxParser.swift` (verify thread safety)
```

---

### Task 4: Batch Database Operations
**Title:** `Batch database inserts with transactions`
**Type:** `feature`
**Priority:** `P1`
**Depends on:** Task 1

**Description:**
```markdown
## Goal
Replace individual INSERT statements with batched transactions for 5-10x DB write speedup.

## Approach
1. Collect messages in batches of 1000
2. Wrap batch in single transaction: `BEGIN; INSERT...; INSERT...; COMMIT;`
3. Use prepared statements with parameter binding
4. Consider `INSERT OR REPLACE` for upsert behavior

## Acceptance Criteria
- [ ] Add batch insert method to `MailDatabase`
- [ ] Configurable batch size (default: 1000)
- [ ] All inserts wrapped in transactions
- [ ] Prepared statements reused across batch
- [ ] Rollback on error (don't lose partial batch)
- [ ] Benchmark: 5-10x faster DB writes
- [ ] Tests pass

## Files to Modify
- `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
- `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
```

---

### Task 5: Cache Mailbox Lookups
**Title:** `Cache mailbox metadata to eliminate redundant queries`
**Type:** `bug`
**Priority:** `P1`

**Description:**
```markdown
## Goal
Query mailboxes table once at sync start, cache in memory, eliminate 248k redundant queries.

## Current Problem
In `MailSync.processMessage()`, mailbox is queried TWICE per message:
- Line 618: Query for mailbox name
- Line 633: Query again for mailbox path

For 124k messages = 248k unnecessary queries.

## Fix
1. Query all mailboxes at sync start
2. Cache in `[Int: MailboxInfo]` dictionary (keyed by ROWID)
3. Look up from cache in `processMessage()`

## Acceptance Criteria
- [ ] Add `private var mailboxCache: [Int: MailboxInfo]` to MailSync
- [ ] Populate cache once in `performSync()` before processing messages
- [ ] Replace both mailbox queries in `processMessage()` with cache lookup
- [ ] Benchmark: Measurable speedup from eliminated queries
- [ ] Tests pass

## Files to Modify
- `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
```

---

### Task 6: On-Demand Body Fetching
**Title:** `Fetch message body on-demand for non-INBOX messages`
**Type:** `feature`
**Priority:** `P2`
**Depends on:** Task 2

**Description:**
```markdown
## Goal
When user runs `swea mail show <id>` for a message without cached body, fetch and cache it.

## Acceptance Criteria
- [ ] `mail show` checks if body is null/empty
- [ ] If missing, locate .emlx file and parse body
- [ ] Update database with fetched body
- [ ] Display body to user
- [ ] Add `--no-fetch` flag to skip on-demand fetching
- [ ] Handle case where .emlx file no longer exists (deleted from Mail.app)
- [ ] Tests pass

## Files to Modify
- `Sources/SwiftEACLI/Commands/MailCommand.swift` (show subcommand)
- `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
```

---

## Dependency Graph

```
Task 1 (Bulk SQLite Copy) ─┬─► Task 2 (Inbox-Only) ─► Task 3 (Parallel)
                           │                          │
                           └─► Task 4 (Batch DB) ◄────┘

Task 5 (Cache Mailbox) ─► Independent, do anytime

Task 6 (On-Demand Fetch) ─► Depends on Task 2
```

---

## Commands to Create Issues

Run these in the swiftea directory:

```bash
# Task 1 - Bulk SQLite Copy (P0)
bd create --title "Implement direct SQLite ATTACH/INSERT for initial mail sync" --type feature --priority 0

# Task 2 - Inbox-Only Body Parsing (P0)
bd create --title "Limit .emlx body parsing to INBOX only on initial sync" --type feature --priority 0

# Task 3 - Parallel Parsing (P1)
bd create --title "Add parallel processing for .emlx body parsing" --type feature --priority 1

# Task 4 - Batch DB Operations (P1)
bd create --title "Batch database inserts with transactions" --type feature --priority 1

# Task 5 - Cache Mailbox Lookups (P1)
bd create --title "Cache mailbox metadata to eliminate redundant queries" --type bug --priority 1

# Task 6 - On-Demand Body Fetching (P2)
bd create --title "Fetch message body on-demand for non-INBOX messages" --type feature --priority 2

# Add dependencies after creation
bd dep add <task2-id> <task1-id>  # Task 2 depends on Task 1
bd dep add <task3-id> <task2-id>  # Task 3 depends on Task 2
bd dep add <task6-id> <task2-id>  # Task 6 depends on Task 2
```

---

## Expected Outcomes

| Metric | Current | After Optimization |
|--------|---------|-------------------|
| Initial sync (124k messages) | 30+ minutes | < 60 seconds |
| Disk I/O (initial sync) | 124k file reads | ~12k file reads (inbox only) |
| DB operations | 500k+ | ~10 bulk operations |
| CPU utilization | Single core | All cores |

---

## Session Context (What Was Done Today)

1. Fixed root command to use `AsyncParsableCommand` (was crashing)
2. Fixed Calendar AppleScript account discovery (was hanging)
3. Removed misleading `vault bind` step from init message
4. Added progress output to mail sync (was showing no feedback)
5. Created `Makefile` for easy build/install
6. Created `test-tutorial.md` walkthrough
7. Identified all performance bottlenecks in mail sync

**Files modified this session:**
- `Sources/SwiftEA/main.swift` - AsyncParsableCommand fix
- `Sources/SwiftEAKit/Core/AccountDiscovery.swift` - Calendar fix
- `Sources/SwiftEACLI/Commands/VaultCommand.swift` - Removed vault bind step
- `Sources/SwiftEACLI/Commands/MailCommand.swift` - Added progress output
- `Makefile` - New file
- `test-tutorial.md` - New file

---

## If You Cannot Complete All Tasks

Follow the Partial Completion Protocol:

1. Check off completed acceptance criteria in each task
2. Add progress comment: `bd comments add <id> "Session ended: X/Y criteria done..."`
3. Commit partial work: `git commit -m "WIP: <task-id> - <summary>"`
4. Push changes: `git push`
5. Leave incomplete tasks as `in_progress`

Do NOT close tasks until ALL acceptance criteria are checked and tests pass.
