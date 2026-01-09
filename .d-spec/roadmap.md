---
type: roadmap
master_plan: swiftea-architecture-master-plan.md
last_updated: 2026-01-09
---

# SwiftEA Roadmap

This roadmap summarizes planned work based on:
- **Master Plan**: `.d-spec/swiftea-architecture-master-plan.md`
- **Upstream Context**: `.d-spec/claudea-swiftea-ecosystem-master-plan.md`
- **Specs**: `.d-spec/planning/specs/`
- **Changes**: `.d-spec/planning/changes/`

## SwiftEA Goals Reference

| Goal | Type | Description |
|------|------|-------------|
| SG-1 | Core | Unified PIM Access |
| SG-2 | Core | Cross-Module Intelligence |
| SG-3 | Core | Data Liberation |
| SG-4 | Supporting | ClaudEA-Ready Output |
| SG-5 | Supporting | Local-First Architecture |
| SG-6 | Supporting | Modular Extensibility |

---

## Now (Bootstrapping)

1. Create the master app folder structure
   - Create the modular monolith layout described in `.d-spec/swiftea-architecture-master-plan.md` (Core, Modules, CLI, Tests).
   - Ensure Swift Package Manager builds a CLI binary (`swiftea`) and internal modules compile behind clear boundaries.
   - Spec: `.d-spec/planning/specs/project-structure/spec.md`
   - Beads: swiftea-btu

## Phase 1 — Foundation (Mail + Core)

**Goals**: SG-1 (Unified PIM Access), SG-3 (Data Liberation), SG-5 (Local-First Architecture)

**Goal**: `swiftea mail` is end-to-end usable (sync/search/export + basic actions) with a stable core foundation.

### Vault Bootstrap
- `swiftea init --vault <path>` creates vault-local config + folder layout and binds accounts per-vault (vault-scoped model).
- Spec: `.d-spec/planning/specs/vaults/spec.md`
- Beads: swiftea-294

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
  - Change: `.d-spec/planning/changes/add-mail-read-export/proposal.md`
  - Spec: `.d-spec/planning/specs/mail/spec.md`
  - Beads: swiftea-7im
- Threading support
  - Change: `.d-spec/planning/changes/add-threading/proposal.md`
  - Spec: `.d-spec/planning/specs/mail/spec.md`
  - Beads: swiftea-az6
- Apple Mail actions via AppleScript
  - Change: `.d-spec/planning/changes/add-mail-actions-applescript/proposal.md`
  - Spec: `.d-spec/planning/specs/mail/spec.md`
  - Beads: swiftea-01t

### Deliverable checkpoints
- `swiftea mail sync` builds and incrementally updates a local mirror
- `swiftea mail search` returns results quickly with stable IDs
- `swiftea mail export` writes Obsidian-friendly markdown/JSON
- `swiftea mail archive/delete/move/flag` works safely and predictably

## Phase 2 — Calendar & Unified Search

**Goals**: SG-1 (Unified PIM Access), SG-2 (Cross-Module Intelligence), SG-6 (Modular Extensibility)

**Goal**: add core PIM context beyond mail.

- Calendar module (read/search/export; later create/update/delete)
- Contacts module (read/search/export; later create/update/delete)
- Cross-module linking (emails ↔ events ↔ contacts)
- Unified search improvements (cross-module ranking, facets)

## Phase 3 — Reminders & Advanced Search

**Goals**: SG-1 (Unified PIM Access), SG-2 (Cross-Module Intelligence), SG-4 (ClaudEA-Ready Output)

**Goal**: Complete PIM coverage and enable ClaudEA workflows.

- Reminders module (read/search/export; later create/update/delete)
- Context assembly (project-based context gathering, timeline view)
- Advanced metadata (ad-hoc fields, bulk ops, templates)
- JSON output for all commands (ClaudEA integration)

## Phase 4 — Performance & Reliability

**Goals**: SG-5 (Local-First Architecture), SG-6 (Modular Extensibility)

**Goal**: project/context workflows and performance hardening.

- Performance optimization (caching, parallelism where safe)
- More real-time sync (FSEvents watchers; resilience)
- Large dataset handling (100k+ items)
- Error recovery and resilience

## Phase 5 — AI & Semantic Features

**Goals**: SG-2 (Cross-Module Intelligence), SG-4 (ClaudEA-Ready Output)

**Goal**: semantic search + AI-enriched metadata while staying local-first.

- Semantic search (vector embeddings / sqlite extensions)
- AI summaries/insights pipelines (opt-in; local-first by default)
- Automatic linking improvements (meeting/email/contact relationship inference)

## Phase 6+ — Polish & OSS Release

**Goals**: SG-3 (Data Liberation), SG-6 (Modular Extensibility)

- Notes module (Apple Notes integration)
- Documentation and guides
- Installation packaging (Homebrew)
- Community feedback and refinement
- Plugin/extension system (maybe)

## Proposed Changes (Parked / Future Candidates)

These are proposal candidates extracted from the master plan for later d-spec work:

- `add-calendar-module-foundation`
- `add-contacts-module-foundation`
- `add-reminders-module-foundation`
- `add-core-metadata-and-links`
- `add-unified-search-query`
- `add-context-assembly`
