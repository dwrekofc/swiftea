# Agent Instructions

## Start Here

- If the user asks for a new idea, new feature, proposal/spec/change, plan, or new capability: read `.d-spec/AGENTS.md` and follow the linked docs as-needed.
- If the user asks questions or needs context gathering: use `AskUserTool` for interviews and clarifications.
- If the user asks to implement an approved change/feature: follow the workflow below, then use **Beads as the sole execution source of truth** per `bd prime` (d-spec is input-only after approval).
- If the repo needs ideation docs setup/standardization: start with `.d-spec/project-setup.md`.

## Planning Phase - d-spec
THis project uses **d-spec** (`/.d-spec/`) for ideation and planning. See `.d-spec/AGENTS.md`

## Execution Phase - Beads
This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds



## End-to-End Workflow (Discovery → Spec → Beads → Implement)

### Planning Phase
1. **Discovery (read-only)**: read the north star (`docs/*master-plan*.md`) and skim candidates in `docs/ideas/` (`.d-spec/discovery-to-spec.md`).
2. **Interview (AskUserTool)**: ask one question at a time, option-based; stop and wait for answers (`.d-spec/discovery-to-spec.md`).
3. **Draft Spec (d-spec)**: create `d-spec/changes/<change-id>/` (verb-led, date-stamped) and write `proposal.md`, `tasks.md`, and spec deltas (`d-spec/AGENTS.md` Stage 1). Existing non-dated change IDs are grandfathered; new changes must use the date-stamped format.
4. **Validate**: run `d-spec validate <change-id> --strict`; ensure each new/modified requirement has ≥1 scenario (`d-spec/AGENTS.md`).
5. **Approval Gate**: do not create Beads issues or implement until the user approves the proposal in chat.

### Execution Phase
6. **Beads (after approval)**: decompose the approved d-spec proposal/specs/tasks into a **detailed** Beads epic + tasks per `bd prime` (each task must have a clear description and acceptance criteria). Add `Beads: <epic-id>` to `d-spec/changes/<change-id>/proposal.md`. After this step, **Beads is the source of truth**.
7. **Archive Idea (after approval)**: move `docs/ideas/<idea>.md` → `docs/archive/<idea>.md` and prepend YAML traceability keys (including `beads_epic_id`) (`.d-spec/archive-instructions.md`).
8. **Implement**: execute Beads tasks sequentially and update Beads statuses/fields as you work. Do **not** update `d-spec/changes/<change-id>/tasks.md` during implementation (d-spec is frozen after approval).
9. **Wrap Up**: follow the session completion checklist (below).


## d-spec → Beads Handoff

- Use d-spec only to draft/iterate proposals, specs, and approval-level tasks.
- Do not create Beads issues until the proposal is approved in chat.
- After approval, decompose into **detailed** Beads epics/tasks and make Beads the **single source of truth** for execution.
- Freeze d-spec after Beads creation; do not update `d-spec/changes/<change-id>/tasks.md` during implementation.

## Beads Task Template (use for every task)

```text
Title: <concise action>
Description: <what/why; 2-4 sentences>
Acceptance Criteria:
- [ ] <observable outcome>
- [ ] <test or verification>
Dependencies: <beads ids or "none">
Notes: <risks, edge cases, or references>
```

## Gates

- **Approval**: d-spec proposals require explicit chat approval before Beads creation or implementation.
- **Spec hygiene**: `d-spec validate <change-id> --strict` must pass before requesting approval.
- **Beads handoff**: once Beads is created, execution tracking happens only in Beads; d-spec remains read-only.
- **Archiving clarity**: idea docs are archived after approval; d-spec change folders are archived after execution.
- **Session completion**: work is not done until `git push` succeeds (see Wrap Up).


## Reference (d-spec; managed)

Consult this when drafting or validating d-spec changes; the workflow above is primary.

<!-- d-spec:START -->
# d-spec Instructions

These instructions are for AI assistants working in this project.

Open `@/d-spec/AGENTS.md` when a request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Is ambiguous and you need the authoritative d-spec format/conventions before drafting

Use `@/d-spec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

<!-- d-spec:END -->

## Beads
This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
