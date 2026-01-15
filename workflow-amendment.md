# Beads Workflow Amendment: Task Quality & Completion Protocol

**Status:** DRAFT
**Created:** 2026-01-14
**Problems Addressed:**
1. Tasks lack sufficient detail for agents to begin work without additional context gathering
2. Agents may not complete tasks in one session due to context limits, test failures, or blockers
3. Current workflow lacks explicit instructions for handling incomplete work, leading to lost progress and poor handoffs

---

## Part 1: Creating Atomic, Self-Contained Tasks

### Goal
Every task description should contain enough information that the next agent or developer can execute the task **without needing to read anything else or gather context to begin work**.

### Task Structure

Each task needs:
- **Title:** Short descriptive name
- **Description:** "As a [user], I want [feature] so that [benefit]"
- **Acceptance Criteria:** Verifiable checklist of what "done" means

Each task should be small enough to implement in **one focused session**.

### Format Template

```markdown
### <task-id>: [Title]

**Description:** As a [user], I want [feature] so that [benefit].

**Problem:** [What's broken/missing and why it matters]

**Files to modify:**
- `path/to/file.swift` (function name, lines ~X-Y)
- `path/to/other/file.swift`

**Acceptance Criteria:**
- [ ] Specific verifiable criterion
- [ ] Another criterion
- [ ] Existing tests pass
- [ ] New test added: `testSpecificBehavior()` verifies X
- [ ] **[UI tasks only]** Verify in browser using dev-browser skill
```

### Writing Good Acceptance Criteria

**Bad (vague, unverifiable):**
- [ ] Works correctly
- [ ] Handles errors properly
- [ ] Is well tested

**Good (specific, verifiable):**
- [ ] Button shows confirmation dialog before deleting
- [ ] Error message includes the invalid field name
- [ ] Test `testDeleteShowsConfirmation()` verifies dialog appears
- [ ] Returns 404 status code when resource not found

### Best Practices

1. **Be explicit and unambiguous** - Don't assume context
2. **Avoid jargon or explain it** - Not everyone knows your codebase
3. **Provide enough detail** - Include purpose, files, and core logic
4. **Number requirements** - Makes them easy to reference
5. **Use concrete examples** - Show expected inputs/outputs where helpful
6. **Include file paths** - Exact locations reduce search time
7. **Name specific tests** - `testFoo()` not "add tests"

### Special Cases

**For bug fixes:**
- Include steps to reproduce
- Include expected vs actual behavior
- Include error messages or stack traces if available

**For UI changes:**
- Always include: "Verify in browser using dev-browser skill"
- Describe visual expectations (placement, styling, behavior)

**For refactoring:**
- Explain the "before" and "after" state
- List all files that will change
- Clarify what should NOT change (behavior preservation)

---

## Part 2: Handling Incomplete Work

### Problem Statement

The current beads workflow has a binary completion model:
- Tasks are either `open` → `in_progress` → `closed`
- No structured way to record partial progress
- "Provide context for next session" is vague
- Acceptance criteria checkboxes exist but agents aren't instructed to update them
- If tests fail or context runs out, the next agent must re-discover state

**Result:** Work gets lost, agents duplicate effort, partial progress is invisible.

### Partial Completion Protocol

Add the following section to the beads workflow documentation (CLAUDE.md or bd onboard output):

```markdown
## Partial Completion Protocol

If you cannot complete a task (context limit, test failures, blockers), you MUST:

1. **Update acceptance criteria** - Edit the task description to check off completed items:
   ```bash
   bd update <id> --description "$(bd show <id> --field description | sed 's/- \[ \] Completed item/- [x] Completed item/')"
   ```
   Or manually update the description with checked boxes.

2. **Add progress section** - Append to description:
   ```markdown
   ## Progress (as of YYYY-MM-DD)
   **Completed:**
   - [x] Item 1
   - [x] Item 2

   **Remaining:**
   - [ ] Item 3
   - [ ] Item 4

   **Blocker:** [Description of what's blocking, if any]
   ```

3. **Add handoff comment** - Document state for next agent:
   ```bash
   bd comments add <id> "Session ended: 3/8 tests written. MockMailDatabase created.
   Blocked on: MailDatabase protocol extraction needed before remaining tests.
   Files modified: Tests/SwiftEAKitTests/MessageResolverTests.swift
   Next steps: Extract protocol, then write remaining 5 tests."
   ```

4. **Commit partial work** - Use WIP prefix:
   ```bash
   git add .
   git commit -m "WIP: <task-id> - <summary of completed work>"
   git push
   ```

5. **Keep task in_progress** - Do NOT close incomplete tasks:
   ```bash
   bd update <id> --status in_progress  # Ensure status reflects reality
   ```

### Key Rules
- NEVER close a task if tests are failing
- NEVER close a task if acceptance criteria are unchecked
- ALWAYS commit and push partial work (uncommitted work is lost work)
- ALWAYS document what's done vs. remaining
```

### Handoff Comment Template

Standardize handoff comments:

```markdown
**Session End: <task-id>**
- **Status:** X of Y acceptance criteria complete
- **Tests:** X passing, Y failing, Z not yet written
- **Files changed:** [list]
- **Blocker:** [if any]
- **Next steps:** [specific actions for next agent]
```

### Task Footer Template

All new tasks should include this footer:

```markdown
---
## If You Cannot Complete This Task

1. Check off completed acceptance criteria above
2. Add a comment with: what's done, what's remaining, any blockers
3. Commit with: `git commit -m "WIP: <task-id> - <summary>"`
4. Push changes: `git push`
5. Leave task status as `in_progress`

Do NOT close this task until ALL acceptance criteria are checked.
```

---

## Part 3: Implementation Options

### Option A: Update CLAUDE.md (Minimal)
Add the Partial Completion Protocol section to the project's CLAUDE.md. Agents will see it in system context.

**Pros:** Simple, immediate
**Cons:** Only affects this project, depends on agents reading it

### Option B: Update bd onboard/workflow output
Modify the beads plugin to include partial completion instructions in `bd workflow` or `bd onboard` output.

**Pros:** Applies to all beads projects, always visible
**Cons:** Requires beads plugin changes

### Option C: Add bd checkpoint command
New command: `bd checkpoint <id> "progress notes"`
- Automatically adds timestamped comment
- Updates task's `last_checkpoint` field
- Could auto-extract git diff summary

**Pros:** Structured, consistent, tooling-enforced
**Cons:** Requires significant beads development

### Option D: Pre-flight task instructions (Recommended)
Add standard footer to all task descriptions (as proposed above). This is self-contained - the instructions travel with the task.

**Pros:** Works immediately, no tooling changes, self-documenting
**Cons:** Adds ~100 tokens to each task description

---

## Recommended Approach

**Phase 1 (Now):** Option D - Add footer to task descriptions
**Phase 2 (Soon):** Option A - Add to CLAUDE.md
**Phase 3 (Later):** Option C - Build `bd checkpoint` command

---

## Acceptance Criteria for This Amendment

**Part 1 - Task Quality:**
- [x] Document task creation best practices with examples
- [x] Define format template for atomic tasks
- [x] Include good vs bad acceptance criteria examples
- [x] All tasks in epic swiftea-pzv follow the atomic task format

**Part 2 - Partial Completion:**
- [x] All tasks in epic swiftea-pzv updated with partial completion footer
- [ ] CLAUDE.md updated with Partial Completion Protocol section
- [ ] Test: Assign task to fresh agent, verify it follows protocol on incomplete work

**Documentation:**
- [ ] Document in beads plugin README or workflow guide
- [ ] Add to `bd workflow` command output
