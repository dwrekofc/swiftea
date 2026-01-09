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

### Execution Phase
12. **Beads handoff (after approval)**: before creating Beads issues, read `.d-spec/project.md` plus the change’s `proposal.md`, `design.md` (if present), all `specs/**/spec.md`, and `tasks.md`. Then create a **detailed** Beads epic + tasks per `bd prime` and add `Beads: <epic-id>` to `.d-spec/planning/changes/<change-id>/proposal.md`. See `.d-spec/onboarding/discovery-to-spec.md` for Beads prereads + task template.
13. **Update roadmap after approval**: once the Beads epic exists, update `.d-spec/roadmap.md` to reference the official spec(s) and Beads epic IDs.
14. **Enforce TDD via Beads structure**: write tests as Acceptance Criteria, use an epic with Success Criteria, split Red → Green → Refactor into child tasks for larger work, and wire dependencies so tests come first (label `tdd` or `tests-first` where relevant).
15. **Archive change doc**: move the change to `.d-spec/planning/archive/` with YAML traceability once the Beads epic exists.
16. **Implement via Beads**: execute Beads tasks sequentially and update Beads statuses/fields as you work. Do **not** update `.d-spec/planning/changes/<change-id>/tasks.md` during implementation (d-spec is frozen after approval).
17. **Wrap up**: follow the session completion checklist in root `CLAUDE.md`.

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

## d-spec → Beads Handoff (Explicit Requirements)

- Do not create Beads issues until the proposal is approved in chat.
- Before creating Beads issues, **must read**:
  - `.d-spec/swiftea-architecture-master-plan.md` (SwiftEA goals)
  - `.d-spec/project.md`
  - `.d-spec/planning/changes/<change-id>/proposal.md`
  - `.d-spec/planning/changes/<change-id>/design.md` (if present)
  - `.d-spec/planning/changes/<change-id>/specs/**/spec.md`
  - `.d-spec/planning/changes/<change-id>/tasks.md`
- After Beads creation, execution tracking happens only in Beads; d-spec remains read-only.

## Entrypoints

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
