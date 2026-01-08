## 1. Mail Mirror Schema
- [ ] 1.1 Define libSQL tables for mail mirror, headers, body, attachments, and export paths
- [ ] 1.2 Add indexes for lookup by stable ID, rowid, message-id, and mailbox
- [ ] 1.3 Add FTS5 index for subject/from/to/body_text
- [ ] 1.4 Add migration/init routines for first-run setup

## 2. Source Mapping & Sync
- [ ] 2.1 Implement Apple Mail DB discovery (auto-detect V[x] and Envelope Index path)
- [ ] 2.2 Implement query-and-rebuild sync from Apple SQLite to libSQL
- [ ] 2.3 Parse .emlx files for headers, plain text, HTML, and attachment metadata
- [ ] 2.4 Implement incremental sync (changed messages only)
- [ ] 2.5 Track sync status and last sync time

## 3. Watch Mode (launchd)
- [ ] 3.1 Implement `swiftea mail sync --watch` to install/start a LaunchAgent
- [ ] 3.2 Implement resilient watch loop with debounce and backoff
- [ ] 3.3 On start, run incremental sync before watching
- [ ] 3.4 On sleep/wake, run incremental catch-up
- [ ] 3.5 Provide `swiftea mail sync --status` for watch state

## 4. Stable ID Strategy
- [ ] 4.1 Implement stable hash ID generation (Message-ID preferred, fallback to header digest)
- [ ] 4.2 Store rowid and message-id for reverse lookup
- [ ] 4.3 Ensure exported IDs are stable across re-syncs

## 5. Search & Query
- [ ] 5.1 Implement mail search using FTS across subject/from/to/body_text
- [ ] 5.2 Implement structured query filters (from/to/subject/date/mailbox/read/flagged)
- [ ] 5.3 Implement JSON envelope output for search/query/get

## 6. Export
- [ ] 6.1 Implement markdown export with minimal frontmatter and aliases
- [ ] 6.2 Implement JSON export for single and batch items
- [ ] 6.3 Implement flat-folder export naming with ID-based filenames
- [ ] 6.4 Track export file paths in libSQL and overwrite on re-export
- [ ] 6.5 Implement optional attachment extraction via `--include-attachments`

## 7. Configuration
- [ ] 7.1 Add config keys for mail path overrides, export defaults, and watch settings
- [ ] 7.2 Implement `swiftea config` read/write for mail settings

## 8. Tests & Documentation
- [ ] 8.1 Unit tests for .emlx parsing and ID generation
- [ ] 8.2 Integration tests for sync + search + export
- [ ] 8.3 Document CLI usage and Phase 1 scope
