# Phase 1: Agent-Readiness Foundation - Context

**Gathered:** 2026-01-16
**Status:** Ready for planning

<vision>
## How This Should Work

ClaudEA operates SwiftEA through multi-step workflows — chaining commands together, building on results. Search finds messages, then read one, then export it. It's not fire-and-forget; it's a conversation where each response informs the next action.

The interaction pattern is **state-aware and guided**:
- ClaudEA can inspect system state to know what's possible ("what can I do right now?")
- Each response includes guidance on what makes sense next — breadcrumbs through valid paths
- When errors happen, the response explains exactly what went wrong and how to fix it

**Critical UX insight:** Outputs must be readable by both humans AND AI agents without post-processing. The default format is **markdown** — clean headers, sections, line breaks, code blocks. JSON is available via `--json` flag when structured parsing is needed, but it's the escape hatch, not the default.

</vision>

<essential>
## What Must Be Nailed

All three are interdependent — can't have one without the others:

- **Output readability** — Markdown by default, JSON on demand. Every command produces output a human can scan AND an AI can reason about without parsing gymnastics.
- **Error recovery** — When things fail, ClaudEA knows exactly what went wrong (error codes) and how to fix it (actionable recovery hints).
- **State inspection** — ClaudEA can always ask "what's the current state?" and get a clear answer about what operations are valid next.

</essential>

<specifics>
## Specific Ideas

**Output format model (hybrid gh + kubectl):**
- **List commands:** Tables (like `gh pr list`) — scannable at a glance
- **Detail commands:** Hierarchical key:value with sections (like `kubectl describe`) — structured for complex state
- **Events/history:** At the bottom of detail views, showing what happened and why
- **`--json` flag:** Full structured output for machine parsing when needed

**Testing requirements from agent-ux-audit:**
1. **Synthetic Agent Simulator** — Script that calls SwiftEA as an agent would, parses outputs, validates schemas, retries using recovery hints, measures success rate/token usage/retry count
2. **Non-Interactive Validation** — All commands work with `--non-interactive --json`, no STDIN reads, no ANSI color codes in JSON mode
3. **Error Recovery Testing** — Trigger each error code deliberately, verify recovery hints are actionable

**Documentation requirements from agent-ux-audit:**
1. **OpenAPI/JSON Schema Spec** — Every command's JSON output schema documented, error codes and recovery hints included
2. **Error Code Reference** — Comprehensive list of all ERR_* codes with cause, recovery hint, retry policy
3. **State Machine Diagrams** — Valid command sequences documented (e.g., "Must run sync before search")

</specifics>

<notes>
## Additional Context

The core philosophy is **delegation, not assistance** — SwiftEA should be something ClaudEA can operate autonomously, only escalating what truly requires human judgment.

The agent-readiness score target: 2/10 → 9/10. This phase transforms SwiftEA from a human-centric CLI into a first-class agent interface.

</notes>

---

*Phase: 01-agent-readiness-foundation*
*Context gathered: 2026-01-16*
