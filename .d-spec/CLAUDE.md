# d-spec Agent Instructions

This folder contains the d-spec planning workflow and links to the onboarding docs used by agents.

## Start Here

- Use this file for the high-level planning → execution workflow.
- Use `.d-spec/onboarding/` for detailed step-by-step guides.

## End-to-End Workflow (Ideation → Spec → Beads → Implement)

### Planning Phase
1. **Create vision doc (new projects)**: interview with `AskUserTool` and capture the north-star vision in `.d-spec/*master-plan*.md` (see `.d-spec/onboarding/vision-doc.md` + `.d-spec/onboarding/create-master-vision.md`).
2. **Convert vision → project conventions + roadmap (when ready to implement)**: interview the user and convert the vision into `.d-spec/project.md` (app folder structure, architecture, tech stack, etc.) and `.d-spec/roadmap.md`. At this point, the vision doc is read-only.
3. **Create idea doc**: capture intent and scope with `AskUserTool`; save in `.d-spec/planning/ideas/` and leave it there until it's selected for a change proposal (see `.d-spec/onboarding/create-ideas.md`).
4. **Add to plan**: record the idea as an unimplemented/future item in `.d-spec/*master-plan*.md` and add it to `.d-spec/roadmap.md` as a potential change.
5. **Discovery (read-only)**: read `.d-spec/*master-plan*.md`, `.d-spec/project.md`, `.d-spec/roadmap.md`, then review `.d-spec/planning/ideas/` (see `.d-spec/onboarding/discovery-to-spec.md`).
6. **Interview (AskUserTool)**: ask one question at a time, option-based; stop and wait for answers (see `.d-spec/onboarding/discovery-to-spec.md`).
7. **Draft change (d-spec)**: create `.d-spec/planning/changes/<change-id>/` (verb-led, date-stamped) and write `proposal.md`, `tasks.md`, and spec deltas under `specs/` (see `.d-spec/onboarding/discovery-to-spec.md`). Existing non-dated change IDs are grandfathered; new changes must use the date-stamped format.
8. **Encode TDD in tasks**: define test-first acceptance criteria and, for non-trivial work, outline Red → Green → Refactor tasks or dependencies so tests drive implementation.
9. **Validate**: ensure each new/modified requirement has ≥1 scenario.
   - Reference details (change-id rules, spec delta format, design.md criteria, validation checklist): `.d-spec/onboarding/discovery-to-spec.md`
10. **Link + archive idea**: add bidirectional YAML links between idea and change, then move the idea to `.d-spec/planning/ideas/archive/` (see `.d-spec/onboarding/archive-instructions.md`).
11. **Approval gate**: do not create Beads issues or implement until the user approves the proposal in chat.

### Execution Phase (Ralph-TUI with Beads)

This project uses **ralph-tui** with **Beads** for autonomous task execution. All tasks MUST follow the ralph-tui user story format.

12. **Ralph-TUI Beads handoff (after approval)**: before creating Beads issues, read `.d-spec/project.md` plus the change's `proposal.md`, `design.md` (if present), all `specs/**/spec.md`, and `tasks.md`. Then create ralph-tui formatted Beads:
    - **Epic**: `bd create --type=epic --title="..." --labels="ralph,feature"`
    - **Tasks**: `bd create --parent=<epic> --title="US-XXX: ..." --labels="ralph,task"`
    - **Dependencies**: `bd dep add <task> <depends-on>` (schema → backend → CLI)
    - Add `Beads: <epic-id>` to `.d-spec/planning/changes/<change-id>/proposal.md`
    - See `.d-spec/commands/ralph-tui.md` for full format spec.

13. **User Story Format (REQUIRED)**:
    - Title: `US-XXX: Short descriptive title`
    - Description: `As a [role], I want/need [what] so [why]`
    - Acceptance criteria with quality gates: `swift build` and `swift test` passes
    - Labels: `ralph,task` (tasks) or `ralph,feature` (epics)
    - Task footer with partial completion protocol

14. **Task Sizing**: Each task must be completable in ONE ralph-tui iteration. Split large features into schema → services → CLI → tests.

15. **Update roadmap after approval**: once the Beads epic exists, update `.d-spec/roadmap.md` to reference the official spec(s) and Beads epic IDs.

16. **Archive change doc**: move the change to `.d-spec/planning/archive/` with YAML traceability once the Beads epic exists.

17. **Execute via ralph-tui**: Run `ralph-tui run --tracker beads --epic <epic-id>` for autonomous execution. Ralph picks tasks in dependency order, claims them, implements, and closes when done. Do **not** update `.d-spec/planning/changes/<change-id>/tasks.md` during implementation (d-spec is frozen after approval).

18. **Wrap up**: follow the session completion checklist in root `CLAUDE.md`.

## Goal Alignment (Required)

