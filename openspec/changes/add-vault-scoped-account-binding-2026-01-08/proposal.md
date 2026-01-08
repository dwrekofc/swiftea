# Change: Vault-scoped account binding and vault-local storage

Beads: swiftea-294

## Why
SwiftEA needs to be portable and vault-first so a single Obsidian vault can be synced, moved, or shared with all replicated data and derived artifacts kept inside the vault.

## What Changes
- Introduce vault-scoped configuration stored at `<vault>/.swiftea/config.json`.
- Add `swiftea vault init --path <vault>` to initialize vault config, folder layout, and vault-local database.
- Bind mail and calendar accounts per vault using a multi-select prompt from macOS Internet Accounts (no new logins).
- Enforce one-vault-per-account using a minimal global registry at `~/.config/swiftea/account-bindings.json`.
- Require vault context for data-affecting commands; allow `help`, `version`, and `vault init` without a vault.
- Standardize vault layout under `<vault>/Swiftea/{mail,calendar,contacts,metadata,attachments,logs}`.

## Impact
- Affected capabilities: new `vaults` capability (vault configuration, binding, and layout).
- Affected modules: core CLI command routing; mail and calendar sync/export paths.
- Affected data model: vault-local libSQL database at `<vault>/.swiftea/swiftea.db`.

## Decisions (from interview)
- Vault config lives in `.swiftea/` at the vault root.
- Accounts are selected via multi-select prompt from existing macOS Internet Accounts; no login flow.
- Vault-local database is required (no export-only mode in v1).
- Layout uses `Swiftea/{mail,calendar,contacts,metadata,attachments,logs}`.
- The same account cannot be bound to multiple vaults.
- Vault commands require CWD at the vault root (no upward search for `.swiftea/`).
