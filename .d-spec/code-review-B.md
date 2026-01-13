# SwiftEA Critical Code & Architecture Review (Comprehensive)

**Scope & Context Sources**
- `.d-spec/project.md` (project purpose, tech stack, architecture claims)
- `.d-spec/planning/changes/add-calendar-module-foundation-2026-01-09/proposal.md` (calendar foundation proposal, status draft dated 2026-01-09)
- `.d-spec/planning/changes/add-calendar-module-foundation-2026-01-09/specs/calendar/spec.md` (calendar capability spec)
- Codebase scan under `Sources/SwiftEA`, `Sources/SwiftEACLI`, and `Sources/SwiftEAKit`

**Inferred Objective / Status / Happy Path**
- Objective: SwiftEA is a unified CLI for macOS PIM data (mail, calendar, contacts, etc.) and a data layer for ClaudEA.
- Tech stack: Swift 6, Swift Argument Parser, libSQL, Foundation, OSAKit (per `.d-spec/project.md`).
- Current status: Calendar foundation proposal is **draft** (January 9, 2026). Calendar commands exist but are stubbed. Contacts and global sync/search/export/status also stubbed.
- Happy path (per specs): `swiftea cal sync` builds mirror DB; search/list/show/export and watch mode work; ClaudEA consumes stable IDs and JSON outputs.

---

## Critical (Must Fix)

### SQL safety and correctness
- SQL is built via string interpolation in multiple places, including user input (`search` queries). Escaping single quotes is not sufficient for FTS syntax and can yield incorrect or unsafe queries. This is brittle and can cause crashes or incorrect results.
  - Files: `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`, `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- `getAllMessages` query selects columns that do **not exist** in the schema (`recipients`, `created_at`). This will fail at runtime.
  - File: `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
- Deleted mail is not excluded from search; `searchMessages` lacks `is_deleted = 0` filtering. Deleted data will still be returned.
  - File: `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
- `markMessageDeleted` updates `messages`, but FTS is not updated for deletes, so stale results persist in FTS index.
  - File: `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`

### CLI surface mismatches and misleading commands
- Top-level CLI (`main.swift`) exposes calendar, contacts, search, sync, export, status, etc., but many are placeholder stubs. User-facing CLI implies functionality that does not exist.
  - Files: `Sources/SwiftEA/main.swift`, `Sources/SwiftEACLI/Commands/CalendarCommand.swift`, `Sources/SwiftEACLI/Commands/ContactsCommand.swift`, `Sources/SwiftEACLI/Commands/SearchCommand.swift`, `Sources/SwiftEACLI/Commands/SyncCommand.swift`, `Sources/SwiftEACLI/Commands/ExportCommand.swift`, `Sources/SwiftEACLI/Commands/StatusCommand.swift`
- Mail action commands (archive/delete/move/flag/mark/reply/compose) are exposed but stubbed (AppleScript not implemented) while presenting as real actions.
  - File: `Sources/SwiftEACLI/Commands/MailCommand.swift`

### Stable ID contract violations
- “Stable IDs” are not stable: fallback ID generation uses `rowid` as a component, which can change across Apple Mail DB rebuilds or migrations. This violates the stability contract described in planning docs.
  - File: `Sources/SwiftEAKit/Modules/MailModule/StableIdGenerator.swift`
- No collision handling for stable IDs. Collisions can silently overwrite data (e.g., identical subject/sender/date combos).
  - File: `Sources/SwiftEAKit/Modules/MailModule/StableIdGenerator.swift`

### Documentation vs implementation gaps
- Calendar docs/specs describe a robust module with `show/list/calendars/watch/ics` and full mirror DB, but code only includes stub `sync/search/export` commands with no implementation.
  - Files: `.d-spec/planning/changes/add-calendar-module-foundation-2026-01-09/specs/calendar/spec.md` vs `Sources/SwiftEACLI/Commands/CalendarCommand.swift`
- Project doc claims `SwiftEAModule` protocol and modular monolith boundaries, but no such protocol exists.
  - Files: `.d-spec/project.md` vs codebase search for `SwiftEAModule`

---

## Optimization

### Mail sync performance
- `detectStatusChanges` builds a list of existing messages and then scans linearly for each row (`first(where:)`) → O(n²) for large mailboxes.
  - File: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- `processMessage` queries mailboxes table twice per message for name/path, causing repeated I/O. No caching or prefetching.
  - File: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- Full sync upserts per message without wrapping in a transaction.
  - Files: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`, `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
- FTS index is maintained via triggers, but no rebuild/optimize step after large sync. Potential index bloat and degraded search performance.
  - File: `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`

### Mail export and show
- `MailShowCommand` HTML stripping is regex-based and can be slow or incorrect for large/complex HTML. No size limits or streaming.
  - File: `Sources/SwiftEACLI/Commands/MailCommand.swift`
- `MailSearchCommand` outputs JSON with `dateSent?.description` (non-ISO, locale-dependent).
  - File: `Sources/SwiftEACLI/Commands/MailCommand.swift`
- YAML frontmatter escaping only handles quotes; special characters (colon, newline) can invalidate YAML.
  - File: `Sources/SwiftEACLI/Commands/MailCommand.swift`

### Account discovery / binding
- Account discovery result parsing uses comma-separated strings; account names containing commas break parsing.
  - File: `Sources/SwiftEAKit/Core/AccountDiscovery.swift`

---

## Refactoring

### Layering / architecture
- `MailDatabase` mixes schema creation, data access, and sync status bookkeeping; it acts as a god object.
  - File: `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
