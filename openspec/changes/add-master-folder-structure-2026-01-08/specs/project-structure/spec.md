## ADDED Requirements
### Requirement: SwiftPM package scaffold
The system SHALL define a Swift Package Manager package named `SwiftEA` that produces a globally executable `swiftea` binary.

#### Scenario: Build produces executable
- **WHEN** a developer runs `swift build`
- **THEN** the build output includes an executable named `swiftea`

### Requirement: Source layout for modular monolith
The system SHALL create a library target `SwiftEAKit` with source folders `Core/` and `Modules/`, and an executable target `SwiftEACLI` with `Commands/` and `Output/` subfolders.

#### Scenario: Folder layout exists
- **WHEN** a developer inspects the repository structure
- **THEN** the required folder layout exists under `Sources/`

### Requirement: Module folder conventions
The system SHALL include module folders `MailModule/`, `CalendarModule/`, and `ContactsModule/` under `Sources/SwiftEAKit/Modules/`.

#### Scenario: Module directories present
- **WHEN** a developer lists module folders
- **THEN** the three module directories are present

### Requirement: CLI parser dependency
The system SHALL use `swift-argument-parser` for the CLI command structure.

#### Scenario: Package declares dependency
- **WHEN** a developer inspects `Package.swift`
- **THEN** `swift-argument-parser` is declared as a dependency and used by the executable target

### Requirement: Starter command groups
The system SHALL include top-level command groups `mail`, `cal`, `contacts`, `sync`, and `export` with placeholder handlers.

#### Scenario: Command help lists groups
- **WHEN** a user runs `swiftea --help`
- **THEN** help output lists the five command groups

### Requirement: Test data location
The system SHALL include a `Tests/TestData/` directory reserved for fixtures.

#### Scenario: Test data directory exists
- **WHEN** a developer lists the `Tests/` directory
- **THEN** `TestData/` is present
