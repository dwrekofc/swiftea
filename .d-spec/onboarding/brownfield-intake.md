# Brownfield Intake (Existing Ideas / Specs / Changes)

Use this workflow when the repo already contains existing docs, partial specs, or active OpenSpec changes and the user wants to “process what’s here” into the standard Discovery → OpenSpec → Beads workflow.

## Goals

- Establish a clear “current truth” (OpenSpec specs) vs “incoming work” (idea docs).
- Avoid duplicating capabilities or creating conflicting OpenSpec changes.
- Preserve traceability from old docs to OpenSpec change-ids and Beads epics.

## Sources To Scan (in order)

1. North star: `docs/*master-plan*.md`
2. Standards: `docs/standards.md` (and any other `docs/*.md` referenced by the master plan)
3. Intake ideas: `docs/ideas/*.md`
4. Archived ideas: `docs/archive/*.md` (for context only; do not resurrect without asking)
5. OpenSpec truth: `openspec/specs/`
6. OpenSpec proposals in flight: `openspec/changes/`
7. Legacy markdown outside `docs/` (if present): treat as untriaged intake and reconcile into `docs/ideas/` or `docs/archive/` with the user

If any step requires clarification or prioritization, use `AskUserTool` (mandatory).

## Categorize What You Find

For each non-OpenSpec doc discovered, assign one label:
- **Idea (untriaged)**: a concept, wishlist, or rough spec → keep in `docs/ideas/`
- **Decision record**: architectural/standards decision → incorporate into master plan or standards
- **Partial spec**: requirements-like content → likely becomes an OpenSpec change draft
- **Historical**: no longer active → archive (or keep archived)

## Brownfield Decision Rules (avoid conflicts)

### A) Existing OpenSpec change overlaps an idea

If a chosen idea overlaps an existing folder under `openspec/changes/`, surface the overlap and ask the user what to do (case-by-case) using `AskUserTool`:
- Update the existing change
- Create a new change and cross-link
- Defer the idea

### B) Existing OpenSpec spec already covers the idea

If the idea is already covered by `openspec/specs/<capability>/spec.md`:
- If the user wants to improve/extend behavior, draft a new OpenSpec change (do not edit truth directly).
- If it is a true bug fix restoring specified behavior, follow `openspec/AGENTS.md` guidance (may not require a proposal). If unsure, ask using `AskUserTool`.

### C) “Partial spec” docs in `docs/ideas/`

If a doc reads like requirements/scenarios but isn’t in OpenSpec format:
- Treat it as intake.
- Convert into an OpenSpec change draft using the standard workflow (`.d-spec/discovery-to-spec.md`), keeping the original doc as the source reference until approval.

## Processing Existing Idea Docs (YAML retrofit on-touch)

If an existing `docs/ideas/*.md` lacks YAML frontmatter:
- Only add the minimal YAML keys when the idea is selected to be processed (on-touch).
- Use the keys defined in `.d-spec/create-ideas.md`.

## Output (per selected idea)

Once the user picks an idea to process, switch to `.d-spec/discovery-to-spec.md` and produce:
- OpenSpec change draft under `openspec/changes/<change-id>/`
- `openspec validate <change-id> --strict` passing
- Chat approval gate before Beads creation
- After approval: archive the idea with YAML traceability (`.d-spec/archive-instructions.md`)
