# Archiving Processed Ideas

Archive the selected idea doc after the user approves the related d-spec proposal in chat **and** after the Beads epic is created (so `beads_epic_id` is available).

## When To Archive

- Archive after **proposal approval** (chat approval gate) and Beads epic creation, not at draft time.

## Where To Archive

- Move: `.d-spec/planning/ideas/<idea>.md` → `.d-spec/planning/ideas/archive/<idea>.md`

## What To Add (YAML Header)

Prepend (or insert) a YAML frontmatter block at the top of the archived idea doc:

```yaml
---
processed_date: YYYY-MM-DD
d-spec_change_id: <change-id>
beads_epic_id: <epic-id>
decision_summary:
  - <short decision>
  - <short decision>
---
```

Guidelines:
- Keep `decision_summary` to 2–5 short bullets.
- Do not rewrite the body content unless you are fixing factual errors.
- If the idea doc already has YAML frontmatter, merge these keys into the existing frontmatter.
