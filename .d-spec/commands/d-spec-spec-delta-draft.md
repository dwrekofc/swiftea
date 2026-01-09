---
description: Draft a spec delta outline for a capability.
argument-hint: capability [change-id]
---

$ARGUMENTS
<!-- D-SPEC:START -->
**Guardrails**
- Do not implement code; produce spec delta structure only.
- Use ADDED/MODIFIED/REMOVED/RENAMED headers.
- Every requirement must include at least one #### Scenario.

**Steps**
1. Resolve capability and change-id from arguments.
2. Outline delta sections with placeholders for requirements.
3. Add at least one scenario placeholder per requirement.
4. Flag any missing inputs required to complete the spec.

**Reference**
- Spec delta format and scenario rules live in `.d-spec/onboarding/discovery-to-spec.md`.
<!-- D-SPEC:END -->
