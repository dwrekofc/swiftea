## 1. Vault configuration and layout
- [ ] 1.1 Add vault init command `swiftea vault init --path <vault>`
- [ ] 1.2 Write vault config to `<vault>/.swiftea/config.json`
- [ ] 1.3 Create vault-local DB at `<vault>/.swiftea/swiftea.db`
- [ ] 1.4 Create canonical folder layout under `<vault>/Swiftea/`

## 2. Account binding
- [ ] 2.1 Read available Mail and Calendar accounts from macOS Internet Accounts
- [ ] 2.2 Prompt user with multi-select; persist selected account IDs in vault config
- [ ] 2.3 Implement global binding registry at `~/.config/swiftea/account-bindings.json`
- [ ] 2.4 Prevent binding an account already registered to another vault

## 3. Vault resolution and command gating
- [ ] 3.1 Require `.swiftea/` in CWD for data-affecting commands
- [ ] 3.2 Return actionable error when no vault is present
- [ ] 3.3 Allow `help`, `version`, and `vault init` without a vault

## 4. Integration updates
- [ ] 4.1 Route mail/calendar sync/export to the vault-local DB and vault layout
- [ ] 4.2 Update docs/help text with vault usage examples
- [ ] 4.3 Add tests for vault init, registry enforcement, and command gating
