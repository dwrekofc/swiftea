---
description: Propose a test matrix for a feature or change.
argument-hint: feature [platforms]
---

$ARGUMENTS
<!-- D-SPEC:START -->
**Guardrails**
- Prioritize critical paths and regressions.
- Keep the matrix minimal unless high risk is stated.
- Tie tests to observable outcomes and specs.

**Steps**
1. Identify the feature scope and target platforms.
2. List critical paths, edge cases, and failure modes.
3. Map each to test types (unit/integration/e2e/manual).
4. Ask for confirmation or constraints.

**Reference**
- Use relevant spec deltas in `.d-spec/planning/changes/` to derive scenarios.
<!-- D-SPEC:END -->
