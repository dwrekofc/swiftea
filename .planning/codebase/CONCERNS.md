# Codebase Concerns

**Analysis Date:** 2026-01-15

## Tech Debt

**Mail Sync Performance - Documented P0 Issue:**
- Issue: Initial sync of large mailboxes (100k+ messages) is unacceptably slow (30+ minutes) due to single-threaded sequential processing with 500k+ individual database operations
- Files: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`, `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
- Impact: Blocks user testing workflow, makes product unusable for large mail archives
- Fix approach: Six-task remediation plan documented in `handoff-mail-sync-performance.md`:
  1. Direct SQLite bulk copy using ATTACH DATABASE
  2. Inbox-only body parsing (skip Archive/Trash/Junk)
  3. Parallel .emlx parsing with Swift concurrency
  4. Batch database inserts (1000+ per transaction)
  5. Cache mailbox lookups (eliminate 248k redundant queries)
  6. On-demand body fetching for non-INBOX messages

**Redundant Mailbox Queries:**
- Issue: In `MailSync.processMessage()`, mailbox metadata is queried TWICE per message (lines ~618 and ~633)
- Files: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- Impact: For 124k messages = 248k unnecessary database queries, significant performance overhead
- Fix approach: Query all mailboxes once at sync start, cache in `[Int: MailboxInfo]` dictionary keyed by ROWID

**Single-Threaded I/O Bottleneck:**
- Issue: .emlx file parsing happens sequentially on single thread despite multi-core hardware
- Files: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`, `Sources/SwiftEAKit/Modules/MailModule/EmlxParser.swift`
- Impact: CPU utilization ~12% during sync, wastes available cores
- Fix approach: Use `TaskGroup` or `AsyncStream` for parallel file parsing (2-4x speedup expected)

**Over-Syncing Unnecessary Mailboxes:**
- Issue: Initial sync parses bodies for ALL mailboxes including Archive, Trash, Junk, Sent (~80-90% of total messages)
- Files: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- Impact: Unnecessary disk I/O, dramatically slows initial sync
- Fix approach: Default to INBOX-only body parsing, fetch other bodies on-demand via `swea mail show <id>`

**Large Files - Potential Complexity Hotspots:**
- Issue: Several files exceed 1000 lines, indicating potential complexity/maintainability issues:
  - `Sources/SwiftEACLI/Commands/MailCommand.swift` (3641 lines)
  - `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift` (2692 lines)
  - `Sources/SwiftEACLI/Commands/CalendarCommand.swift` (1302 lines)
  - `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift` (1147 lines)
- Files: As listed above
- Impact: Difficult to navigate, test, and maintain; high cognitive load for modifications
- Fix approach: Extract subcommands into separate files, split database operations into focused data access layers

**@unchecked Sendable Usage:**
- Issue: Multiple classes use `@unchecked Sendable` to bypass Swift 6 concurrency checks without proving thread safety
- Files:
  - `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift` (line 47)
  - `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift` (line 166)
  - `Sources/SwiftEAKit/Modules/MailModule/MailSyncBackward.swift` (line 56)
  - `Sources/SwiftEAKit/Modules/MailModule/MessageResolver.swift` (line 91)
  - `Sources/SwiftEAKit/Modules/MailModule/EmlxParser.swift` (line 27)
  - `Sources/SwiftEAKit/Modules/MailModule/MailSyncParallel.swift` (lines 92, 119)
  - `Sources/SwiftEAKit/Modules/CalendarModule/CalendarDatabase.swift` (line 35)
- Impact: Potential data races, crashes under concurrent access, Swift 6 migration risk
- Fix approach: Replace with proper actors, serial executors, or prove thread safety with locks/isolation

**nonisolated(unsafe) FileManager Usage:**
- Issue: FileManager instances marked `nonisolated(unsafe)` without clear justification
- Files:
  - `Sources/SwiftEAKit/Modules/MailModule/EmlxParser.swift` (line 139)
  - `Sources/SwiftEAKit/Modules/MailModule/EnvelopeIndexDiscovery.swift` (line 58)
- Impact: Potential thread safety issues with shared FileManager instances
- Fix approach: Use local FileManager instances or document why unsafe is necessary

**Legacy Concurrency Primitives:**
- Issue: Mix of old (Thread.sleep, DispatchQueue) and new (async/await) concurrency patterns
- Files:
  - `Sources/SwiftEACLI/Commands/MailCommand.swift` (Thread.sleep on lines 307, 1029, 1140)
  - `Sources/SwiftEACLI/Commands/MailCommandUtilities.swift` (Thread.sleep on line 125)
  - `Sources/SwiftEAKit/Modules/MailModule/AppleScriptService.swift` (usleep on line 255)
- Impact: Inconsistent concurrency model, difficult to reason about, harder to test
- Fix approach: Migrate to Task.sleep and structured concurrency throughout

**FileManager.default Overuse:**
- Issue: 475 occurrences of direct FileManager.default usage across CLI commands
- Files: Throughout `Sources/SwiftEACLI/Commands/` (30+ instances in MailCommand.swift alone)
- Impact: Hard to test (no dependency injection), tight coupling to file system
- Fix approach: Inject FileManager dependencies for testability

**Excessive Console Output in Production Code:**
- Issue: 475 print/fputs statements in Sources/ directory (should use structured logging)
- Files: All CLI command files, especially MailCommand.swift (300+ occurrences)
- Impact: Difficult to control verbosity, no log levels, hard to filter/redirect
- Fix approach: Replace with proper logging framework (e.g., swift-log) with severity levels

## Known Bugs

**Watch Daemon Crash on Empty Working Directory:**
- Symptoms: Daemon mode crashes on launch if current working directory is empty or invalid
- Files: `Sources/SwiftEACLI/Commands/MailCommand.swift` (lines ~256-260)
- Trigger: `swea mail sync --watch` from invalid/deleted directory
- Workaround: Always launch from valid directory
- Fix: Task swiftea-2hz.1 addressed this (per git log)

**Crash on Unknown Search Filter:**
- Symptoms: CLI crashes when user provides unrecognized search filter keyword
- Files: Search query parsing code (exact location TBD - needs investigation)
- Trigger: `swea mail search "unknownfilter:value"`
- Workaround: Use documented filter keywords only
- Fix: Task swiftea-2hz.2 addressed this (per git log)

**Crash on Special Characters in Search Query:**
- Symptoms: Crashes when search query contains certain special characters (likely regex metacharacters)
- Files: Search query parsing code
- Trigger: `swea mail search "text with [brackets] or (parens)"`
- Workaround: Escape special characters or avoid them
- Fix: Task swiftea-2hz.3 addressed this (per git log)

**RFC822 Message-ID Not Stored During Sync:**
- Symptoms: Message-ID header from .emlx files was not persisted to database
- Files: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- Trigger: Any mail sync operation
- Impact: Threading detection may fail, message resolution ambiguous
- Fix: Task swiftea-2hz.4 addressed this (per git log)

**Legacy Client Threading Limitation:**
- Symptoms: Email clients that only set In-Reply-To (no References header) create separate threads instead of joining existing thread
- Files: `Sources/SwiftEAKit/Modules/MailModule/ThreadDetectionService.swift`
- Trigger: Receiving replies from clients that don't follow RFC 5322 References chaining
- Impact: Conversation threads appear fragmented
- Workaround: None - limitation documented in test on line 1181

**Apple Mail Schema Variation Brittleness:**
- Symptoms: Queries may fail if Apple changes Mail.app database schema across versions
- Files: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`, envelope index discovery code
- Trigger: macOS update that changes Mail.app database structure
- Impact: Sync stops working after OS update
- Mitigation: Resilient query patterns added (per git log "fix: make Apple Mail queries resilient to schema variations")

