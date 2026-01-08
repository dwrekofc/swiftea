# Creating a Vision Doc

Use this when the user wants to capture the high-level vision for a new product, module, or major feature before writing OpenSpec requirements.

## Interview Guide

- Use `.claude/vision-doc/SKILL.md` as the interview guide and question bank.
- All interviews and context gathering MUST be facilitated with `AskUserTool`.
- Ask one question at a time, option-based, and wait for answers.

## Where To Save (This Repo)

Save the final vision as one of:
- `docs/vision.md` (single evolving vision), or
- `docs/ideas/YYYY-MM-DD-vision-<slug>.md` (vision as an intake idea)

Choose based on what the user wants to treat as canonical.

## What Happens Next

- Convert deliverables into idea docs in `docs/ideas/` (see `.d-spec/create-ideas.md`).
- Pick the next idea to process into an OpenSpec change (see `.d-spec/discovery-to-spec.md`).
