## Context
SwiftEA needs a vault-first model where configuration, database state, and exported artifacts live inside the vault to keep the vault portable and syncable. This change introduces a vault-scoped configuration, account binding per vault, and a minimal global registry to enforce one-vault-per-account.

## Goals / Non-Goals
- Goals:
  - Vault-local config and DB inside the vault root.
  - Per-vault account binding for mail and calendar.
  - Deterministic, canonical folder layout for replicated artifacts.
  - Clear command gating and explicit error guidance when no vault context exists.
- Non-Goals:
  - Cross-vault federation or search.
  - Multi-user permissions beyond the underlying sync tool.
  - Account login flows or adding new accounts.

## Decisions
- **Vault config location**: `<vault>/.swiftea/config.json`.
- **Vault-local DB**: `<vault>/.swiftea/swiftea.db`.
- **Folder layout**: `<vault>/Swiftea/{mail,calendar,contacts,metadata,attachments,logs}`.
- **Account selection**: multi-select prompt sourced from macOS Internet Accounts; no login or account creation flow.
- **Account binding enforcement**: global registry at `~/.config/swiftea/account-bindings.json` mapping account IDs to vault paths.
- **Vault resolution**: require `.swiftea/` in CWD (no upward search).

## Risks / Trade-offs
- Global registry introduces minimal hidden state; mitigated by keeping only account→vault mappings.
- Requiring CWD at vault root reduces convenience; mitigated by clear error messages and explicit `vault init` guidance.
- Disallowing multi-vault bindings limits flexibility but prevents unintended side effects.

## Migration Plan
- New installs use `swiftea vault init --path <vault>`.
- Existing configurations (if any) require a one-time migration to a vault; out of scope for v1.

## Open Questions
- None for v1; future changes may introduce vault discovery or multi-vault support.