- Mail commands directly access the database rather than going through a module interface. This violates the documented modular monolith boundary.
  - File: `Sources/SwiftEACLI/Commands/MailCommand.swift`
- Raw SQLite access in sync (`sqlite3`) and libSQL in mirror coexist without a clear abstraction boundary.
  - File: `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- Duplicate helper logic exists in CLI (e.g., `stripHtml`, `formatSender`) across commands.
  - File: `Sources/SwiftEACLI/Commands/MailCommand.swift`

### Vault & registry design
- `VaultManager` mixes filesystem layout, config encoding, and db file creation in one type.
  - File: `Sources/SwiftEAKit/Core/VaultManager.swift`
- Binding registry path uses Linux-style `~/.config/swiftea` rather than macOS `~/Library/Application Support`, despite macOS-only scope.
  - File: `Sources/SwiftEAKit/Core/BindingRegistry.swift`

---

## What-If Scenarios / Edge Cases Ignored

### Mail sync / data integrity
1. Apple Mail DB schema drift breaks sync queries with no version detection or fallbacks.
2. FTS query syntax: user queries with `-`, quotes, or special characters can break FTS because the query is interpolated directly.
3. Stable ID collisions from identical subject/sender/date lead to silent overwrites.
4. Apple Mail DB rebuild changes `rowid`, invalidating “stable” IDs that incorporate rowid.
5. Mailbox moves vs deletions are indistinguishable in current soft-delete logic (`is_deleted`).
6. Full `.emlx` parsing with unknown encoding yields empty or corrupted output for non-UTF-8 messages.

### CLI / UX behavior
1. Running commands from a subdirectory of a vault fails; error message says “not supported,” likely for most users.
2. Stubs exposed as real commands yield misleading outcomes.

### Account binding
1. Concurrent `swiftea vault bind` can race and corrupt binding registry.
2. AppleScript permission failure returns “no accounts” rather than permission error, obscuring the real problem.
3. Account names with commas break parsing and binding.

---

## Documentation Audit (Mismatches and Gaps)

- Calendar spec is written as if implemented; code is stubbed. Planning docs do not clearly label this as future work.
- Project doc claims `SwiftEAModule` protocol and modular architecture but this is not present in code.
- Calendar proposal lists `cal show/list/calendars/watch/ics` while CLI only exposes `sync/search/export` and stubs.
- Mail action interface is surfaced despite no implementation, which conflicts with a “documentation-first” claim.

---

## Additional Findings (Mail CLI + Actions)

- `MailSearchCommand` never closes the database connection (potential file handle leak in repeated runs).
  - File: `Sources/SwiftEACLI/Commands/MailCommand.swift`
- `MailExportCommand` writes files unconditionally into `exports/mail` (no safe-guarding or dry-run by default). This is a risk for sensitive data.
  - File: `Sources/SwiftEACLI/Commands/MailCommand.swift`
- `MailShowCommand` raw `.emlx` output assumes UTF-8 and fails silently on other encodings.
  - File: `Sources/SwiftEACLI/Commands/MailCommand.swift`
- Multiple commands print “not yet implemented” but still proceed as if they executed a real action.
  - File: `Sources/SwiftEACLI/Commands/MailCommand.swift`

---

## Stable ID Implementation Notes (Mail)

- Uses `messageId` when present; otherwise hashes `subject + sender + date + rowid`. This is not stable across DB rebuilds, mailbox moves, or different machines.
- Hash prefix truncated to 128 bits; not inherently an issue, but the input instability is the primary concern.
- No tracking of which strategy was used (msgid vs fallback) and no storage of raw inputs to reconcile or audit.
  - File: `Sources/SwiftEAKit/Modules/MailModule/StableIdGenerator.swift`

---

## Files Referenced
- `Sources/SwiftEA/main.swift`
- `Sources/SwiftEACLI/Commands/MailCommand.swift`
- `Sources/SwiftEACLI/Commands/CalendarCommand.swift`
- `Sources/SwiftEACLI/Commands/ContactsCommand.swift`
- `Sources/SwiftEACLI/Commands/SearchCommand.swift`
- `Sources/SwiftEACLI/Commands/SyncCommand.swift`
- `Sources/SwiftEACLI/Commands/ExportCommand.swift`
- `Sources/SwiftEACLI/Commands/StatusCommand.swift`
- `Sources/SwiftEAKit/Modules/MailModule/MailDatabase.swift`
- `Sources/SwiftEAKit/Modules/MailModule/MailSync.swift`
- `Sources/SwiftEAKit/Modules/MailModule/StableIdGenerator.swift`
- `Sources/SwiftEAKit/Core/VaultManager.swift`
- `Sources/SwiftEAKit/Core/VaultContext.swift`
- `Sources/SwiftEAKit/Core/AccountDiscovery.swift`
- `Sources/SwiftEAKit/Core/BindingRegistry.swift`
- `.d-spec/project.md`
- `.d-spec/planning/changes/add-calendar-module-foundation-2026-01-09/proposal.md`
- `.d-spec/planning/changes/add-calendar-module-foundation-2026-01-09/specs/calendar/spec.md`