Every proposal MUST include a `goals:` field in its YAML frontmatter, referencing one or more SwiftEA goals from `.d-spec/swiftea-architecture-master-plan.md`.

**Valid goal references**:

| Goal | Type | Description |
|------|------|-------------|
| SG-1 | Core | Unified PIM Access |
| SG-2 | Core | Cross-Module Intelligence |
| SG-3 | Core | Data Liberation |
| SG-4 | Supporting | ClaudEA-Ready Output |
| SG-5 | Supporting | Local-First Architecture |
| SG-6 | Supporting | Modular Extensibility |

**When creating a new proposal, verify:**
1. At least one SwiftEA goal is served
2. The goal reference is valid (SG-1 through SG-6)
3. The proposal scope aligns with the referenced goal(s)

**Example proposal frontmatter:**
```yaml
---
title: Add Calendar Module
goals:
  - SG-1  # Unified PIM Access
  - SG-2  # Cross-Module Intelligence
status: draft
---
```

## d-spec → Ralph-TUI Beads Handoff

- Do not create Beads issues until the proposal is approved in chat.
- Before creating Beads issues, **must read**:
  - `.d-spec/swiftea-architecture-master-plan.md` (SwiftEA goals)
  - `.d-spec/project.md`
  - `.d-spec/planning/changes/<change-id>/proposal.md`
  - `.d-spec/planning/changes/<change-id>/design.md` (if present)
  - `.d-spec/planning/changes/<change-id>/specs/**/spec.md`
  - `.d-spec/planning/changes/<change-id>/tasks.md`
- After Beads creation, execution tracking happens only in Beads; d-spec remains read-only.

### Ralph-TUI Task Requirements

All tasks MUST follow the ralph-tui user story format:

1. **Title**: `US-XXX: Short descriptive title`
2. **Description**: `As a [role], I want/need [what] so [why]`
3. **Acceptance Criteria**: Specific outcomes + quality gates
4. **Labels**: `ralph,task` (tasks) or `ralph,feature` (epics)
5. **Quality Gates** (MUST include in every task):
   ```
   - [ ] `swift build` passes
   - [ ] `swift test` passes
   ```
6. **Task Footer** (MUST include in every task):
   ```markdown
   ---
   ## If You Cannot Complete This Task
   1. Check off completed acceptance criteria
   2. Add comment: what's done, remaining, blockers
   3. Commit: `git commit -m "WIP: <task-id> - <summary>"`
   4. Push: `git push`
   5. Leave status as `in_progress`
   ```

### Task Sizing

Each task MUST be completable in ONE ralph-tui iteration (~one agent context window).

**Right-sized tasks:**
- Add a database column + migration
- Add a CLI command with flags
- Update a service with new logic
- Write tests for a single component

**Split these (too big):**
- "Build entire feature" → Schema, services, CLI, tests
- "Refactor module" → One refactoring step per task

### Dependency Order

Use `bd dep add <task> <depends-on>`:
1. Schema/database changes (no dependencies)
2. Services/backend logic (depends on schema)
3. CLI commands (depends on services)
4. Integration tests (depends on commands)

### Running Ralph-TUI

```bash
ralph-tui run --tracker beads --epic <epic-id>
```

Ralph-TUI will autonomously:
1. Select the highest-priority unblocked task
2. Claim it (`in_progress`)
3. Implement and verify acceptance criteria
4. Close it when complete
5. Repeat until epic is done

## Entrypoints

- **Ralph-TUI workflow (execution)**: `.d-spec/commands/ralph-tui.md`
- Beads manual workflow: `.d-spec/commands/beads-workflow.md`
- Project setup (docs ideation structure): `.d-spec/onboarding/project-setup.md`
- Discovery → Spec → Beads → Implement: `.d-spec/onboarding/discovery-to-spec.md`
- Brownfield intake (existing docs/specs): `.d-spec/onboarding/brownfield-intake.md`
- Archiving processed ideas: `.d-spec/onboarding/archive-instructions.md`
- Creating new idea docs (YAML + AskUserTool): `.d-spec/onboarding/create-ideas.md`
- Creating/updating the master plan: `.d-spec/onboarding/create-master-vision.md`
- Defining project conventions & standards (project.md): `.d-spec/onboarding/create-standards.md`
- Creating a vision doc: `.d-spec/onboarding/vision-doc.md`
- Creating/updating a roadmap: `.d-spec/onboarding/create-roadmap.md`

## Directory Anchors (Project Convention)

- North star: `.d-spec/*master-plan*.md`
- Project overview: `.d-spec/project.md`
- Project conventions & standards: `.d-spec/project.md`
- Roadmap: `.d-spec/roadmap.md`
- Ideas (intake): `.d-spec/planning/ideas/`
- Ideas (archive): `.d-spec/planning/ideas/archive/`
- Changes (proposals): `.d-spec/planning/changes/`
- Archived changes: `.d-spec/planning/archive/`
