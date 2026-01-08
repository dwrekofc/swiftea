# Project Setup (Ideation Docs Structure)

Use this workflow when bootstrapping a project (or standardizing an existing one) for the ideation → OpenSpec → Beads process.

All user interviews and context gathering MUST be facilitated with `AskUserTool`.

## Target Structure

Create (or confirm) the following:

- `docs/` (human-facing planning and ideation)
  - `docs/ideas/` (intake ideas and half-formed specs)
  - `docs/archive/` (processed ideas; archived after proposal approval)
  - `docs/*master-plan*.md` (north star; agent reads first)
  - `docs/standards.md` (project standards)
  - optional: `docs/roadmap.md`, `docs/vision.md`

OpenSpec remains the system of record for requirements:
- `openspec/specs/` (truth)
- `openspec/changes/` (proposals)

## Setup Steps

1. **Create folders**: ensure `docs/ideas/` and `docs/archive/` exist.
2. **Create/choose master plan**:
   - Ensure one file in `docs/` contains `master-plan` in the filename.
   - Keep it concise and stable (see `.d-spec/create-master-plan.md`).
3. **Create standards**:
   - Ensure `docs/standards.md` exists and contains defaults an agent can apply (see `.d-spec/create-standards.md`).
4. **Set idea intake conventions**:
   - New idea docs go in `docs/ideas/` with filename `YYYY-MM-DD-<verb>-<slug>.md`.
   - Use the minimal YAML frontmatter (see `.d-spec/create-ideas.md`).
5. **Reconcile legacy markdown (if any)**:
   - If there are root-level or miscellaneous markdown docs, use `AskUserTool` to decide whether each is:
     - a new idea → move into `docs/ideas/`
     - historical → move into `docs/archive/`
     - standards/master-plan content → merge into the canonical doc

## Exit Criteria

- Master plan is discoverable via `docs/*master-plan*.md`
- Idea intake location and naming is established (`docs/ideas/`)
- Archive location exists (`docs/archive/`)
- Standards exist (`docs/standards.md`)
- Team understands that OpenSpec is the requirements truth (`openspec/specs/`)
