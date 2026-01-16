---
type: context
status: reference
role: Describes the broader ClaudEA ecosystem that SwiftEA serves
created: 2026-01-08
last_updated: 2026-01-09
---

# Context: ClaudEA + SwiftEA Ecosystem

> *An AI executive assistant that manages your knowledge work so you can focus on what matters*

**Scope**: Full Product Ecosystem (upstream context for SwiftEA)

> **Note**: This document provides upstream context for the SwiftEA CLI toolkit. For SwiftEA-specific goals and architecture, see [swiftea-architecture-master-plan.md](./swiftea-architecture-master-plan.md).

---

## Vision Goals

### Core Goals (Primary Drivers)

#### VG-1: Unified Knowledge Graph
Query across email, calendar, contacts, tasks, and notes in one interface. All personal data connected and searchable. No more fragmented silos.

#### VG-2: Delegation Not Assistance
The agent MANAGES your systems (task manager, inbox triage, dashboards). You manage by exception—stepping in only for decisions requiring human judgment. You manage the agent; the agent manages the system.

#### VG-3: Never Lose Context
Everything is connected in a queryable knowledge graph. No information falls through the cracks. Context persists across sessions and tools. "What am I forgetting?" always has an answer.

### Supporting Goals (Enabling Principles)

#### VG-5: Data Sovereignty
Own your data in open formats (markdown, SQLite, JSON). No vendor lock-in. Everything inspectable, portable, and under your control.

#### VG-6: Progressive Automation
Start with scripts, add workflows, escalate to AI agents only where reasoning is needed. Deterministic over probabilistic. Build confidence before complexity.

#### VG-7: Composable Tools
Small CLI tools that chain together (Unix philosophy). Build systems from reusable components. Each piece inspectable and replaceable.

#### VG-8: Obsidian as Home Base
The markdown vault is the human interface. Agent reads vault for context, writes digests and dashboards there. Bidirectional sync. Your notes are the source of truth for human-readable knowledge.

---

## The Vision

### Idea Overview

ClaudEA is a personal AI executive assistant that doesn't just help you work—it works *for* you. Built on the principle of **management by exception**, ClaudEA handles the cognitive overhead of knowledge work autonomously: triaging your inbox, tracking your commitments, surfacing what you're forgetting, and keeping you in flow. You step in only for decisions that require human judgment.

The foundation of this vision is **SwiftEA**, a Swift-based CLI tool that provides programmatic access to your macOS personal information management (PIM) data—email, calendar, contacts, and eventually tasks and notes. SwiftEA liberates your data from Apple's siloed apps and makes it queryable, searchable, and actionable via the command line.

But SwiftEA is just the data layer. The magic happens when Claude Code—running in your terminal, Obsidian vault, or IDE—acts as the intelligent agent that orchestrates across all your information. Claude reads your emails, understands your calendar, knows your relationships, and manages a task system you never have to look at directly. You interact in natural language; Claude handles the rest.

This is **cognitive offload** in practice. Instead of context-switching between Mail, Calendar, Reminders, and your notes app, you ask: "What do I need to handle today?" Claude queries SwiftEA, consults your Obsidian vault, checks the task database, and gives you a prioritized answer. You never lose context because everything is connected in a unified knowledge graph that Claude can traverse.

The system is designed around the **Unix philosophy**: small, composable CLI tools that do one thing well. SwiftEA reads from Apple's databases. A task manager CLI stores work in SQLite. Obsidian holds your markdown notes. Claude is the orchestration layer that ties them together. Each piece is inspectable, portable, and replaceable.

For you, this means **speed and flow**. Commands execute instantly. There's no web UI to load, no app to switch to. You stay in the terminal or your editor, and Claude brings the information to you. Offline-first means the core system works without internet. Local-first means you own your data—it lives in SQLite and markdown on your Mac, not in someone else's cloud.

The long-term ambition is an open-source project that others can adopt and extend. But first, it needs to be battle-tested on the hardest customer: you.

### User Pain Points

- **Fragmented information**: Email in Mail, events in Calendar, tasks in Reminders, notes in Obsidian—context is scattered across apps with no unified search or linking
- **Cognitive overload**: Too many inboxes, too many tabs, too many things to remember; the mental overhead of tracking it all is exhausting
- **Reactive workflows**: You're always responding to what's in front of you rather than proactively managing priorities
- **Context loss across AI sessions**: Claude forgets what you discussed yesterday; each conversation starts from scratch
- **GUI friction**: Clicking through apps and menus breaks flow; the terminal is faster but doesn't have access to your data
- **Vendor lock-in**: Your data is trapped in proprietary formats and apps you don't control

---

