---
description: Run a validation checklist for a d-spec change.
argument-hint: change-id [strict|soft]
---

$ARGUMENTS
<!-- D-SPEC:START -->
**Guardrails**
- Do not edit files unless explicitly requested.
- Prefer `d-spec validate <id> --strict` when strict is specified.
- Surface failures clearly with paths and next actions.

**Steps**
1. Read the change-id and validation mode from arguments.
3. Report failures with concrete fixes.
4. Confirm pass state or ask for approval to fix issues.

**Reference**
- Validation checklist and common failures are in `.d-spec/onboarding/discovery-to-spec.md`.
<!-- D-SPEC:END -->
