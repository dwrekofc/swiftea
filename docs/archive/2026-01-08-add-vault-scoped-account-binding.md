---
title: Vault-Scoped Account Binding & Sync Model
area: core
status: draft
created: 2026-01-08
processed_date: 2026-01-08
openspec_change_id: add-vault-scoped-account-binding-2026-01-08
beads_epic_id: swiftea-294
decision_summary:
  - Vault config in <vault>/.swiftea/ with vault-local DB
  - Account selection via multi-select from existing Internet Accounts
  - One-vault-per-account enforced via global registry
  - Data commands require CWD at vault root; no upward search
  - Canonical layout under <vault>/Swiftea/
---

## Why

SwiftEA is most useful when its replicated data and derived artifacts (exports, indexes, metadata) live inside an Obsidian vault so the vault remains portable, syncable, and collaborative using standard file-based workflows.

## What

Define SwiftEA as **vault-scoped**:
- Each vault can define its **own set of connected accounts** (mail + calendar, and later other modules).
- Within a vault, the user can:
  - Select specific email accounts to watch/manage
  - Select specific calendar accounts to watch/manage
  - Replicate emails, events, and derived artifacts into the vault’s folder structure

Example configurations:
- Personal vault → personal email + personal calendar
- Work vault → work email + work calendar
- Combined vault → selected accounts from both, merged intentionally

Operational model:
- All replicated data lives inside the vault directory.
- The vault is just a folder on disk.
- No hidden global state is required beyond the vault itself.

Resulting properties:
- The entire system can be:
  - Synced as a single folder
  - Copied or moved across machines
  - Published (e.g., GitHub)
  - Opened in any markdown-compatible notes app
  - Collaborated on via standard file-based workflows

Core principle:
- One vault = one coherent executive context
- The vault is the unit of sync, portability, and collaboration

## Scope

In scope:
- Vault selection and configuration model (how SwiftEA targets a vault)
- Account binding per vault (mail + calendar initially)
- Vault-local storage layout for replicated data and derived artifacts

Out of scope (for first iteration):
- Cross-vault federation/queries
- Multi-user permissioning beyond what the underlying sync/collab tool provides

## Open Questions

- Where does vault configuration live (e.g., `.swiftea/` folder in the vault vs a user-chosen path inside the vault)?
- How should account selection be expressed (explicit allowlist, patterns, UI prompts)?
- How are conflicts handled when the same account is bound to multiple vaults (read-only allowed, but action side effects)?
- Do we require vault-local DB state (e.g., libSQL file in-vault) or “export-only” mode for some vaults?
- What is the canonical folder layout inside a vault (emails/events/contacts/derived summaries/attachments)?
