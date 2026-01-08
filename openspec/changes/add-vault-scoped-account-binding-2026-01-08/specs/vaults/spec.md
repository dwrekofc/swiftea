## ADDED Requirements

### Requirement: Vault Initialization
The system SHALL provide `swiftea vault init --path <vault>` to initialize a vault-scoped configuration, vault-local database, and standard folder layout.

#### Scenario: Initialize a new vault
- **WHEN** the user runs `swiftea vault init --path /path/to/vault`
- **THEN** the system SHALL create `/path/to/vault/.swiftea/`
- **AND** SHALL write `/path/to/vault/.swiftea/config.json`
- **AND** SHALL create `/path/to/vault/.swiftea/swiftea.db`
- **AND** SHALL create `/path/to/vault/Swiftea/{mail,calendar,contacts,metadata,attachments,logs}`

### Requirement: Vault Config Location
The vault configuration SHALL be stored at `<vault>/.swiftea/config.json` and MUST be the source of truth for vault-scoped settings.

#### Scenario: Config file is present
- **WHEN** a vault is initialized
- **THEN** the config MUST exist at `<vault>/.swiftea/config.json`

### Requirement: Vault-Local Database
All replicated data and metadata SHALL be stored in a vault-local libSQL database at `<vault>/.swiftea/swiftea.db`.

#### Scenario: Mail sync uses vault-local DB
- **WHEN** the user runs `swiftea mail sync` from a vault
- **THEN** the system SHALL read and write mirror data in `<vault>/.swiftea/swiftea.db`

### Requirement: Account Binding Selection
During vault initialization, the system SHALL list available Mail and Calendar accounts from macOS Internet Accounts and SHALL prompt for multi-select binding. The system SHALL NOT offer to log into new accounts.

#### Scenario: User selects accounts
- **WHEN** the user initializes a vault
- **THEN** the system SHALL prompt for account selection
- **AND** SHALL persist the selected account IDs in the vault config

### Requirement: Single-Vault Account Binding
An account MUST NOT be bound to more than one vault. The system SHALL enforce this using a global registry at `~/.config/swiftea/account-bindings.json`.

#### Scenario: Account already bound
- **WHEN** the user attempts to bind an account already registered to another vault
- **THEN** the system SHALL block the selection
- **AND** SHALL return an actionable error indicating the existing vault path

### Requirement: Vault-Scoped Command Gating
Data-affecting commands (search/export/sync/link/meta) SHALL require a vault context. `swiftea help`, `swiftea version`, and `swiftea vault init` SHALL work without a vault.

#### Scenario: Command run outside a vault
- **WHEN** the user runs `swiftea mail search "budget"` outside a vault
- **THEN** the system SHALL return an error
- **AND** SHALL provide guidance to run `swiftea vault init --path <vault>`

### Requirement: Vault Context Resolution
Vault context SHALL be determined only by the current working directory containing `.swiftea/`. The system SHALL NOT walk parent directories to locate a vault.

#### Scenario: Running from a subdirectory
- **WHEN** the user runs a data-affecting command from a subdirectory inside a vault
- **AND** the CWD does not contain `.swiftea/`
- **THEN** the system SHALL return a "no vault" error

### Requirement: Canonical Vault Layout
The system SHALL standardize replicated artifacts under `<vault>/Swiftea/` with module-specific subfolders.

#### Scenario: Layout created at init
- **WHEN** the user initializes a vault
- **THEN** the system SHALL create `<vault>/Swiftea/mail`
- **AND** SHALL create `<vault>/Swiftea/calendar`
- **AND** SHALL create `<vault>/Swiftea/contacts`
- **AND** SHALL create `<vault>/Swiftea/metadata`
- **AND** SHALL create `<vault>/Swiftea/attachments`
- **AND** SHALL create `<vault>/Swiftea/logs`
