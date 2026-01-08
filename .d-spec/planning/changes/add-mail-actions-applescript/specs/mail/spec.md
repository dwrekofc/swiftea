## ADDED Requirements

### Requirement: Automation Permission
The mail module SHALL perform write actions (archive/delete/move/flag/reply/send) via Mail.app automation and SHALL require macOS Automation permission for controlling Mail.app. When permission is missing, the system SHALL fail with actionable guidance.

#### Scenario: Missing Automation permission
- **WHEN** the user runs `swiftea mail archive --id <id>`
- **AND** SwiftEA is not permitted to control Mail.app
- **THEN** the system SHALL return an error indicating Automation permission is required
- **AND** SHALL provide steps to grant the permission in macOS System Settings

### Requirement: Mail Action Commands
The CLI SHALL provide mail action commands that operate on a selected message:
- `swiftea mail archive --id <id>`
- `swiftea mail delete --id <id>`
- `swiftea mail move --id <id> --mailbox <name>`
- `swiftea mail flag --id <id> [--set|--clear]`
- `swiftea mail mark --id <id> --read|--unread`

#### Scenario: Archive a message
- **WHEN** the user runs `swiftea mail archive --id <id> --yes`
- **THEN** the system SHALL archive the target message in Mail.app
- **AND** SHALL return a success result that includes the message id

#### Scenario: Move to mailbox
- **WHEN** the user runs `swiftea mail move --id <id> --mailbox "INBOX/Receipts" --yes`
- **THEN** the system SHALL move the target message to the specified mailbox in Mail.app
- **AND** SHALL return an error if the mailbox does not exist

### Requirement: Drafting and Sending
The CLI SHALL support creating outbound mail content via Mail.app automation:
- `swiftea mail reply --id <id> --body <text> [--send]`
- `swiftea mail compose --to <email> --subject <text> --body <text> [--send]`

If `--send` is not provided, the system SHALL create a draft rather than sending.

#### Scenario: Reply draft
- **WHEN** the user runs `swiftea mail reply --id <id> --body "Thanks, will do."`
- **THEN** the system SHALL create a draft reply in Mail.app
- **AND** SHALL return a success result that includes the draft reference

#### Scenario: Send compose
- **WHEN** the user runs `swiftea mail compose --to bob@example.com --subject "Update" --body "..." --send`
- **THEN** the system SHALL send the message via Mail.app
- **AND** SHALL return a success result that includes the sent message reference when available

### Requirement: Safe Defaults for Destructive Actions
Destructive actions (`archive`, `delete`, `move`) SHALL require explicit confirmation via `--yes` unless `--dry-run` is provided.

#### Scenario: Missing confirmation
- **WHEN** the user runs `swiftea mail delete --id <id>`
- **THEN** the system SHALL refuse to execute
- **AND** SHALL instruct the user to pass `--yes` or `--dry-run`

### Requirement: Dry Run Mode
All mail actions SHALL support `--dry-run` to show what would happen without performing automation.

#### Scenario: Dry run archive
- **WHEN** the user runs `swiftea mail archive --id <id> --dry-run`
- **THEN** the system SHALL not modify Mail.app state
- **AND** SHALL print a description of the intended action and target message

### Requirement: Message Resolution
For any action command that accepts `--id <id>`, the system SHALL resolve the SwiftEA email id to exactly one Mail.app message before executing. If resolution fails or is ambiguous, the system SHALL fail without performing the action.

#### Scenario: Message not found
- **WHEN** the user runs `swiftea mail archive --id <id> --yes`
- **AND** the message cannot be resolved in Mail.app
- **THEN** the system SHALL return a not-found error
- **AND** SHALL suggest running `swiftea mail sync` to refresh the mirror

#### Scenario: Message resolution ambiguous
- **WHEN** the user runs `swiftea mail archive --id <id> --yes`
- **AND** multiple Mail.app messages match the resolved identifiers
- **THEN** the system SHALL return an ambiguity error
- **AND** SHALL instruct the user to refine selection (e.g., use a query or a message-id)
