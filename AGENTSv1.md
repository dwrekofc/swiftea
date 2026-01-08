# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Combined Workflow (Discovery → Spec → Beads → Implement)

Keep this file succinct; detailed procedures live in `.d-spec/` (start at `.d-spec/AGENTS.md`).

### When To Use This Workflow
- If the user asks for a workflow, spec, proposal, plan, or new capability: read `.d-spec/AGENTS.md`, then follow the linked docs as-needed.
- If the user asks to implement an approved change: follow `openspec/AGENTS.md` (Stage 2) and use Beads to track execution.

### Default Flow (High Level)
1. **Discovery (read-only):** read the master plan in `docs/*master-plan*.md`, then review candidate files in `docs/ideas/`.
2. **Interview:** use the ask-user-question interview style (one question at a time, option-based) to clarify scope and priorities.
3. **Spec Draft (OpenSpec):** create an OpenSpec change under `openspec/changes/<change-id>/` and run `openspec validate <change-id> --strict`.
4. **Approval Gate:** do not generate Beads issues or begin implementation until the user explicitly approves the proposal in chat.
5. **Beads Planning:** after approval, create **one epic per change-id** and tasks from `openspec/changes/<change-id>/tasks.md`.
6. **Archive Idea:** after approval, move the idea from `docs/ideas/` → `docs/archive/` and prepend YAML traceability keys.
7. **Implementation:** execute tasks sequentially; actively manage Beads statuses while working.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

### OpenSpec Quick Reference
```bash
openspec list
openspec list --specs
openspec spec list --long
openspec validate <change-id> --strict
```

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
