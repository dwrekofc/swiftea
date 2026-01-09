# Defining Project Conventions & Standards (project.md)

Use this when the user wants to establish or refine project standards (coding style, UX principles, data/privacy rules, etc). This repo does **not** use `.d-spec/standards.md`; capture standards inside `.d-spec/project.md`.

## Primary Standards Doc

- Keep standards in `.d-spec/project.md` so discovery can load them quickly.

## Interview (AskUserTool)

All interviews and context gathering MUST be facilitated with `AskUserTool`.

Ask option-based questions about:
- Coding conventions (language, formatting, naming)
- Testing expectations
- Security/privacy constraints
- Compatibility constraints
- Documentation expectations

## Output Checklist

- Clear "MUST" vs "SHOULD" guidance
- Explicit non-goals
- A short "defaults" section that an agent can apply without re-interviewing
