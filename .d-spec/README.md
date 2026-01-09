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
