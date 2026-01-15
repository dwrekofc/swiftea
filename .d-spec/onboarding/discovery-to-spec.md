# Discovery → d-spec → Beads (Proposal → Execution)

This doc is the detailed procedure behind the “Discovery → Spec → Beads → Implement” section in `AGENTS.md`.

## Triggers

Use this workflow when the user asks for a workflow, proposal, spec, plan, or to turn ideas into implementation tasks.

## Inputs

- **Master plan (read first)**: `.d-spec/swiftea-architecture-master-plan.md` (SwiftEA goals SG-1 through SG-6)
- Upstream context: `.d-spec/claudea-swiftea-ecosystem-master-plan.md` (informational only)
- Project overview: `.d-spec/project.md`
- Roadmap: `.d-spec/roadmap.md`
- Project conventions & standards: `.d-spec/project.md`
- Intake ideas: `.d-spec/planning/ideas/*.md`
- Existing changes: `.d-spec/planning/changes/`
- Archived changes (context): `.d-spec/planning/archive/`

## Outputs

- d-spec change: `.d-spec/planning/changes/<change-id>/...` (proposal + specs for approval)
- Beads epic + tasks (only after chat approval; **execution source of truth**)
- Archived idea doc with YAML traceability (only after chat approval)

## Workflow

### 1) Discovery (read-only)

1. Read the master plan doc in `.d-spec/` (first match for `*master-plan*.md`).
2. Read `.d-spec/project.md` and `.d-spec/roadmap.md`.
3. Enumerate idea docs in `.d-spec/planning/ideas/` and select 3–5 candidate ideas to summarize.
4. Summarize candidates and ask the user to pick which one to process next.

Notes:
- Prefer `rg --files -g'*.md'` for enumeration and `rg -n "TODO|FIXME|NEEDS"` for gaps.
- If the chosen idea overlaps an existing change in `.d-spec/planning/changes/`, surface the overlap and ask the user to decide case-by-case.

### 2) Interview (clarify scope)

Use `AskUserTool` for all user interviews and context gathering:
- Ask one question at a time
- Provide 2–4 concrete options with tradeoffs
- Stop and wait for the answer

Target questions:
- scope boundaries (in/out)
- priority ordering
- breaking changes and migrations
- impacted capabilities (multi-cap allowed)

### 3) Draft d-spec change (no Beads yet)

1. Choose a verb-led, date-stamped change id: `<verb>-<slug>-YYYY-MM-DD`. Existing non-dated change IDs are grandfathered; new changes must use the date-stamped format.
2. **Identify SwiftEA goals**: Before drafting, identify which SwiftEA goals (SG-1 through SG-6) this change serves. At least one is required.
3. Scaffold:
   - `.d-spec/planning/changes/<change-id>/proposal.md` (with `goals:` in YAML frontmatter)
   - `.d-spec/planning/changes/<change-id>/tasks.md` (approval-level checklist; not execution source)
   - `.d-spec/planning/changes/<change-id>/specs/<capability>/spec.md` deltas (one per impacted capability)
   - `.d-spec/planning/changes/<change-id>/design.md` when needed
4. Ensure each new/modified requirement includes at least one scenario.
5. Encode TDD expectations in `tasks.md`: acceptance criteria should be tests, and for larger work split Red → Green → Refactor into ordered tasks or dependencies.


Approval gate:
- Do not generate Beads issues or start implementation until the user approves the proposal in chat.

### 4) After chat approval

1. **Required reads before Beads**:
   - `.d-spec/project.md`
   - `.d-spec/planning/changes/<change-id>/proposal.md`
   - `.d-spec/planning/changes/<change-id>/design.md` (if present)
   - `.d-spec/planning/changes/<change-id>/specs/**/spec.md`
   - `.d-spec/planning/changes/<change-id>/tasks.md`
2. Decompose the approved proposal/specs/tasks into a **detailed** Beads epic + tasks per `bd prime` (each task must include a clear description and acceptance criteria; expand beyond `tasks.md` as needed). Encode TDD: tests as Acceptance Criteria, epic Success Criteria, and Red → Green → Refactor tasks with dependencies for non-trivial work.
3. Add traceability:
   - Add `Beads: <epic-id>` to `.d-spec/planning/changes/<change-id>/proposal.md`
   - Add bidirectional YAML links between the idea doc and change
4. After the Beads epic exists, update the roadmap to reference the official spec(s) and Beads epic IDs for the approved change.
5. Archive the processed idea doc (see `.d-spec/onboarding/archive-instructions.md`) and fill `beads_epic_id` in the YAML header.
6. Freeze d-spec: do not update `.d-spec/planning/changes/<change-id>/tasks.md` during implementation; all execution tracking happens in Beads.

## Reference: Change-ID Rules

- Format: `<verb>-<slug>-YYYY-MM-DD` (verb-led, kebab-case, date-stamped).
- Uniqueness: check `.d-spec/planning/changes/` and `.d-spec/planning/archive/` before choosing.
- Existing non-dated change IDs are grandfathered; new changes must use the date-stamped format.

## Reference: Change Folder Scaffold

Create the following (minimum set):