## The Solution

ClaudEA + SwiftEA creates an **AI-managed knowledge work system** where:

1. **SwiftEA** extracts and mirrors your macOS PIM data (mail, calendar, contacts) into a local libSQL database with full-text search
2. **A task manager CLI** (to be built) stores tasks and projects in SQLite, managed entirely by the agent
3. **Obsidian** serves as your markdown knowledge base for notes, documents, and agent-generated outputs
4. **Claude Code** acts as the intelligent agent that orchestrates across all data sources, executing commands and surfacing insights

### Core Value Proposition

**Delegation, not assistance.** Traditional AI assistants help you do work. ClaudEA does the work for you—triaging, organizing, reminding, drafting—and only escalates what requires your judgment. You manage the agent; the agent manages the system.

---

## Scope

**In Scope**:
- SwiftEA: CLI access to Apple Mail, Calendar, Contacts with export to markdown/JSON
- Task manager CLI: Agent-managed task/project tracking in SQLite
- Obsidian integration: Bidirectional sync between agent and vault
- Unified search: Query across email, calendar, contacts, tasks, notes
- Cross-module linking: Connect related items across data types
- AI-powered triage: Inbox processing, priority scoring, smart categorization
- Natural language interface: Ask questions, give instructions in plain English
- Offline-first: Core functionality works without internet
- Local-first: All data stored locally, no cloud dependency

**Out of Scope**:
- Replacing native macOS apps (Mail.app stays, SwiftEA reads from it)
- GUI applications (CLI and markdown only)
- Cloud sync or multi-device (macOS single machine for now)
- Cross-platform support (macOS only, leveraging Apple ecosystem)
- Real-time collaboration (single-user system)

---

## Who Is This For?

**Primary Users**:
- **You (the builder)**: Power user who lives in the terminal, manages complex knowledge work, wants AI augmentation without GUI overhead
- **Technical professionals**: Developers, architects, consultants who need to manage email, meetings, and projects efficiently
- **Knowledge workers**: Anyone overwhelmed by information volume who wants proactive AI assistance

**Use Cases**:
1. **Morning briefing**: "What do I need to handle today?" → prioritized list across email, calendar, tasks
2. **Email triage**: Agent processes inbox, archives low-priority, flags urgent, drafts responses
3. **Meeting prep**: "Brief me on my 2pm" → attendee context, related emails, action items from last meeting
4. **Relationship context**: "What's my history with Alice?" → all emails, meetings, notes about/with Alice
5. **Task delegation**: "Remind me to follow up on the proposal next week" → agent creates task, manages it
6. **Context recovery**: "What was I working on with Project X?" → full context from emails, notes, tasks
7. **Draft composition**: "Draft a reply to Bob's email about the budget" → contextual draft

---

## Core Capabilities

### Must-Haves (MVP)

- [ ] **SwiftEA Mail Module**: Read, search, export Apple Mail (done/in progress)
- [ ] **SwiftEA Calendar Module**: Read, search, export Apple Calendar
- [ ] **Unified search**: Query across mail and calendar with FTS5
- [ ] **Markdown export**: Export items to Obsidian-friendly markdown with YAML frontmatter
- [ ] **Basic task CLI**: Create, list, complete tasks via command line
- [ ] **Agent-readable output**: JSON output for all commands so Claude can parse results
- [ ] **Obsidian vault read**: Claude can read notes from vault for context
- [ ] **Cross-module linking**: Link emails to calendar events to contacts

### Nice-to-Haves (Future)

- [ ] **Contacts Module**: Full contact access and relationship mapping
- [ ] **Semantic search**: Vector embeddings for meaning-based queries
- [ ] **AI-generated summaries**: Automatic summarization of emails, meetings, threads
- [ ] **Priority scoring**: ML-based prioritization of inbox and tasks
- [ ] **Daily digest notes**: Agent writes summary notes to Obsidian on schedule
- [ ] **Dashboard markdown**: Living document in vault that agent keeps updated
- [ ] **Smart auto-linking**: Automatic detection of related items across modules
- [ ] **Context assembly**: Gather all information about a project/topic in one command

---

## Modules & Components

### Data Layer (SwiftEA)
- **MailModule**: Apple Mail access (SQLite + .emlx files)
- **CalendarModule**: Apple Calendar access (SQLite + .calendar bundles)
- **ContactsModule**: Apple Contacts access (SQLite + vCards)
- **Core**: Shared infrastructure (database, search, sync, export, metadata)

### Intelligence Layer (Shared libSQL)
- **Unified search index**: FTS5 across all modules
- **Metadata store**: AI-generated insights, priority scores, tags
- **Link graph**: Relationships between items across modules
- **Context cache**: Pre-assembled contexts for common queries

