# Project Setup (Ideation Docs Structure)

Use this workflow when bootstrapping a project (or standardizing an existing one) for the ideation → d-spec → Beads process.

All user interviews and context gathering MUST be facilitated with `AskUserTool`.

## Target Structure

Create (or confirm) the following:

- `.d-spec/` (planning + project conventions)
  - `.d-spec/*master-plan*.md` (north star; agent reads first)
  - `.d-spec/project.md` (project conventions)
  - `.d-spec/roadmap.md` (optional but preferred)
  - `.d-spec/planning/ideas/` (intake ideas and half-formed specs)
  - `.d-spec/planning/ideas/archive/` (processed ideas; archived after approval)
  - `.d-spec/planning/changes/` (change proposals)
  - `.d-spec/planning/archive/` (archived changes)

Canonical layout (diagram):

```
AGENTS.md
requirements.txt
.d-spec/
├── AGENTS.md
├── master-plan.md              # Overarching product vision and direction
├── project.md                  # Project conventions & standards
├── README.md                   
├── roadmap.md                  # 
├── commands/                   # Agent prompts/commands
├── onboarding/                 # d-spec workflow instructions
└── planning/
    ├── specs/                  # Current truth - what IS built
    │   └── [capability]/       # Single focused capability
    │       ├── spec.md         # Requirements and scenarios
    │           └── design.md   # Technical patterns
    ├── changes/                # Proposals - what SHOULD change
    │   ├── [change-name]/
    │   │   ├── proposal.md     # Why, what, impact
    │   │   ├── tasks.md        # Implementation checklist
    │   │   ├── design.md       # Technical decisions (optional; see criteria)
    │   │   └── specs/          # Delta changes
    │   │       └── [capability]/
    │   │           └── spec.md # ADDED/MODIFIED/REMOVED
    │   └── archive/            # Completed changes
    └── ideas/                  # New ideation, not ready for proposals
        └── archive/            # Completed or discarded ideas
```


## Setup Steps

1. **Create folders**: ensure `.d-spec/planning/ideas/`, `.d-spec/planning/ideas/archive/`, `.d-spec/planning/changes/`, and `.d-spec/planning/archive/` exist.
2. **Create/choose master plan (vision)**:
   - Ensure one file in `.d-spec/` contains `master-plan` in the filename.
   - Keep it concise and stable (see `.d-spec/onboarding/create-master-vision.md`).
3. **Convert vision → project conventions + roadmap (when ready to implement)**:
   - Interview the user and convert the vision doc into `.d-spec/project.md` (app folder structure, architecture, tech stack, etc.) and `.d-spec/roadmap.md`.
   - Use `.d-spec/project.md` as the example for conventions and formatting.
   - After conversion, the vision doc is read-only.
4. **Create project conventions & standards**:
   - Ensure `.d-spec/project.md` captures conventions and standards (see `.d-spec/onboarding/create-standards.md`).
5. **Set idea intake conventions**:
   - New idea docs go in `.d-spec/planning/ideas/` with filename `YYYY-MM-DD-<verb>-<slug>.md`.
   - Use the minimal YAML frontmatter (see `.d-spec/onboarding/create-ideas.md`).
   - Add new ideas to `.d-spec/roadmap.md` as potential changes.
6. **Reconcile legacy markdown (if any)**:
   - If there are root-level or miscellaneous markdown docs, use `AskUserTool` to decide whether each is:
     - a new idea → move into `.d-spec/planning/ideas/`
     - historical → move into `.d-spec/planning/ideas/archive/`
     - project conventions/master-plan content → merge into the canonical doc

## Exit Criteria

- Master plan is discoverable via `.d-spec/*master-plan*.md`
- Vision has been converted into `.d-spec/project.md` and `.d-spec/roadmap.md` when the team is ready to implement
- Idea intake location and naming is established (`.d-spec/planning/ideas/`)
- Archive location exists (`.d-spec/planning/ideas/archive/`)
- Project Conventions exist (`.d-spec/project.md`)
