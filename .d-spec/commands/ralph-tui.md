---
description: Ralph-TUI workflow with Beads for autonomous task execution
---

# Ralph-TUI with Beads

This project uses **ralph-tui** with **Beads** for autonomous task execution. Ralph-TUI is an AI agent loop orchestrator that picks tasks from a Beads epic and executes them autonomously.

## Quick Start

```bash
# Run ralph-tui on an epic
ralph-tui run --tracker beads --epic <epic-id>

# Or let it pick the best available task
ralph-tui run --tracker beads
```

## How It Works

1. **Query**: Ralph-TUI runs `bd list --json --parent <epic>` to get tasks
2. **Select**: Finds next task (open status, highest priority, no blockers)
3. **Claim**: Sets task to `in_progress` via `bd update`
4. **Execute**: Spawns an agent to implement the task
5. **Complete**: Sets task to `closed` via `bd close`
6. **Sync**: Runs `bd sync` to push changes
7. **Repeat**: Until all tasks in epic are done

## Quality Gates (SwiftEA)

Every task MUST include these in acceptance criteria:
```
- [ ] `swift build` passes
- [ ] `swift test` passes
```

---

## User Story Format (REQUIRED)

All tasks MUST follow this format for ralph-tui execution.

### Title Format

```
US-XXX: Short descriptive title
```

Examples:
- `US-001: Add thread_id column to mail_mirror table`
- `US-002: Implement thread detection service`
- `US-003: Add swiftea mail threads CLI command`

### Description Template

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

### Labels

- **Epics**: `ralph,feature`
- **Tasks**: `ralph,task`

---

## Creating Ralph-TUI Beads

### Step 1: Create Epic

```bash
bd create --type=epic \
  --title="Feature Name" \
  --description="Feature description with success criteria" \
  --labels="ralph,feature"
```

### Step 2: Create Child Tasks

```bash
bd create --parent=<epic-id> \
  --title="US-001: Task title" \
  --description="As a developer, I need [what] so [why].

## Context
[Implementation details]

## Acceptance Criteria
- [ ] Specific outcome 1
- [ ] Specific outcome 2
- [ ] \`swift build\` passes
- [ ] \`swift test\` passes

---
## If You Cannot Complete This Task
1. Check off completed acceptance criteria
2. Add comment: what's done, remaining, blockers
3. Commit: \`git commit -m \"WIP: <task-id> - <summary>\"\`
4. Push: \`git push\`
5. Leave status as \`in_progress\`" \
  --priority=2 \
  --labels="ralph,task"
```

### Step 3: Add Dependencies

```bash
# Syntax: bd dep add <issue> <depends-on>
# (issue depends on / is blocked by depends-on)

bd dep add <us-002-id> <us-001-id>  # US-002 depends on US-001
bd dep add <us-003-id> <us-002-id>  # US-003 depends on US-002
```

---

## Task Sizing (Critical)

**Each task must be completable in ONE ralph-tui iteration** (~one agent context window).

Ralph-TUI spawns a fresh agent instance per iteration with no memory of previous work. If a task is too big, the agent runs out of context before finishing.

### Right-sized tasks:
- Add a database column + migration
- Add a CLI command with flags
- Update a service with new logic
- Write tests for a single component

### Too big (split these):
- "Build entire threading support" → Schema, detection, CLI, export
- "Add authentication" → Schema, middleware, commands, tests
- "Refactor the API" → One endpoint or pattern per task

**Rule of thumb:** If you can't describe the change in 2-3 sentences, it's too big.

---

## Dependency Order

Tasks must be ordered so earlier tasks don't depend on later ones.

**Correct order:**
1. Schema/database changes (no dependencies)
2. Services/backend logic (depends on schema)
3. CLI commands (depends on services)
4. Integration tests (depends on commands)

**Wrong order:**
1. CLI command (depends on schema that doesn't exist yet)
2. Schema change

---

## Acceptance Criteria Guidelines

### Good criteria (verifiable):
- "Add `thread_id` column to mail_mirror table"
- "CLI command `swiftea mail threads` lists all threads"
- "Test `testThreadDetection()` passes"

### Bad criteria (vague):
- "Works correctly"
- "Is well tested"
- "Handles edge cases"
- "Good performance"

---

## Task Selection Algorithm

Ralph-TUI selects the next task by:

1. Filter to tasks under the specified epic
2. Filter to tasks with status `open`
3. Filter to tasks with no unresolved dependencies
4. Sort by priority (lowest number first: 0=critical, 2=medium, 4=backlog)
5. Return the first matching task

---

## Priorities

| Priority | Meaning |
|----------|---------|
| 0 | Critical |
| 1 | High |
| 2 | Medium (default) |
| 3 | Low |
| 4 | Backlog |

---

## Example: Full Epic Creation

```bash
# Create epic
bd create --type=epic \
  --title="Email Threading Support" \
  --description="Add conversation threading to email sync and export" \
  --labels="ralph,feature"
# Returns: swiftea-xyz

# Create US-001 (schema - no deps)
bd create --parent=swiftea-xyz \
  --title="US-001: Add thread columns to mail_mirror" \
  --description="As a developer, I need thread metadata columns so conversations can be grouped.

## Context
Add thread_id, thread_position, thread_total columns to mail_mirror table.

## Acceptance Criteria
- [ ] Columns added and nullable
- [ ] Migration applies without data loss
- [ ] \`swift build\` passes
- [ ] \`swift test\` passes

---
## If You Cannot Complete This Task
..." \
  --priority=1 \
  --labels="ralph,task"
# Returns: swiftea-xyz.1

# Create US-002 (service - depends on schema)
bd create --parent=swiftea-xyz \
  --title="US-002: Implement thread detection service" \
  --description="..." \
  --priority=2 \
  --labels="ralph,task"
# Returns: swiftea-xyz.2

# Add dependency
bd dep add swiftea-xyz.2 swiftea-xyz.1

# Create US-003 (CLI - depends on service)
bd create --parent=swiftea-xyz \
  --title="US-003: Add swiftea mail threads command" \
  --description="..." \
  --priority=3 \
  --labels="ralph,task"
# Returns: swiftea-xyz.3

# Add dependency
bd dep add swiftea-xyz.3 swiftea-xyz.2

# Run ralph-tui
ralph-tui run --tracker beads --epic swiftea-xyz
```

---

## Troubleshooting

### "No tasks available"

Check that:
1. The epic has child tasks: `bd list --parent <epic>`
2. Tasks are `open` status: `bd list --status open`
3. Dependencies are met: `bd show <task-id>`

### "Task too big"

Split into smaller tasks. Each should be describable in 2-3 sentences.

### "Agent ran out of context"

The task is too big. Split it and add dependencies.

---

## Available Commands

```bash
# List ralph-tagged tasks
bd list --label ralph

# Find available ralph work
bd ready --label ralph

# Show task details
bd show <id>

# Run ralph-tui
ralph-tui run --tracker beads --epic <id>
```

---

## See Also

- `.d-spec/commands/beads-workflow.md` - Manual beads workflow
- `.d-spec/onboarding/discovery-to-spec.md` - Full planning → execution workflow
- Root `CLAUDE.md` - Session completion checklist
