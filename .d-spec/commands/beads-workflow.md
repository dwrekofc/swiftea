---
description: Show the AI-supervised issue workflow guide
---

Display the beads workflow for AI agents and developers.

# Beads Workflow

Beads is an issue tracker designed for AI-supervised coding workflows. Here's how to use it effectively:

## 1. Find Ready Work
Use `/beads:ready` or the `ready` MCP tool to see tasks with no blockers.

## 2. Claim Your Task
Update the issue status to `in_progress`:
- Via command: `/beads:update <id> in_progress`
- Via MCP tool: `update` with `status: "in_progress"`

## 3. Work on It
Implement, test, and document the feature or fix.
If TDD applies, follow the Red → Green → Refactor loop and keep tests green before closing tasks.

## 4. Discover New Work
As you work, you'll often find bugs, TODOs, or related work:
- Create issues: `/beads:create` or `create` MCP tool
- Link them: Use `dep` MCP tool with `type: "discovered-from"`
- This maintains context and work history

## 5. Complete the Task
Close the issue when done:
- Via command: `/beads:close <id> "Completed: <summary>"`
- Via MCP tool: `close` with reason

## 5a. If You Cannot Complete the Task

If context runs out, tests fail, or you hit a blocker:

1. **Update acceptance criteria** - Check off completed items in the task description
2. **Add handoff comment**:
   ```bash
   bd comments add <id> "Session ended: X/Y criteria complete.
   Files modified: [list]. Blocker: [if any]. Next steps: [actions]"
   ```
3. **Commit partial work**:
   ```bash
   git add . && git commit -m "WIP: <task-id> - <summary>" && git push
   ```
4. **Keep task `in_progress`** - Do NOT close incomplete tasks

**Key Rules:**
- NEVER close if tests are failing
- NEVER close if acceptance criteria are unchecked
- ALWAYS push partial work (uncommitted = lost)

## 6. Check What's Unblocked
After closing, check if other work became ready:
- Use `/beads:ready` to see newly unblocked tasks
- Start the cycle again

## Creating Atomic Tasks

Every task should be self-contained—the next agent can execute **without gathering context**.

**Required elements:**
- **Title:** Short descriptive name
- **Description:** "As a [user], I want [feature] so that [benefit]"
- **Problem:** What's broken/missing and why it matters
- **Files to modify:** Paths with function names, approx line numbers
- **Acceptance Criteria:** Verifiable checklist (specific, not vague)

**Good criteria:** `Button shows confirmation dialog`, `Test testFoo() verifies X`
**Bad criteria:** `Works correctly`, `Is well tested`

### Special Cases

**Bug fixes:**
- Include steps to reproduce
- Include expected vs actual behavior
- Include error messages or stack traces if available

**UI changes:**
- Always include: "Verify in browser using dev-browser skill"
- Describe visual expectations (placement, styling, behavior)

**Refactoring:**
- Explain the "before" and "after" state
- List all files that will change
- Clarify what should NOT change (behavior preservation)

**Include this footer in all tasks:**
```markdown
---
## If You Cannot Complete This Task
1. Check off completed acceptance criteria
2. Add comment: what's done, remaining, blockers
3. Commit: `git commit -m "WIP: <task-id> - <summary>"`
4. Push: `git push`
5. Leave status as `in_progress`
```

## Tips
- **Priority levels**: 0=critical, 1=high, 2=medium, 3=low, 4=backlog
- **Issue types**: bug, feature, task, epic, chore
- **Dependencies**: Use `blocks` for hard dependencies, `related` for soft links
- **TDD encoding**: Put tests in Acceptance Criteria, use epic Success Criteria, and create Red → Green → Refactor child tasks with dependencies; label `tdd` or `tests-first` when relevant.
- **Auto-sync**: Changes automatically export to `.beads/issues.jsonl` (5-second debounce)
- **Git workflow**: After `git pull`, JSONL auto-imports if newer than DB

## Available Commands
- `/beads:ready` - Find unblocked work
- `/beads:create` - Create new issue
- `/beads:show` - Show issue details
- `/beads:update` - Update issue
- `/beads:close` - Close issue
- `/beads:workflow` - Show this guide (you are here!)

## MCP Tools Available
Use these via the beads MCP server:
- `ready`, `list`, `show`, `create`, `update`, `close`
- `dep` (manage dependencies), `blocked`, `stats`
- `init` (initialize bd in a project)

For more details, see the beads README at: https://github.com/steveyegge/beads
