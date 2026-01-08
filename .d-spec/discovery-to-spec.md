# Discovery → OpenSpec → Beads (Combined Workflow)

This doc is the detailed procedure behind the "Discovery → Spec → Beads → Implement" section in `AGENTS.md`.

## Triggers

Use this workflow when the user asks for a workflow, proposal, spec, plan, or to turn ideas into implementation tasks.

## Inputs

- North star (read first): `docs/*master-plan*.md`
- Intake ideas: `docs/ideas/*.md`
- Existing OpenSpec: `openspec/specs/`
- Existing changes: `openspec/changes/`

## Outputs

- OpenSpec change: `openspec/changes/<change-id>/...`
- Beads epic + tasks (only after chat approval)
- Archived idea doc with YAML traceability (only after chat approval)

## Workflow

### 1) Discovery (read-only)

1. Read the master plan doc in `docs/` (first match for `*master-plan*.md`).
2. Enumerate idea docs in `docs/ideas/` and select 3–5 candidate ideas to summarize.
3. Summarize candidates and ask the user to pick which one to process next.

Notes:
- Prefer `rg --files -g'*.md'` for enumeration and `rg -n "TODO|FIXME|NEEDS"` for gaps.
- If the chosen idea overlaps an existing change in `openspec/changes/`, surface the overlap and ask the user to decide case-by-case.

### 2) Interview (clarify scope)

Use `AskUserTool` for all user interviews and context gathering:
- Ask one question at a time
- Provide 2–4 concrete options with tradeoffs
- Stop and wait for the answer

Target questions:
- scope boundaries (in/out)
- priority ordering
- breaking changes and migrations
- impacted capabilities (multi-cap allowed)

### 3) Draft OpenSpec change (no Beads yet)

1. Choose a verb-led, date-stamped change id: `<verb>-<slug>-YYYY-MM-DD`.
2. Scaffold:
   - `openspec/changes/<change-id>/proposal.md`
   - `openspec/changes/<change-id>/tasks.md` (mid-detail)
   - `openspec/changes/<change-id>/specs/<capability>/spec.md` deltas (one per impacted capability)
3. Ensure each new/modified requirement includes at least one scenario.
4. Run: `openspec validate <change-id> --strict` and fix issues.

Approval gate:
- Do not generate Beads issues or start implementation until the user approves the proposal in chat.

### 4) After chat approval

1. Archive the processed idea doc (see `.d-spec/archive-instructions.md`).
2. Create Beads epic + tasks from `openspec/changes/<change-id>/tasks.md`.
3. Add traceability:
   - Add `Beads: <epic-id>` to `openspec/changes/<change-id>/proposal.md`
   - Fill `beads_epic_id` in the archived idea doc YAML header
