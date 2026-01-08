---
title: Create Master App Folder Structure
area: core
status: draft
created: 2026-01-08
processed_date: 2026-01-08
openspec_change_id: add-master-folder-structure-2026-01-08
beads_epic_id: swiftea-btu
decision_summary:
  - Single library target `SwiftEAKit` with CLI in `SwiftEACLI`
  - Module folders named MailModule/CalendarModule/ContactsModule
  - Starter CLI groups: mail, cal, contacts, sync, export
  - TestData directory under Tests
---

## Why

SwiftEA needs a stable, conventional Swift Package Manager layout that matches the modular monolith design (Core + Modules + CLI). A consistent folder structure makes it easier to implement specs, add new modules (calendar/contacts), and keep boundaries clear.

## What

Create the master app folder structure and baseline SwiftPM targets so `swiftea` builds cleanly and the repo is ready for Phase 1 implementation.

Initial shape (high level):
- `Core/` shared infrastructure (db/search/sync/export/config/logging)
- `Modules/` per-source modules (Mail/Calendar/Contacts...)
- `CLI/` command routing + output formatting
- `Tests/` unit tests (core + module logic)

## Scope

In scope:
- SwiftPM package scaffolding (targets, dependencies, executable)
- Directory layout aligned to the master plan
- Minimal “hello world” CLI wiring that proves the structure compiles

Out of scope:
- Implementing mail sync/search/export behaviors (handled by Phase 1 changes/specs)
- Homebrew packaging and CI (can be added later)

## Open Questions

- Do we want a single library target (`SwiftEAKit`) plus per-module targets, or a single monolithic library target with folders for boundaries?
- What naming conventions should we use for modules (`MailModule` vs `Mail`) and targets?
- Should we include a `Fixtures/` or `TestData/` folder early for mail parsing samples?