## Security Considerations

**Automation Permission Handling:**
- Risk: AppleScript operations fail silently or with confusing errors if user hasn't granted automation permission
- Files: `Sources/SwiftEAKit/Modules/MailModule/AppleScriptService.swift` (lines 9-87)
- Current mitigation: Clear error messages with remediation guidance in AppleScriptError enum
- Recommendations: Consider adding --check-permissions command to validate before attempting operations

**Environment Variable Exposure:**
- Risk: Working directory and environment paths logged in daemon mode
- Files: `Sources/SwiftEACLI/Commands/MailCommand.swift` (line 259 logs working directory)
- Current mitigation: Only in debug/daemon startup logging
- Recommendations: Sanitize paths in logs, avoid logging sensitive environment state

**LaunchAgent Plist Creation:**
- Risk: LaunchAgent plist file written with user-controlled executable path
- Files: `Sources/SwiftEACLI/Commands/MailCommand.swift` (lines ~641-658)
- Current mitigation: Uses FileManager.default.currentDirectoryPath for executable location
- Recommendations: Validate and canonicalize executable path before writing to plist

**Direct SQLite ATTACH Security:**
- Risk: Future bulk copy implementation (per performance plan) will ATTACH user database files
- Files: Planned for `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- Current mitigation: Not yet implemented
- Recommendations: Validate paths, use read-only mode for source database, handle SQL injection in schema mapping

## Performance Bottlenecks

**Initial Sync Duration (Critical):**
- Problem: 30+ minutes for 124k messages (documented in detail above under Tech Debt)
- Files: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- Cause: Serial processing + 500k+ individual DB ops + no batching + parsing all mailboxes
- Improvement path: See six-task plan in Tech Debt section (60 second target)

**Mail.app Launch Detection Polling:**
- Problem: Uses busy-wait polling loop with usleep to detect Mail.app launch
- Files: `Sources/SwiftEAKit/Modules/MailModule/AppleScriptService.swift` (line 255)
- Cause: No async notification API for app launch events
- Impact: Burns CPU cycles during daemon startup
- Improvement path: Use NSWorkspace notifications or increase poll interval

**Full-Text Search Performance:**
- Problem: Documented issue "FTS stall fix" in git history suggests previous search performance problems
- Files: Likely in `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift` (FTS table implementation)
- Cause: Unknown - was fixed per git log "fix(mail): auto-incremental sync, FTS stall fix"
- Improvement path: Monitor for regression, add performance tests

**Database Lock Contention:**
- Problem: WAL mode enabled to prevent "database is locked" errors during concurrent access
- Files: `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift` (lines 62-68)
- Cause: Daemon and manual sync can run concurrently
- Current mitigation: WAL mode + 5 second busy timeout
- Improvement path: Consider connection pooling or single-writer architecture

## Fragile Areas

**EmlxParser.swift (947 lines, complex MIME parsing):**
- Files: `Sources/SwiftEAKit/Modules/MailModule/EmlxParser.swift`
- Why fragile: Complex multipart MIME parsing, encoding detection, line ending normalization (per git log "fix: EmlxParser line ending detection and multipart parsing bugs")
- Safe modification: Extensive test coverage exists (625 lines in EmlxParserTests.swift), always run tests
- Test coverage: Good - dedicated test file with 625 lines

**MailCommand.swift (3641 lines, massive CLI orchestration):**
- Files: `Sources/SwiftEACLI/Commands/MailCommand.swift`
- Why fragile: Handles sync, search, show, export, actions, daemon mode, LaunchAgent lifecycle - too many responsibilities
- Safe modification: Isolate changes to single subcommand, test in isolation first
- Test coverage: Moderate - 547 lines in MailCommandValidationTests.swift (mostly argument parsing)

**Thread Detection Algorithm:**
- Files:
  - `Sources/SwiftEAKit/Modules/MailModule/ThreadDetectionService.swift` (518 lines)
  - `Sources/SwiftEAKit/Modules/MailModule/ThreadIDGenerator.swift`
  - `Sources/SwiftEAKit/Modules/MailModule/ThreadingHeaderParser.swift`
- Why fragile: Complex RFC 5322 In-Reply-To/References traversal, deterministic ID generation, cross-client compatibility issues
- Safe modification: Document describes algorithm in detail (`docs/mail-migration-guide.md`), extensive test suite (1235 lines in ThreadDetectionServiceTests.swift)
- Test coverage: Excellent - comprehensive test scenarios including legacy client compatibility

**AppleScript Execution and Error Mapping:**
- Files: `Sources/SwiftEAKit/Modules/MailModule/AppleScriptService.swift` (520 lines)
- Why fragile: OS version-specific behavior, permission prompts, Mail.app state dependencies, error code translation
- Safe modification: Test on multiple macOS versions, handle all error codes defensively
- Test coverage: Good - 677 lines in AppleScriptServiceTests.swift with mocking

**Envelope Index Discovery (Apple Mail Database Paths):**
- Files: `Sources/SwiftEAKit/Modules/MailModule/EnvelopeIndexDiscovery.swift`
- Why fragile: Hardcoded paths to Apple Mail database that vary by macOS version (fallback to legacy path on line 196)
- Safe modification: Always test on multiple macOS versions (V10, V11, etc.)
- Test coverage: Moderate - EnvelopeIndexDiscoveryTests.swift exists

**Database Migration System:**
- Files: `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift` (lines 85-96, migration tracking)
- Why fragile: Schema changes must be sequential and idempotent, no rollback mechanism
- Safe modification: Never modify existing migrations, only append new ones, test upgrades from all prior versions
- Test coverage: Good - MailDatabaseTests.swift has 2542 lines

## Scaling Limits

**Single Database File Per Vault:**
- Current capacity: Tested with 124k messages, performs acceptably after optimizations
- Limit: SQLite file size limit (~281 TB) or available disk space, whichever is smaller
- Scaling path: Database sharding by time period (yearly databases) or account-level separation

**In-Memory Thread Cache:**
- Current capacity: Configurable cache size in `Sources/SwiftEAKit/Modules/MailModule/ThreadCache.swift`
- Limit: Available system memory divided by average thread metadata size
- Scaling path: LRU eviction (already implemented), consider persistent cache backed by database

**Mailbox Classification Logic:**
- Current capacity: Works for standard mail providers (Gmail, iCloud, Exchange)
- Limit: Custom mailbox hierarchies or non-English mailbox names may be misclassified
- Scaling path: Add configurable mailbox type rules or regex patterns

**AppleScript Performance:**
- Current capacity: Works for single-user desktop usage
- Limit: AppleScript is inherently slow, not suitable for bulk operations (100+ messages)
- Scaling path: Completed - added bulk backward sync operations (MailSyncBackward.swift) to reduce AppleScript roundtrips

## Dependencies at Risk

**libsql-swift (0.3.0):**
- Risk: Early version (0.x), API may change breaking compatibility
- Impact: Core database functionality would break
- Migration plan: Pin to specific version, monitor releases, test thoroughly before upgrading

**ICalendarKit (1.0.0):**
- Risk: Limited maintenance, last update unknown, calendar functionality dependency
- Impact: Calendar sync and export features would break
- Migration plan: Consider fork if unmaintained, or migrate to alternative iCal parser

**GRDB.swift (7.0.0):**
- Risk: Major version (v7), potential breaking changes in future versions
- Impact: Calendar database access would break
- Migration plan: Well-maintained library, follow upgrade guides, comprehensive test coverage exists

**swift-argument-parser (1.3.0):**
- Risk: Low - stable Apple-maintained library
- Impact: CLI argument parsing would break
- Migration plan: Low priority, framework is stable

## Missing Critical Features

**No Incremental Export:**
- Problem: `swea mail export` always exports all messages, no incremental option
- Blocks: Efficient recurring export workflows for large mailboxes
- Priority: Medium - workaround is filtering with --query flag

**No Attachment Extraction Control:**
- Problem: Attachment extraction is all-or-nothing, no size limits or type filtering
- Blocks: Users with large attachments may fill disk or experience slow exports
- Priority: Medium - documented warning on line 2377: "Warning: Could not extract attachments"

**No Mail.app Event Subscription:**
- Problem: Sync relies on polling or manual triggers, doesn't detect Mail.app changes in real-time
- Blocks: True bidirectional sync with instant updates
- Priority: Low - daemon mode with wake/sleep detection mitigates this

**No Multi-Vault Support for Mail:**
- Problem: Account binding exists but workflow unclear for multiple vaults
- Blocks: Users managing multiple email accounts/personas in separate vaults
- Priority: Low - single vault per account works for most users

## Test Coverage Gaps

**Integration Test for Full Sync Pipeline:**
- What's not tested: End-to-end sync from Apple Mail database through export to Markdown files
- Files: No comprehensive integration test exists
- Risk: Pipeline breakage undetected until manual testing
- Priority: High - critical path

**Calendar Module Backward Sync:**
- What's not tested: Calendar event modifications in vault propagating back to Calendar.app
- Files: No backward sync tests exist for calendar (unlike mail which has MailSyncBackwardTests.swift with 713 lines)
- Risk: Bidirectional calendar sync may be incomplete
- Priority: Medium - depends on whether bidirectional calendar is implemented

**Error Recovery During Parallel Sync:**
- What's not tested: Behavior when parallel workers fail mid-batch (MailSyncParallel.swift)
- Files: `Sources/SwiftEAKit/Modules/MailModule/MailSyncParallel.swift`
- Risk: Partial sync state, data loss, or crash under error conditions
- Priority: High - parallel sync is new and critical for performance

**macOS Version Compatibility:**
- What's not tested: No automated tests for Mail.app database schema variations across macOS versions
- Files: AppleScript and Envelope Index discovery code
- Risk: Breaks silently on OS updates
- Priority: High - user-facing breakage

**LaunchAgent Lifecycle:**
- What's not tested: Install/uninstall/status commands for background daemon
- Files: `Sources/SwiftEACLI/Commands/MailCommand.swift` (lines ~600-800, watch command lifecycle)
- Risk: Broken daemon management, zombie processes
- Priority: Medium - manual testing possible

**Search Query Edge Cases:**
- What's not tested: Complex boolean queries, escaped characters, regex patterns
- Files: Search query parsing and execution code
- Risk: Crashes or incorrect results (recent fixes suggest this was problematic)
- Priority: Medium - recent bug fixes addressed crashes, but edge cases remain

---

*Concerns audit: 2026-01-15*
