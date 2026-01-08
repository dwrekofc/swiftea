# SwiftEA Roadmap

This roadmap summarizes planned work based on `docs/swiftea-architecture-master-plan.md`, current OpenSpec specs (`openspec/specs/`), and proposed OpenSpec changes (`openspec/changes/`).

## Now (Bootstrapping)

1. Create the master app folder structure
   - Create the modular monolith layout described in `docs/swiftea-architecture-master-plan.md` (Core, Modules, CLI, Tests).
   - Ensure Swift Package Manager builds a CLI binary (`swiftea`) and internal modules compile behind clear boundaries.
   - Idea: `docs/ideas/2026-01-08-create-master-app-folder-structure.md`

## Phase 1 — Foundation (Mail + Core)

**Goal**: `swiftea mail` is end-to-end usable (sync/search/export + basic actions) with a stable core foundation.

### Vault Bootstrap
- `swiftea init --vault <path>` creates vault-local config + folder layout and binds accounts per-vault (vault-scoped model).
- Idea: `docs/ideas/2026-01-08-add-vault-scoped-account-binding.md`

### Core (Shared Infrastructure)
- Database layer (libSQL/SQLite), baseline schema, migrations
- Sync engine (manual + periodic; watch where applicable)
- Export system (markdown/JSON)
- CLI infrastructure (command routing, output formatting, config)
- Testing harness (unit + targeted integration tests)
- Packaging/installation (Homebrew formula; from-source build)
- Security & privacy defaults (permission checks, local-first behavior)

### Mail Module (Capabilities)
- Read/search/export/watch foundation
  - OpenSpec change: `openspec/changes/add-mail-read-export/proposal.md`
  - Capability spec (truth): `openspec/specs/mail/spec.md`
- Threading support
  - OpenSpec change: `openspec/changes/add-threading/proposal.md`
- Apple Mail actions via AppleScript
  - OpenSpec change: `openspec/changes/add-mail-actions-applescript/proposal.md`

### Deliverable checkpoints
- `swiftea mail sync` builds and incrementally updates a local mirror
- `swiftea mail search` returns results quickly with stable IDs
- `swiftea mail export` writes Obsidian-friendly markdown/JSON
- `swiftea mail archive/delete/move/flag` works safely and predictably

## Phase 2 — Calendar & Contacts

**Goal**: add core PIM context beyond mail.

- Calendar module (read/search/export; later create/update/delete)
- Contacts module (read/search/export; later create/update/delete)
- Cross-module linking (emails ↔ events ↔ contacts)
- Unified search improvements (cross-module ranking, facets)

## Phase 3 — Advanced Features

**Goal**: project/context workflows and performance hardening.

- Context assembly (project-based context gathering, timeline view)
- Advanced metadata (ad-hoc fields, bulk ops, templates)
- Performance optimization (caching, parallelism where safe)
- More real-time sync (FSEvents watchers; resilience)

## Phase 4 — AI & Semantic Features

**Goal**: semantic search + AI-enriched metadata while staying local-first.

- Semantic search (vector embeddings / sqlite extensions)
- AI summaries/insights pipelines (opt-in; local-first by default)
- Automatic linking improvements (meeting/email/contact relationship inference)

## Phase 5+ — Future Vision

- Tasks module (Reminders vs markdown vs hybrid)
- Notes module (Apple Notes vs markdown vault vs hybrid)
- Obsidian plugin UI integration (threaded mail triage, action delegation)

## Proposed Changes (Parked / Future Candidates)

These are proposal candidates extracted from the master plan for later OpenSpec work:

- `add-calendar-module-foundation`
- `add-contacts-module-foundation`
- `add-core-metadata-and-links`
- `add-unified-search-query`
- `add-context-assembly`
