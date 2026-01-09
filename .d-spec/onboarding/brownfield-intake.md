# Brownfield Intake (Existing Ideas / Specs / Changes)

Use this workflow when the repo already contains existing docs, partial specs, or active d-spec changes and the user wants to “process what’s here” into the standard Discovery → d-spec → Beads workflow.

## Goals

- Establish a clear distinction between **incoming ideas** and **in-flight changes**.
- Avoid duplicating capabilities or creating conflicting d-spec changes.
- Preserve traceability from old docs to d-spec change-ids and Beads epics.

## Sources To Scan (in order)

1. North star: `.d-spec/*master-plan*.md`
2. Project conventions & standards: `.d-spec/project.md` (and any other `.d-spec/*.md` referenced by the master plan)
3. Intake ideas: `.d-spec/planning/ideas/*.md`
4. Archived ideas: `.d-spec/planning/ideas/archive/*.md` (for context only; do not resurrect without asking)
5. d-spec changes in flight: `.d-spec/planning/changes/`
6. Archived d-spec changes: `.d-spec/planning/archive/`
7. Legacy markdown outside `.d-spec/` (if present): treat as untriaged intake and reconcile into `.d-spec/planning/ideas/` or `.d-spec/planning/ideas/archive/` with the user

If any step requires clarification or prioritization, use `AskUserTool` (mandatory).

## Categorize What You Find

For each non-d-spec doc discovered, assign one label:
- **Idea (untriaged)**: a concept, wishlist, or rough spec → keep in `.d-spec/planning/ideas/`
- **Decision record**: architectural/conventions decision → incorporate into master plan or project.md
- **Partial spec**: requirements-like content → likely becomes a d-spec change draft
- **Historical**: no longer active → archive (or keep archived)

## Brownfield Decision Rules (avoid conflicts)

### A) Existing d-spec change overlaps an idea

If a chosen idea overlaps an existing folder under `.d-spec/planning/changes/`, surface the overlap and ask the user what to do (case-by-case) using `AskUserTool`:
- Update the existing change
- Create a new change and cross-link
- Defer the idea

### B) Existing archived change already covers the idea

If the idea is already covered by an archived change under `.d-spec/planning/archive/`:
- If the user wants to improve/extend behavior, draft a new d-spec change (do not edit archived files directly).
- If it is a true bug fix restoring specified behavior, ask whether to skip a proposal or create a fast change.

### C) “Partial spec” docs in `.d-spec/planning/ideas/`

If a doc reads like requirements/scenarios but isn’t in d-spec format:
- Treat it as intake.
- Convert into a d-spec change draft using the standard workflow (`.d-spec/onboarding/discovery-to-spec.md`), keeping the original doc as the source reference until approval.

## Processing Existing Idea Docs (YAML retrofit on-touch)

If an existing `.d-spec/planning/ideas/*.md` lacks YAML frontmatter:
- Only add the minimal YAML keys when the idea is selected to be processed (on-touch).
- Use the keys defined in `.d-spec/onboarding/create-ideas.md`.

## Output (per selected idea)

Once the user picks an idea to process, switch to `.d-spec/onboarding/discovery-to-spec.md` and produce:
- d-spec change draft under `.d-spec/planning/changes/<change-id>/`
- `d-spec validate <change-id> --strict` passing
- Chat approval gate before Beads creation
- After approval: archive the idea with YAML traceability (`.d-spec/onboarding/archive-instructions.md`)
