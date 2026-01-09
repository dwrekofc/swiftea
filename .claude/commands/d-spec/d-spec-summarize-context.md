---
description: Summarize current repo context for a given area or path.
argument-hint: area-or-path [verbosity]
---

$ARGUMENTS
<!-- D-SPEC:START -->
**Guardrails**
- Keep summary factual and grounded in current files.
- Call out unknowns and ask for clarification when needed.
- Prefer concise output unless verbosity is requested.

**Steps**
1. Identify the target area or path from arguments.
2. Review relevant docs and files to build a short, accurate summary.
3. List key decisions, open questions, and constraints.
4. Suggest the next logical action (clarify, plan, or implement).

**Reference**
- Use `.d-spec/project.md` and `.d-spec/*master-plan*.md` as primary context when applicable.
<!-- D-SPEC:END -->
