# Creating / Updating the Master Plan (North Star)

The master plan is the "north star" doc that the agent should read first during discovery.

## Location Rule

- The agent should look for the first match of: `docs/*master-plan*.md`

## When To Create/Update

- Create a master plan early in a new project.
- Update it when major scope, architecture, or priorities shift.

## Inputs

- Vision doc workflow: `.d-spec/create-vision.md`
- Standards: `.d-spec/create-standards.md`
- Existing OpenSpec truth: `openspec/specs/`

## Interview (AskUserTool)

All interviews and context gathering MUST be facilitated with `AskUserTool`.

Use the interview to pin down:
- Purpose and non-goals
- Modules/capabilities (and near-term focus)
- Constraints (platform, privacy, permissions)
- North-star priorities for the next 1–3 milestones

## Suggested Outline

Keep the master plan concise and stable:
- Purpose / goals / non-goals
- Architecture overview (high level)
- Constraints (must not violate)
- Current focus (next milestone)
- References (links to key specs and standards)
