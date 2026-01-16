# Agent Instructions

## Start Here
- If the user asks for a new idea, new feature, proposal/spec/change, plan, or new capability: read `.claude/commands/gsd/help.md` and follow the linked docs as-needed.
- If the user asks questions or needs context gathering: use `AskUserTool` for interviews and clarifications.
- If the user asks to implement an approved change/feature: follow the **ralph-tui workflow** below with Beads as the execution source of truth.

**Workflow:** Idea → Interview → Planning → Approval → **Ralph-TUI Beads**

# Planning Phase - GSD
This project uses **GSD** (`/.planning/`) for ideation, roadmap and planning. See `.claude/commands/gsd/help.md` for detailed instructions.


# Execution Phase - Ralph-TUI with Beads
This project uses **ralph-tui** with **Beads** for autonomous task execution. All tasks MUST follow the ralph-tui user story format.

When creating PRDs use your "ralph-tui-prd" skill. See `.claude/skills/ralph-tui-prd/SKILL.md` for creating PRDs

When creating beads issues use your "ralph-tui-create-beads" skill. See `.claude/skills/ralph-tui-create-beads/SKILL.md` for converting PRDs into propper ralph beads issues

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
