---
description: Create Beads issues from an approved d-spec proposal and specs.
argument-hint: change-id
---

$ARGUMENTS
<!-- D-SPEC:START -->
**Guardrails**
- Do not create Beads issues until the proposal is approved in chat.
- Read all required documents before creating Beads issues.
- Beads is the execution source of truth after creation.

**Steps**
1. Confirm chat approval for the change-id.
2. Read required docs:
   - `.d-spec/project.md`
   - `.d-spec/planning/changes/<change-id>/proposal.md`
   - `.d-spec/planning/changes/<change-id>/design.md` (if present)
   - `.d-spec/planning/changes/<change-id>/specs/**/spec.md`
   - `.d-spec/planning/changes/<change-id>/tasks.md`
3. Create a detailed Beads epic + tasks per `bd prime` with clear descriptions and acceptance criteria.
4. Add `Beads: <epic-id>` to `.d-spec/planning/changes/<change-id>/proposal.md`.
5. Archive the related idea doc with YAML traceability after Beads creation.
6. Freeze d-spec: do not update change docs during implementation.

**Reference**
- See `.d-spec/onboarding/discovery-to-spec.md` for Beads prereads and the task template.
- See `.d-spec/onboarding/archive-instructions.md` for idea archiving rules.
<!-- D-SPEC:END -->
