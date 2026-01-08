# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Issue Tracking

This project uses **bd (beads)** for issue tracking.
Run `bd prime` for workflow context, or install hooks (`bd hooks install`) for auto-injection.

**Quick reference:**
- `bd ready` - Find unblocked work
- `bd create "Title" --type task --priority 2` - Create issue
- `bd close <id>` - Complete work
- `bd sync` - Sync with git (run at session end)

For full workflow details: `bd prime`

## Start Here

- If the user asks for a workflow, proposal/spec/change, plan, or new capability: read `.d-spec/AGENTS.md` and follow the linked docs as-needed.
- If the user asks questions or needs context gathering: use `AskUserTool` for interviews and clarifications.
- If the user asks to implement an approved change: follow the workflow below, then use `openspec/AGENTS.md` (Stage 2) for implementation sequencing.
- If the repo needs ideation docs setup/standardization: start with `.d-spec/project-setup.md`.

## End-to-End Workflow (Discovery → Spec → Beads → Implement)

1. **Discovery (read-only)**: read the north star (`docs/*master-plan*.md`) and skim candidates in `docs/ideas/` (`.d-spec/discovery-to-spec.md`).
2. **Interview (AskUserTool)**: ask one question at a time, option-based; stop and wait for answers (`.d-spec/discovery-to-spec.md`).
3. **Draft Spec (OpenSpec)**: create `openspec/changes/<change-id>/` and write `proposal.md`, `tasks.md`, and spec deltas (`openspec/AGENTS.md` Stage 1).
4. **Validate**: run `openspec validate <change-id> --strict`; ensure each new/modified requirement has ≥1 scenario (`openspec/AGENTS.md`).
5. **Approval Gate**: do not create Beads issues or implement until the user approves the proposal in chat.
6. **Beads (after approval)**: create 1 epic per change-id and tasks from `openspec/changes/<change-id>/tasks.md`; actively update statuses while working.
7. **Archive Idea (after approval)**: move `docs/ideas/<idea>.md` → `docs/archive/<idea>.md` and prepend YAML traceability keys (`.d-spec/archive-instructions.md`).
8. **Implement**: execute `tasks.md` sequentially; keep Beads in sync with progress (`openspec/AGENTS.md` Stage 2).
9. **Wrap Up**: follow the session completion checklist (below).

## Gates

- **Approval**: OpenSpec proposals require explicit chat approval before Beads creation or implementation.
- **Spec hygiene**: `openspec validate <change-id> --strict` must pass before requesting approval.
- **Session completion**: work is not done until `git push` succeeds (see Wrap Up).

## Command Cheat Sheet

```bash
# Discovery
rg --files -g'*.md'
rg -n "TODO|FIXME|NEEDS" docs -S

# OpenSpec (draft/validate)
openspec list
openspec list --specs
openspec spec list --long
openspec validate <change-id> --strict

# Beads (execute)
bd ready
bd show <id>
bd update <id> --status in_progress
bd close <id>
bd sync
```

## Reference (OpenSpec; managed)

Consult this when drafting or validating OpenSpec changes; the workflow above is primary.

<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Open `@/openspec/AGENTS.md` when a request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Is ambiguous and you need the authoritative OpenSpec format/conventions before drafting

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

## Wrap Up (Every Session)

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
