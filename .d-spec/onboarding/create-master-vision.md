# Creating / Updating the Master Plan (North Star)

The master plan is the "north star" doc that the agent should read first during discovery.

## Location Rule

- The agent should look for the first match of: `.d-spec/*master-plan*.md`

## When To Create/Update

- Create a master plan early in a new project.
- Update it when major scope, architecture, or priorities shift.
- When the team is ready to implement, convert the vision into `.d-spec/project.md` and `.d-spec/roadmap.md` via an interview (vision doc becomes read-only).

## Vision Creation Guide

- Use `.d-spec/onboarding/vision-doc.md` as the interview guide and question bank.
- All interviews and context gathering MUST be facilitated with `AskUserTool`.
- Ask one question at a time, option-based, and wait for answers.

## Where To Save (This Repo)

Save the final vision as one of:
- `.d-spec/<projectname>-master-vision.md` (single evolving vision), or
- `.d-spec/planning/ideas/YYYY-MM-DD-vision-<slug>.md` (vision as an intake idea)
