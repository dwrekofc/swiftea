---
name: vision-doc
description: Conducts an interactive interview to create a Vision doc for products, features, or modules. Use when the user wants to document their product vision, plan a new feature, clarify what they want to build and why it matters, or capture high-level direction before detailed planning.
allowed-tools: AskUserQuestion, Write, Read
---

# Vision Doc Interview Skill

## Purpose

This skill guides you to interview the user to create a **Vision doc** - a living document that sits between a product features page and a full business requirements document. It captures the inspirational high-level vision for a feature, module, or product before diving into detailed planning.

## Interview Approach

- **Style**: Combine quick capture with conversational adaptive questioning
- **Tone**: Collaborative, curious, and generative
- **Flow**: Start broad to capture raw ideas, then refine and organize together
- **Questions**: Mix of open-ended prompts and structured options

## Instructions

You are conducting a Vision doc interview. Your goal is to help the user articulate their product/feature vision in a way that energizes them and provides clear direction for next steps.

### Interview Flow

#### 1. Opening Context

Start with this opening message:

"I'll help you create a Vision doc for your idea. This is all about capturing the high-level vision and vibes - we're not writing detailed requirements yet. Think of this as clarifying *what you want to build* and *why it matters* before we get into the *how*.

Let's start: What are you envisioning? Give me a quick 1-2 sentence summary, and let me know if this is a single feature, a product module, or a full product."

Then:
- Ask what they're building (scope: feature, module, or full product)
- Get a quick 1-2 sentence summary of the idea
- Set expectations: "This is about capturing the vision and vibes, not writing requirements yet"

#### 2. Quick Capture Round

Use the AskUserQuestion tool to gather high-level information across multiple dimensions at once. The user wants to build cool tools and apps for himself or small groups of users or may want to discuss a larger business application. Ask which one to start out.

**Sample quick capture questions:**

```
Question 1: "Is this a cool tool for you or a larger business application?"
- Options: Small tool, enterprise app, somewhere in the middle, skip
- Allow "Other" for custom answers
```

#### 3. Conversational Deep Dive

Based on their answers, ask adaptive follow-up questions. Probe on areas that seem underdeveloped. Help them articulate the "why" and the vision. Look for the emotional core - what gets them excited about this?


#### 4. Ideas & Vibes Capture

- Ask about inspiration, references, or analogies ("It's like X but for Y")
- What's the dream scenario? What would make this magical?
- Any specific user moments or experiences they're imagining?

#### 5. Reality Check & Next Steps

- Gently surface potential technical concerns or "dream ruiners"
- Ask if they know of existing solutions, OSS libraries, or similar products
- Identify what they need to research next (technical specs, existing tools, feasibility)

**Sample technical reality check questions:**
- "Do you know of any existing libraries or open-source projects that could help with this?"
- "What's your biggest technical concern or potential blocker?"
- "Is there anything that could make this impossible or not worth building?"

#### 6. Document Assembly

- Draft the Vision doc using the template below
- Save it to the `.d-spec` folder with naming format: `[project/product]-master-plan.md`
- Review it together and refine
- Ensure it feels inspiring and directionally clear, not overly prescriptive
- Include the Idea Overview (~700 words), Scope (in/out bullets), and Early Decisions & Integrations sections

## Vision Doc Template

Use this template to create the Vision doc markdown file. Save it to the `.d-spec` folder with naming format: `[project/product]-master-plan.md`

```markdown
# Vision: [Product/Feature Name]

> *One-sentence tagline that captures the essence*

**Status**: Draft | In Progress | Validated
**Scope**: Feature | Module | Full Product
**Created**: [Date]
**Last Updated**: [Date]

---

## The Vision

### Idea Overview
[~700 words. Explain the idea vision, capabilities, and benefits in paragraphs.]

### User Pain Points
- [Specific pain point 1]
- [Specific pain point 2]
- [etc.]

---

## The Solution

[High-level description of what you're building and how it solves the problem]

### Core Value Proposition
[What's the main benefit? Why would someone choose this?]

---
## Scope

**In Scope**:
- [What it does]
- [What it does]

**Out of Scope**:
- [What it does not do]
- [What it does not do]

## Who Is This For?

**Primary Users**:
- [User type 1]: [What they need]
- [User type 2]: [What they need]

**Use Cases**:
1. [Scenario 1]
2. [Scenario 2]
3. [Scenario 3]

---

## Core Capabilities

[What will this actually do? List the key features/capabilities without going into implementation details]

### Must-Haves (MVP)
- [ ] [Capability 1]
- [ ] [Capability 2]
- [ ] [Capability 3]

### Nice-to-Haves (Future)
- [ ] [Capability 4]
- [ ] [Capability 5]

## Modules & features
[organize the full scope and breadth of features provided at the time by the user into modules. seek user approval to confirm correctness and completeness]

---

## Ideas & Vibes

### Inspiration & References
[Products, tools, or experiences that inspire this. What do you want to emulate or avoid?]

### Dream Scenario
[If everything goes perfectly, what does this look like in 6-12 months? Paint the picture.]

### Key Moments
[Specific user interactions or experiences that would feel magical]

---

## Technical Considerations

### Known Constraints
- [Technical limitation 1]
- [Technical limitation 2]

### Potential Dream Ruiners
- [Concern 1]: [Why this could be a blocker]
- [Concern 2]: [Why this could be a blocker]

### Existing Solutions/Dependencies to Evaluate
- [OSS library/tool 1]: [What it does, why it might help]
- [OSS library/tool 2]: [What it does, why it might help]
- [Competitor/similar product]: [What to learn from it]

---

## Early Decisions & Integrations (Subject to Change)

### Architecture (Early Ideas)
- [Decision/idea]
- [Decision/idea]

### Technical Standards
- [Standard or guideline]
- [Standard or guideline]

### Dependencies
- [Library/service]
- [Library/service]

### Integrations
- [External system or API]
- [External system or API]

---
## Roadmap
[take the modules and features and map out the potential implementation phases into a roadmap of which features to build and in what order]

---

## Next Steps

### Research Needed
- [ ] [Technical research item 1]
- [ ] [Technical research item 2]
- [ ] [User research or validation needed]

### Open Questions
- [Question 1]
- [Question 2]

### When to Revisit This Doc
[Define triggers for when you should come back and update this vision - e.g., after user feedback, technical spike, prototype testing]

---

## Notes & Evolution

[Free-form section for capturing thoughts, learnings, and how the vision changes over time]

- **[Date]**: [Note about what changed or what you learned]
```

## Best Practices

1. **Don't rush**: Give space for thinking. If they say "I'm not sure," offer options or examples.
2. **Embrace messiness**: First draft can be rough. Help organize later.
3. **Find the emotion**: The best visions have an emotional core. Help them find what excites them.
4. **Be realistic but not pessimistic**: Surface concerns, but don't kill the dream prematurely.
5. **Make it actionable**: End with clear next steps so they know what to do after this conversation.
6. **Save to inbox**: Always save the completed Vision doc to `0-inbox/vision-[product-name].md` in the Obsidian vault.
