---
description: Audit and propose cleanup for stale ideas or changes.
argument-hint: age-days [dry-run]
---

$ARGUMENTS
<!-- D-SPEC:START -->
**Guardrails**
- Do not delete or move files without approval.
- Summarize candidates with dates and rationale.
- Prefer archiving over deletion.

**Steps**
1. Interpret age threshold and dry-run intent.
2. List stale ideas and changes with last activity.
3. Recommend archive actions and confirm before changes.
4. If approved, follow archive instructions precisely.

**Reference**
- Archiving rules are in `.d-spec/onboarding/archive-instructions.md`.
<!-- D-SPEC:END -->
