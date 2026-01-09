# Agent Instructions

## Start Here

- If the user asks for a new idea, new feature, proposal/spec/change, plan, or new capability: read `.d-spec/AGENTS.md` and follow the linked docs as-needed.
- If the user asks questions or needs context gathering: use `AskUserTool` for interviews and clarifications.
- If the user asks to implement an approved change/feature: follow the workflow below, then use **Beads as the sole execution source of truth** per `bd prime` (d-spec is input-only after approval).
- If the repo needs ideation docs setup/standardization: start with `.d-spec/onboarding/project-setup.md`.

# Planning Phase - d-spec
THis project uses **d-spec** (`/.d-spec/`) for ideation and planning. See `.d-spec/AGENTS.md`

## Quick Reference
<!-- note to editor:START -->
add d-spec quickstart information here, see beads quickstart info below for reference. keep it short and reference/link to the other AGENTS.md files in the /.d-spec folder for further info
<!-- note to editor:END -->

# Beads (Execution Phase)
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

<!-- note to editor:START -->
everything below this needs to be migrated to the AGENTS.md file in the `/.d-spec` folder.
<!-- note to editor:END -->
