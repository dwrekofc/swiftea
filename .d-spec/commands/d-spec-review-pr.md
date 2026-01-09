---
description: Run a structured PR review checklist.
argument-hint: pr-id [priority] [owner]
---

$ARGUMENTS
<!-- D-SPEC:START -->
**Guardrails**
- Focus on correctness, regressions, and test coverage first.
- Call out risks and missing validation explicitly.
- Keep feedback actionable and scoped.

**Steps**
1. Identify PR scope and relevant specs or tasks.
2. Review for correctness, security, and edge cases.
3. Verify tests and update gaps.
4. Provide a clear approve/block recommendation.

**Reference**
- Use `.d-spec/project.md` for conventions if needed.
<!-- D-SPEC:END -->
