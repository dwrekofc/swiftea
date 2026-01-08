# Creating Idea Docs (`docs/ideas/`)

Use this workflow when the user wants to capture a new idea (small feature → whole module).

## File Naming

Create new idea files as:
- `docs/ideas/YYYY-MM-DD-<verb>-<slug>.md`

Example:
- `docs/ideas/2026-01-07-add-mail-rules.md`

## Required YAML Frontmatter (Minimal)

```yaml
---
title: <human title>
area: <short area, e.g. mail|calendar|core|docs>
status: draft|needs-info|ready|in-spec|archived
created: YYYY-MM-DD
---
```

## Interview (AskUserTool)

All interviews and context gathering MUST be facilitated with `AskUserTool`.

Ask one question at a time with concrete options and tradeoffs. Stop and wait after each answer.

Suggested question sequence:
1. **Goal**: what problem is being solved and for whom?
2. **Scope**: what is explicitly in/out for the first iteration?
3. **Constraints**: performance, permissions, privacy, compatibility.
4. **Success**: what does "done" look like (user-visible)?
5. **Risks**: biggest unknowns / what would make you abandon it?

## Body Template (Optional)

Use headings if helpful, but keep it lightweight:

```markdown
## Why

## What

## Scope

## Open Questions
```

## Notes

- For existing idea docs, retrofit YAML frontmatter only when the doc is chosen to be processed (on-touch).
