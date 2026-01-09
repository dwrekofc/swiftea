---
description: Run a structured requirements interview using AskUserTool.
argument-hint: topic [audience] [depth]
---

$ARGUMENTS
<!-- D-SPEC:START -->
**Guardrails**
- Use AskUserTool for all interview questions.
- Ask one question at a time with 2-4 concrete options and tradeoffs.
- Stop after each question and wait for the answer.
- Do not propose solutions until requirements are clear.

**Steps**
1. Summarize the topic, audience, and depth from the arguments.
2. Scan current docs to ground questions in existing context.
3. Ask the first question with clear options and tradeoffs.
4. Continue one question at a time until scope and success criteria are clear.

**Reference**
- See `.d-spec/AGENTS.md` for interview triggers and workflow placement.
<!-- D-SPEC:END -->