```
.d-spec/planning/changes/<change-id>/
├── proposal.md
├── tasks.md
├── specs/
│   └── <capability>/
│       └── spec.md
└── design.md   # only when needed
```

## Reference: proposal.md Template

```markdown
---
title: <Change Title>
goals:
  - SG-1  # Unified PIM Access (if applicable)
  - SG-2  # Cross-Module Intelligence (if applicable)
status: draft
created: YYYY-MM-DD
---

# <Change Title>

## Summary

One paragraph describing what this change does and why.

## Goal Alignment

This change advances:
- **SG-X**: <explanation of how this change serves this goal>

## Scope

**In scope**:
- ...

**Out of scope**:
- ...

## Impact

- **Files/modules affected**: ...
- **Breaking changes**: None / Yes (describe)
- **Migration needed**: None / Yes (describe)

## References

- Idea doc: `.d-spec/planning/ideas/<idea>.md` (if applicable)
- Related specs: ...
```

## Reference: Spec Delta Format + Scenario Rules

- Use delta sections: `## ADDED Requirements`, `## MODIFIED Requirements`, `## REMOVED Requirements`, `## RENAMED Requirements`.
- Each requirement uses `### Requirement: ...`.
- **Every requirement must include at least one `#### Scenario:`.**
- Scenario header must be level-4 (`#### Scenario:`) and include WHEN/THEN steps.

Example:

```markdown
## ADDED Requirements
### Requirement: New Feature
The system SHALL provide ...

#### Scenario: Success case
- **WHEN** ...
- **THEN** ...
```

## Reference: design.md Criteria + Minimal Template

Create `design.md` only when needed (otherwise omit):
- Cross-cutting change (multiple modules/services) or new architectural pattern
- New external dependency or significant data model change
- Security, performance, or migration complexity
- Ambiguity that benefits from technical decisions before coding

Minimal template:

```markdown
## Context

## Goals / Non-Goals

## Decisions

## Risks / Trade-offs

## Migration Plan

## Open Questions
```

## Reference: Validation Checklist + Common Failures

Checklist:
- Change-id follows `<verb>-<slug>-YYYY-MM-DD` and is unique.
- `proposal.md`, `tasks.md`, and at least one `specs/<capability>/spec.md` exist.
- **`proposal.md` has `goals:` in YAML frontmatter with at least one valid SwiftEA goal (SG-1 through SG-6).**
- Each requirement has at least one `#### Scenario:`.
- Scenario headers are `####` (not bullets or `###`).
- Delta section headers use `ADDED|MODIFIED|REMOVED|RENAMED`.


Common failures:
- **Missing `goals:` field in proposal.md.**
- **Invalid goal reference (must be SG-1 through SG-6).**
- Missing scenario per requirement.
- Wrong scenario header level (`###` or bullet).
- Using MODIFIED without including the full, updated requirement block.
- Missing delta section headers or typo in header text.

## Reference: Ralph-TUI Beads Handoff

This project uses **ralph-tui** with **Beads** for autonomous task execution. All tasks MUST follow the ralph-tui user story format.

### Prereads (Required)

Before creating Beads issues, **must read**:
- `.d-spec/project.md`
- `.d-spec/planning/changes/<change-id>/proposal.md`
- `.d-spec/planning/changes/<change-id>/design.md` (if present)
- `.d-spec/planning/changes/<change-id>/specs/**/spec.md`
- `.d-spec/planning/changes/<change-id>/tasks.md`

### Quality Gates (SwiftEA)

Every task MUST include these in acceptance criteria:
```
- [ ] `swift build` passes
- [ ] `swift test` passes
```

### Creating Ralph-TUI Beads

```bash
# 1. Create epic with ralph label
bd create --type=epic \
  --title="Feature Name" \
  --description="Feature description with success criteria" \
  --labels="ralph,feature"

# 2. Create child tasks with ralph format
bd create --parent=<epic-id> \
  --title="US-001: Task title" \
  --description="..." \
  --priority=2 \
  --labels="ralph,task"

# 3. Add dependencies (schema → backend → CLI)
bd dep add <task-id> <depends-on-id>
```

### User Story Format (REQUIRED)

**Title:** `US-XXX: Short descriptive title`

**Description Template:**
```markdown
As a [role], I want/need [what] so [why].

## Context
[Implementation details, file hints, constraints]

## Acceptance Criteria
- [ ] Specific outcome 1
- [ ] Specific outcome 2
- [ ] `swift build` passes
- [ ] `swift test` passes

---
## If You Cannot Complete This Task
1. Check off completed acceptance criteria
2. Add comment: what's done, remaining, blockers
3. Commit: `git commit -m "WIP: <task-id> - <summary>"`
4. Push: `git push`
5. Leave status as `in_progress`
```

### Task Sizing Rule

**Each task must be completable in ONE ralph-tui iteration** (~one agent context window).

**Right-sized:**
- Add a database column + migration
- Add a CLI command with flags
- Update a service with new logic

**Too big (split these):**
- "Build entire feature" → Schema, detection, CLI, export
- "Refactor module" → One step per task

### Dependency Order

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