### Task/Project Layer (New CLI Tool)
- **SQLite-based storage**: Simple, queryable, inspectable
- **Agent-managed**: User never interacts directly; Claude handles all operations
- **Natural language updates**: User receives NL summaries, not raw data

### Knowledge Layer (Obsidian)
- **Markdown notes**: User's personal knowledge base
- **Agent-generated notes**: Digests, dashboards, exported items
- **Bidirectional sync**: Agent reads vault for context, writes updates back

### Orchestration Layer (Claude Code)
- **CLI interface**: Terminal-based conversations
- **IDE integration**: VS Code/Cursor with Claude
- **Skills/commands**: Pre-built workflows for common tasks
- **MCP servers**: Tool access for Claude agent

---

## Ideas & Vibes

### Inspiration & References

- **Notion AI / Mem.ai**: AI-powered knowledge base that understands your content
- **Superhuman / Hey**: High-performance email with smart features and keyboard-first UX
- **Personal CRM (Clay, Monica)**: Relationship context and interaction history
- **Unix philosophy**: Small tools that compose well, text-based, scriptable
- **PARA method**: Projects, Areas, Resources, Archives for organizing knowledge
- **GTD**: Capture everything, process to next actions, maintain trusted system

**What to emulate**:
- Superhuman's speed and keyboard-first design
- Mem.ai's semantic understanding of your content
- Unix composability and transparency
- Clay's relationship intelligence

**What to avoid**:
- Complexity creep (keep it simple and focused)
- Black-box AI that you can't inspect or correct
- Vendor lock-in and proprietary formats
- Feature bloat that slows down the core experience

### Dream Scenario

Six months from now, you wake up and ask Claude: "What's on my plate today?"

Claude responds with a synthesized view: three priority emails that need responses (with draft suggestions), two meetings with prep notes already in your vault, a reminder that you promised to send Alice something last week (extracted from email), and a heads-up that the project deadline is approaching with three open tasks.

You say: "Draft a reply to Bob declining the meeting politely—I have a conflict." Claude composes it, you review and send with one keystroke. You never opened Mail.app.

The task manager quietly tracks your commitments. You never look at it. Claude knows what you committed to because it read your emails and meeting notes. When things are slipping, Claude tells you. When they're done, Claude closes them.

Your Obsidian vault has a "Today" note that updates each morning with your agenda, priorities, and any notes Claude thinks you should see. There's a "People" folder with relationship context that Claude keeps current. There's a "Projects" folder with status dashboards Claude maintains.

You're not managing a system. You're being managed *by* the system—in the best way. You focus on the work that matters. Claude handles the rest.

### Key Moments

- "What am I forgetting?" → Claude surfaces the dropped balls you didn't know you dropped
- "Who is this person?" → Full relationship context before you reply to an email
- "Brief me on Project X" → Everything relevant in 30 seconds
- "Handle my inbox" → Come back to a triaged inbox with drafts ready
- The first time you realize you haven't opened Mail.app in a week

---

## Technical Considerations

### Known Constraints

- **Full Disk Access required**: To read Apple's databases
- **Automation permission required**: For AppleScript write operations
- **macOS only**: Leverages Apple-specific APIs and file locations
- **Offline-first**: Core functionality must work without internet
- **Fast startup**: Commands should execute in <1 second
- **Low memory footprint**: Shouldn't bog down the machine
- **Read-only source**: Never modify Apple's databases directly

### Potential Dream Ruiners

- **Apple database format changes**: Apple could change schema without warning; need resilience
- **AI context limits**: Claude's context window may not fit all relevant data; need smart summarization
- **AI reliability across sessions**: Context loss between conversations; need persistent memory strategy
- **Complexity creep**: Building too much, too fast, making it unmaintainable
- **Performance at scale**: 100k+ emails needs careful indexing and query optimization
- **AppleScript limitations**: Some operations may not be scriptable

### Existing Solutions/Dependencies to Evaluate

- **libSQL**: SQLite fork with better tooling, potential vector extensions
- **sqlite-vss**: Vector similarity search for semantic queries (future)
- **mcp-obsidian**: MCP server for Obsidian integration
- **beads**: Issue tracking for multi-session work persistence
- **Raycast/Alfred**: Launcher integration for quick queries (future)

---

## Early Decisions & Integrations

### Architecture (Early Ideas)

- **Hybrid data architecture**: Unified libSQL for intelligence layer, module-owned source data
- **SwiftEA as ingest layer**: Pulls from Apple apps into shared database
- **Shared libSQL as intelligence layer**: Search, metadata, links, AI insights
- **CLI-first**: All tools are command-line; no GUI dependencies
- **JSON output by default**: Everything Claude-parseable
- **Markdown for human output**: Obsidian-friendly exports

