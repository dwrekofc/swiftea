# Change: Create master app folder structure

## Why
SwiftEA needs a stable SwiftPM layout that reflects the modular monolith (Core + Modules + CLI) so Phase 1 implementation can proceed without structural churn.

## What Changes
- Scaffold a SwiftPM package named `SwiftEA` with an executable `swiftea`.
- Establish source layout for `SwiftEAKit` (Core + Modules) and `SwiftEACLI` (commands + output).
- Add `swift-argument-parser` and stub top-level command groups (`mail`, `cal`, `contacts`, `sync`, `export`).
- Create a `Tests/TestData` folder for future fixtures.

## Impact
- Affected specs: `specs/project-structure/spec.md` (new capability)
- Affected code: `Package.swift`, `Sources/SwiftEAKit/**`, `Sources/SwiftEACLI/**`, `Tests/TestData/`

Beads: swiftea-btu
