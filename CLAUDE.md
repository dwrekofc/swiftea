# Agent Instructions

## Start Here

- If the user asks for a new idea, new feature, proposal/spec/change, plan, or new capability: read `.d-spec/CLAUDE.md` and follow the linked docs as-needed.
- If the user asks questions or needs context gathering: use `AskUserTool` for interviews and clarifications.
- If the user asks to implement an approved change/feature: follow the **ralph-tui workflow** below with Beads as the execution source of truth.
- If the repo needs ideation docs setup/standardization: start with `.d-spec/onboarding/project-setup.md`.

# Planning Phase - d-spec
This project uses **d-spec** (`/.d-spec/`) for ideation and planning. See `.d-spec/CLAUDE.md`

## Quick Reference

```bash
# Ideation
.d-spec/planning/ideas/     # Create new ideas here
.d-spec/planning/changes/   # Draft change proposals

# Key docs
.d-spec/*master-plan*.md    # North star vision
.d-spec/project.md          # Architecture & conventions
.d-spec/roadmap.md          # Planned work
```

**Workflow:** Idea → Interview → Change Proposal → Approval → **Ralph-TUI Beads**

# Execution Phase - Ralph-TUI with Beads

This project uses **ralph-tui** with **Beads** for autonomous task execution. All tasks MUST follow the ralph-tui user story format.

## Quality Gates (SwiftEA)

Every task MUST include these in acceptance criteria:
```
- [ ] `swift build` passes
- [ ] `swift test` passes
```

## User Story Format (REQUIRED)

**Title:** `US-XXX: Short descriptive title`

**Description:**
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

**Labels:** `ralph,task` (or `ralph,feature` for epics)

## Creating Ralph-TUI Beads

```bash
# 1. Create epic
bd create --type=epic \
  --title="Feature Name" \
  --description="Feature description with success criteria" \
  --labels="ralph,feature"

# 2. Create child tasks (with quality gates!)
bd create --parent=<epic-id> \
  --title="US-001: Task title" \
  --description="As a [role]..." \
  --priority=2 \
  --labels="ralph,task"

# 3. Add dependencies (schema → backend → UI)
bd dep add <task-id> <depends-on-id>

# 4. Run ralph-tui
ralph-tui run --tracker beads --epic <epic-id>
```

## Task Sizing Rule

**Each task must be completable in ONE ralph-tui iteration** (~one agent context window).

**Right-sized:**
- Add a database column + migration
- Add a CLI command with flags
- Update a service with new logic

**Too big (split these):**
- "Build entire threading support" → Schema, detection, CLI, export
- "Add authentication" → Schema, middleware, commands, tests

## Dependency Order

1. Schema/database changes (no dependencies)
2. Services/backend logic (depends on schema)
3. CLI commands (depends on services)
4. Integration tests (depends on commands)

## Quick Reference

```bash
bd ready              # Find available work (ralph picks automatically)
bd show <id>          # View issue details
bd list --label ralph # List ralph-tagged tasks
ralph-tui run --tracker beads --epic <id>  # Autonomous execution
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds (tests should be written first unless explicitly exempted)
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

## Partial Completion & Task Quality

For detailed guidance on:
- **Partial completion protocol** - What to do if you can't finish a task
- **Creating atomic tasks** - Self-contained task descriptions
- **Special cases** - Bug fixes, UI changes, refactoring templates

Run `bd workflow` or see `.d-spec/commands/beads-workflow.md`
