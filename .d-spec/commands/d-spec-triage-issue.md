---
description: Triage a request into bug fix vs proposal vs question.
argument-hint: issue-id-or-description [severity]
---

$ARGUMENTS
<!-- D-SPEC:START -->
**Guardrails**
- Default to proposal when scope or impact is unclear.
- Bug fixes restore intended behavior; proposals change behavior.
- Ask clarifying questions before classifying when ambiguous.

**Steps**
1. Summarize the request and any stated severity.
2. Determine if it is a bug fix, proposal, or question.
3. Explain the classification and required next steps.
4. If needed, use AskUserTool to clarify scope.

**Reference**
- See `.d-spec/AGENTS.md` and `.d-spec/onboarding/discovery-to-spec.md` for proposal triggers.
<!-- D-SPEC:END -->