### Technical Standards

- **Swift for SwiftEA**: Native macOS, fast, type-safe
- **libSQL for databases**: SQLite-compatible, FTS5 support
- **Markdown + YAML frontmatter**: For all exports to Obsidian
- **JSON for interchange**: Between tools and Claude
- **Conventional commits**: Semantic versioning and clear history

### Dependencies

- **libSQL**: Database engine for SwiftEA and task manager
- **Swift Argument Parser**: CLI framework
- **OSAKit**: AppleScript execution for write operations
- **Claude Code**: AI orchestration layer

### Integrations

- **Apple Mail**: Via SQLite + .emlx + AppleScript
- **Apple Calendar**: Via SQLite + .calendar + AppleScript
- **Apple Contacts**: Via SQLite + vCards + AppleScript
- **Obsidian**: Via filesystem (read/write markdown)
- **Claude Code**: Via CLI invocation and MCP servers

---

## Roadmap

### Phase 1: SwiftEA Foundation (Current)
**Vision Goals**: VG-1, VG-5, VG-7
- Mail module: read, search, export
- Core infrastructure: database, FTS5, export system
- CLI interface: argument parsing, output formatting
- Basic Obsidian export: markdown with frontmatter

### Phase 2: Calendar & Unified Search
**Vision Goals**: VG-1, VG-3, VG-7
- Calendar module: read, search, export
- Cross-module search: unified FTS5 index
- Cross-module linking: email ↔ calendar connections
- Improved Obsidian export: daily/weekly digest templates

### Phase 3: Task Manager & Agent Workflows
**Vision Goals**: VG-2, VG-3, VG-6, VG-8
- Task manager CLI: SQLite-based, agent-managed
- Claude Code skills: inbox triage, meeting prep, daily briefing
- Obsidian bidirectional sync: agent reads and writes vault
- Dashboard markdown: living status documents

### Phase 4: Contacts & Relationship Intelligence
**Vision Goals**: VG-1, VG-3
- Contacts module: read, search, relationship mapping
- Automatic linking: email/calendar → contacts
- Relationship context: interaction history, notes
- People notes in Obsidian: agent-maintained profiles

### Phase 5: AI Intelligence Layer
**Vision Goals**: VG-2, VG-3, VG-6
- Semantic search: vector embeddings for meaning-based queries
- Priority scoring: ML-based prioritization
- Automatic summarization: emails, meetings, threads
- Smart task extraction: identify commitments from emails

### Phase 6+: Polish & OSS Release
**Vision Goals**: VG-5, VG-7
- Documentation and guides
- Installation packaging (Homebrew)
- Community feedback and refinement
- Plugin/extension system (maybe)

---

## Next Steps

### Research Needed
- [ ] Test libSQL performance with 100k+ emails
- [ ] Evaluate mcp-obsidian for vault integration
- [ ] Prototype task manager CLI schema
- [ ] Explore Claude Code persistent memory strategies (beads, etc.)

### Open Questions
- How to handle AI context limits when full project context is large?
- What's the right granularity for task manager (GTD-style vs. simple list)?
- How to make bidirectional Obsidian sync robust and conflict-free?
- How to handle agent errors gracefully (wrong triage, missed commitment)?

### When to Revisit This Doc
- After Mail module is fully working and used for a week
- After Calendar module is implemented
- After first version of task manager CLI
- When preparing for initial friend/colleague sharing
- Before any OSS release

---

## Notes & Evolution

- **2026-01-08**: Initial vision doc created via interview. Key insight: the goal is *delegation* to the agent, not just *assistance*. User wants to manage the agent; agent manages the system.
- **2026-01-08**: Promoted to master-plan status. Added vision goals (VG-1 through VG-8) for traceability. Roadmap phases now reference vision goals.

---

## Appendix: Design Principles (from ClaudEA Standards)

These principles from the broader ClaudEA vision should guide all technical decisions:

1. **Text-file native**: Everything stored as markdown, SQLite, JSON. No proprietary formats.
2. **CLI-first**: Terminal-based, scriptable, automation-friendly.
3. **Open source dependencies**: Prefer OSS for everything we control.
4. **Deterministic over probabilistic**: Scripts > prompts > agents. Use AI only where reasoning is needed.
5. **Composability over monoliths**: Small, single-purpose tools that chain together.
6. **Data layer simplicity**: Markdown for notes, SQLite for structured data, JSON for interchange.
7. **Progressive enhancement**: Simple data layer → scripts → workflows → AI agents.
