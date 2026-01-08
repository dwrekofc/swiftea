**ClaudEA Design Standards**

# Core Principles

## LLM & Human Compatible Artifacts and Primitives
**Files over apps, code over UI**
- Plain text
- Markdown (.md) files
- JSON
- SQLite (file-based database)
- Bash scripts for glue code

Everything should be inspectable in a text editor, versionable in git, and portable across systems. No proprietary formats, no black boxes.

## Open Source Dependencies
Prefer open source packages, libraries, and dependencies for everything we control. (The AI intelligence layer is necessarily closed source, but all other tooling should be OSS where practical.)

## Preferred Languages
- HTML/CSS
- Javascript/Typescript
- Python
- Bash (for CLI glue code and terminal automation)

## Deterministic over Probabilistic
**Maxim**: When possible, prefer predictability over flexibility
- Scripts over prompts (when the logic is clear)
- Workflows over agents (when the process is defined)
- Executables with args over raw API calls (when the interface is stable)

**Progressive enhancement**: Start with simple scripts, add workflows for orchestration, escalate to AI agents only where you need reasoning and flexibility.

## CLI over UI
Terminal-based, scriptable, automation-friendly. The command line is the universal interoperability layer.

**Designed for lowest common denominator**: Bash + file I/O + prompts are universal across all coding agent CLI harnesses (Claude Code, Gemini CLI, Codex CLI, etc.). Ergonomics vary, but fundamentals work everywhere.

## Composability over Monoliths
Small, single-purpose scripts and agents that chain together. Build systems from reusable components rather than large all-in-one solutions.

## Data Layer Simplicity
The foundation stays simple and portable throughout: markdown for notes, SQLite for structured data, JSON for interchange. This layer never depends on complex tooling or proprietary systems.

---

**Philosophy**: ClaudEA is a progressively enhanced system. The data layer (markdown, SQLite, JSON) remains simple and universal. Scripts handle deterministic operations. Workflows orchestrate multi-step processes. AI agents provide reasoning and flexibility only where needed. Each layer builds on the previous without replacing it.
