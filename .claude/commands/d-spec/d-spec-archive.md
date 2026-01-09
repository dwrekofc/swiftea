---
description: Archive a deployed d-spec change and update specs.
argument-hint: change-id
---

$ARGUMENTS
<!-- D-SPEC:START -->
**Guardrails**
- Favor straightforward, minimal implementations first and add complexity only when it is requested or clearly required.
- Keep changes tightly scoped to the requested outcome.
- Refer to `.d-spec/AGENTS.md` if you need additional d-spec conventions or clarifications.

**Steps**
1. Determine the change ID to archive:
   - If this prompt already includes a specific change ID (for example inside a `<ChangeId>` block populated by slash-command arguments), use that value after trimming whitespace.
   - If the conversation references a change loosely (for example by title or summary),  surface likely IDs, share the relevant candidates, and confirm which one the user intends.
   - Otherwise, review the conversation, and ask the user which change to archive; wait for a confirmed change ID before proceeding.
   - If you still cannot identify a single change ID, stop and tell the user you cannot archive anything yet.
2. Validate the change ID byand stop if the change is missing, already archived, or otherwise not ready to archive.


**Reference**
- Use `d-spec list` to confirm change IDs before archiving.
- Inspect refreshed specs with `d-spec list --specs` and address any validation issues before handing off.
<!-- D-SPEC:END -->
