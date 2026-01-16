# SwiftEA + ClaudEA

> *An AI executive assistant that manages your knowledge work so you can focus on what matters*

## What This Is

**SwiftEA** (Swift Executive Assistant) is a unified CLI toolkit that provides programmatic access to macOS personal information management (PIM) data—email, calendar, contacts, tasks, and notes. Built as a modular monolith, SwiftEA serves as the foundational data access layer for **ClaudEA**, an AI-powered executive assistant that manages your knowledge work through delegation, not just assistance.

**Core Philosophy**: One tool, unified knowledge graph, modular architecture.

**Who This Is For**:
- Power users who live in the terminal and manage complex knowledge work
- Technical professionals (developers, architects, consultants) who need to manage email, meetings, and projects efficiently
- Knowledge workers overwhelmed by information volume who want proactive AI assistance without GUI overhead

**The Problem Being Solved**:
- **Fragmented information**: Email in Mail, events in Calendar, tasks in Reminders, notes in Obsidian—context is scattered across apps with no unified search or linking
- **Cognitive overload**: Too many inboxes, too many tabs, too many things to remember; the mental overhead of tracking it all is exhausting
- **Reactive workflows**: Always responding to what's in front of you rather than proactively managing priorities
- **Context loss across AI sessions**: Claude forgets what you discussed yesterday; each conversation starts from scratch
- **GUI friction**: Clicking through apps and menus breaks flow; the terminal is faster but doesn't have access to your data
- **Vendor lock-in**: Data is trapped in proprietary formats and apps you don't control

---

## Core Value

**Delegation, not assistance.** Traditional AI assistants help you do work. ClaudEA does the work for you—triaging, organizing, reminding, drafting—and only escalates what requires your judgment. You manage the agent; the agent manages the system.

When tradeoffs arise, prioritize enabling autonomous AI workflows that can handle routine knowledge work (inbox triage, meeting prep, commitment tracking) without human intervention. The ultimate measure of success is: *you never have to open Mail.app*.

---

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

**Phase 1 Foundation (Shipped)**:
- [x] Mail Module read/search/export foundation — syncs Apple Mail to local libSQL mirror
- [x] Threading support — conversation grouping, thread export, reply chain navigation (`swiftea mail threads`, `swiftea mail thread --id`)
- [x] Apple Mail actions via AppleScript — send, reply, draft, archive, delete, move, flag, mark read/unread
- [x] Core infrastructure — libSQL database with FTS5 search, sync engine, export system (markdown/JSON)
- [x] CLI infrastructure — command routing, argument parsing, output formatting

### Active

<!-- Current scope. Building toward these. -->

#### Agent-Readiness (P0 — Blockers for ClaudEA Integration)

These are critical for enabling autonomous AI agent consumption:

| ID | Requirement | Description |
|----|-------------|-------------|
| AF-1 | `--json` flag for all commands | Every command must support JSON output with defined schemas; agents cannot parse freeform text |
| AF-2 | `--non-interactive` mode | Fail immediately on prompts instead of blocking; include recovery hints with exact flags to bypass |
| AF-3 | Error code taxonomy | Machine-readable error codes (`ERR_AUTH_001`, `ERR_SYNC_001`, etc.) with recovery hints, not freeform strings |
| AF-4 | `swiftea inspect --json` | Full system state snapshot for agent re-orientation after context loss |
| AF-5 | Stable ID guarantee | Message IDs must survive Apple Mail DB rebuilds, mailbox migrations, cross-machine sync; emit `idStability` enum |
| AF-6 | `--confirm` flags | Replace all `y/n` prompts with `--confirm`, `--yes`, `--force`, `--dry-run` flags |

**Current Agent-Readiness Score**: 2/10 (High friction)
**Target Agent-Readiness Score**: 9/10

#### Agent Performance (P1 — Reliability & Efficiency)

| ID | Requirement | Description |
|----|-------------|-------------|
| AF-7 | `--compact` mode | Suppress progress output, single-line JSON result, log verbosity to file |
| AF-8 | Warnings in JSON | Emit warnings even on "success" for swallowed parse errors, partial syncs |
| AF-9 | Operation visibility | `swiftea operations --json` to query running/failed operations |
| AF-10 | ISO 8601 timestamps | All dates must be `2026-01-12T10:30:00Z` format, not Swift `.description` |
| AF-11 | Delta status output | Show only changes since last check to reduce token usage |

#### Phase 1 Completion

- [ ] Vault bootstrap — `swiftea init --vault <path>` creates vault-local config + folder layout with vault-scoped account bindings
- [ ] Bidirectional inbox/mail sync improvements
- [ ] `swiftea doctor --permissions` to diagnose permission issues

#### Phase 2 — Calendar & Unified Search

- [ ] Calendar module — read events with attendees, location, notes; search by date/title/attendees; export to markdown/JSON
- [ ] Calendar actions via AppleScript — create, update, delete events; manage attendees
- [ ] Handle recurring events properly
- [ ] Contacts module — read contacts with all fields; search by name/email/organization; export to markdown/JSON
- [ ] Contact actions via AppleScript — create, update, delete; manage groups; access photos
- [ ] Cross-module linking — email ↔ event ↔ contact relationships in links table
- [ ] Automatic link detection — detect events in email body, contacts in from field
- [ ] Unified search with cross-module ranking and faceted results

#### Phase 3 — Reminders & Context Assembly

- [ ] Reminders module — read/search/export Apple Reminders; create/update/delete via AppleScript
- [ ] Context assembly — `swiftea context --project "Alpha" --json` gathers all related items with timeline view
- [ ] Advanced metadata — ad-hoc field addition without migrations; bulk metadata operations; metadata templates
- [ ] JSON output for all commands (complete ClaudEA integration)

#### Phase 4 — Performance & Reliability

- [ ] Performance optimization — caching layer, parallel processing where safe
- [ ] Real-time sync via FSEvents watchers with incremental updates
- [ ] Large dataset handling — 100k+ items with sub-second queries
- [ ] Error recovery and resilience with exponential backoff retry
- [ ] Conflict resolution (configurable: last-write-wins default)

#### Phase 5 — AI & Semantic Features

- [ ] Semantic search — vector embeddings via sqlite-vss for meaning-based queries
- [ ] Automatic synonym handling
- [ ] AI-generated summaries — emails, meetings, threads (opt-in, local-first by default)
- [ ] Priority scoring — ML-based prioritization of inbox and tasks
- [ ] Smart task extraction — identify commitments from emails automatically
- [ ] Automatic categorization of content

#### Phase 6 — Polish & OSS Release

- [ ] Notes module — Apple Notes integration or markdown-only vault
- [ ] Documentation and guides
- [ ] Installation packaging — Homebrew formula (`brew tap swiftea/tap && brew install swiftea`)
- [ ] Community feedback and refinement
- [ ] Plugin/extension system (maybe)

#### Phase 7 — GUI Layer (Future)

Prerequisites: CLI must be stable, well-tested, and feature-complete first.

- [ ] SwiftUI-based native macOS application
- [ ] GUI as thin presentation layer calling CLI/library APIs
- [ ] Menu bar quick access and notifications
- [ ] Thread visualization — expandable conversation trees, thread timeline, participant activity
- [ ] Unified dashboard — mail + calendar + contacts in one view
- [ ] Project-based views aggregating related items

### Out of Scope

<!-- Explicit boundaries with reasoning to prevent re-adding. -->

| Exclusion | Reason |
|-----------|--------|
| **Replace native macOS apps** | We read from Mail.app/Calendar.app; we don't replace them. Apple handles the UI and sync. |
| **GUI applications (for now)** | CLI-first ensures stable foundation; GUI is Phase 7+ after CLI is proven. |
| **Cloud sync or multi-device** | macOS single machine; Apple already syncs across devices via iCloud. |
| **Cross-platform support** | macOS only to leverage Apple ecosystem APIs (SQLite databases, AppleScript). |
| **Real-time collaboration** | Single-user system for personal knowledge work. |
| **Modifying Apple's databases** | Read-only access; all writes go through AppleScript for safety. |
| **Network attacks / remote exploitation** | Local-only tool with no network access. |
| **Telemetry or data collection** | Privacy-first; no data leaves your Mac. |

---

## Context

### The Vision: Cognitive Offload Through Delegation

Six months from now, you wake up and ask Claude: "What's on my plate today?"

Claude responds with a synthesized view: three priority emails that need responses (with draft suggestions), two meetings with prep notes already in your vault, a reminder that you promised to send Alice something last week (extracted from email), and a heads-up that the project deadline is approaching with three open tasks.

You say: "Draft a reply to Bob declining the meeting politely—I have a conflict." Claude composes it, you review and send with one keystroke. You never opened Mail.app.

The task manager quietly tracks your commitments. You never look at it. Claude knows what you committed to because it read your emails and meeting notes. When things are slipping, Claude tells you. When they're done, Claude closes them.

Your Obsidian vault has a "Today" note that updates each morning with your agenda, priorities, and any notes Claude thinks you should see. There's a "People" folder with relationship context that Claude keeps current. There's a "Projects" folder with status dashboards Claude maintains.

You're not managing a system. You're being managed *by* the system—in the best way. You focus on the work that matters. Claude handles the rest.

### Key Moments That Define Success

- **"What am I forgetting?"** → Claude surfaces the dropped balls you didn't know you dropped
- **"Who is this person?"** → Full relationship context before you reply to an email
- **"Brief me on Project X"** → Everything relevant in 30 seconds
- **"Handle my inbox"** → Come back to a triaged inbox with drafts ready
- The first time you realize you haven't opened Mail.app in a week

### Use Cases

| Use Case | Description | SwiftEA Commands |
|----------|-------------|------------------|
| **Morning briefing** | "What do I need to handle today?" → prioritized list across email, calendar, tasks | `swiftea context --today --json` |
| **Email triage** | Agent processes inbox, archives low-priority, flags urgent, drafts responses | `swiftea mail search is:unread --json`, `swiftea mail archive`, `swiftea mail flag` |
| **Meeting prep** | "Brief me on my 2pm" → attendee context, related emails, action items from last meeting | `swiftea cal get --id cal:123 --json`, `swiftea context --event cal:123` |
| **Relationship context** | "What's my history with Alice?" → all emails, meetings, notes about/with Alice | `swiftea context --contact "Alice" --json` |
| **Task delegation** | "Remind me to follow up on the proposal next week" → agent creates task, manages it | `swiftea tasks create`, managed by Claude |
| **Context recovery** | "What was I working on with Project X?" → full context from emails, notes, tasks | `swiftea context --project "X" --json` |
| **Draft composition** | "Draft a reply to Bob's email about the budget" → contextual draft | `swiftea mail show --id msg:123 --json`, Claude drafts, `swiftea mail reply` |

### System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     ClaudEA (Intelligence Layer)                 │
│    AI orchestration, natural language interface, workflows,      │
│    inbox triage, meeting prep, commitment tracking               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     SwiftEA (Data Layer)                         │
│    CLI access to Mail, Calendar, Contacts, Tasks, Notes         │
│    Unified FTS5 search, cross-module linking, markdown export   │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        ┌─────────┐     ┌─────────┐     ┌─────────┐
        │  Apple  │     │  Apple  │     │  Apple  │
        │  Mail   │     │Calendar │     │Contacts │
        └─────────┘     └─────────┘     └─────────┘
```

### Modular Monolith Structure

```
SwiftEA
  ├── Core (Shared Infrastructure)
  │   ├── Database Layer (libSQL + FTS5)
  │   ├── Search Engine (unified full-text + semantic)
  │   ├── Sync Engine (FSEvents + polling)
  │   ├── Export System (markdown/JSON/CSV)
  │   ├── Metadata Manager (custom fields, AI insights)
  │   └── Link Manager (cross-module relationships)
  │
  ├── Modules (Data Sources)
  │   ├── MailModule (Apple Mail SQLite + .emlx)
  │   ├── CalendarModule (Calendar Cache + .calendar bundles)
  │   ├── ContactsModule (AddressBook + vCards)
  │   ├── RemindersModule (future)
  │   └── NotesModule (future)
  │
  └── CLI (User Interface)
      └── Command Router (swiftea <module> <command>)
```

### Data Sources

| Module | Database Location | File Format | Write Method |
|--------|------------------|-------------|--------------|
| Mail | `~/Library/Mail/V[x]/MailData/Envelope Index` | `.emlx` files | AppleScript |
| Calendar | `~/Library/Calendars/Calendar Cache` | `.calendar` bundles | AppleScript |
| Contacts | `~/Library/Application Support/AddressBook/AddressBook-v22.abcddb` | vCards | AppleScript |
| Reminders | SQLite database | — | AppleScript |
| Notes | SQLite database | — | AppleScript |

### Database Schema (Core)

```sql
-- Core item registry (tracks all items across modules)
CREATE TABLE items (
  id TEXT PRIMARY KEY,              -- Unique ID (format: MODULE:NATIVE_ID)
  module TEXT NOT NULL,             -- 'mail', 'calendar', 'contacts'
  native_id TEXT NOT NULL,          -- Original ID from source system
  item_type TEXT NOT NULL,          -- 'email', 'event', 'contact', etc.
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  UNIQUE(module, native_id)
);

-- Unified metadata (works across all modules)
CREATE TABLE metadata (
  item_id TEXT PRIMARY KEY,
  ai_summary TEXT,
  ai_insights TEXT,
  priority_score INTEGER,
  processing_status TEXT,
  linked_projects TEXT,             -- JSON array
  linked_tasks TEXT,                -- JSON array
  custom_tags TEXT,                 -- JSON array
  notes TEXT,
  custom_fields JSON,               -- Ad-hoc fields
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  FOREIGN KEY (item_id) REFERENCES items(id)
);

-- Cross-module links
CREATE TABLE links (
  id INTEGER PRIMARY KEY,
  from_item_id TEXT NOT NULL,
  to_item_id TEXT NOT NULL,
  link_type TEXT,                   -- 'related', 'parent', 'child', 'reference', 'thread'
  created_at TIMESTAMP,
  FOREIGN KEY (from_item_id) REFERENCES items(id),
  FOREIGN KEY (to_item_id) REFERENCES items(id)
);

-- Unified full-text search
CREATE VIRTUAL TABLE search_index USING fts5(
  item_id UNINDEXED,
  module UNINDEXED,
  item_type UNINDEXED,
  title,
  content,
  participants,                     -- emails, attendees, contact names
  tags,
  tokenize='porter unicode61 remove_diacritics 1'
);
```

### ClaudEA Integration Points

```bash
# 1. Data Access — ClaudEA queries for context
swiftea search "project alpha" --json | claudea analyze
swiftea context --project Alpha --json

# 2. Automated Actions — ClaudEA triages inbox
swiftea mail search "is:unread" --json | claudea triage
swiftea mail archive --id msg:123 --confirm

# 3. Knowledge Base Population — Export to Obsidian
swiftea export --all --format markdown --output ~/vault/swiftea/
swiftea export --changed --format markdown --output ~/vault/swiftea/

# 4. Task Extraction — Find commitments
swiftea search "action item OR TODO" --json | claudea extract-tasks

# 5. Meeting Prep
swiftea cal get --id cal:123 --json  # Returns: Agenda, attendees, notes
swiftea context --event cal:123 --json  # Related emails, past meetings with attendees
```

### ClaudEA Skills (Future)

Pre-built Claude Code commands that leverage SwiftEA:

```bash
claudea /email-triage          # Auto-triage inbox
claudea /meeting-prep <event>  # Prepare for meeting with full context
claudea /project-status <name> # Generate project report
claudea /find-related <item>   # Find all related items across modules
claudea /extract-tasks         # Extract tasks from emails/events
claudea /daily-briefing        # Generate morning briefing note
```

### Inspiration & References

**What to emulate**:
- **Superhuman**: Speed and keyboard-first design
- **Mem.ai**: Semantic understanding of your content
- **Clay**: Relationship intelligence and interaction history
- **Unix philosophy**: Small tools that compose well, text-based, scriptable

**What to avoid**:
- Complexity creep (keep it simple and focused)
- Black-box AI that you can't inspect or correct
- Vendor lock-in and proprietary formats
- Feature bloat that slows down the core experience

### Research & Open Questions

**Research Needed**:
- [ ] Test libSQL performance with 100k+ emails
- [ ] Evaluate mcp-obsidian for vault integration
- [ ] Prototype task manager CLI schema
- [ ] Explore Claude Code persistent memory strategies (beads, etc.)
- [ ] Which embedding provider for semantic search (OpenAI, Anthropic, local)?

**Open Questions**:
- **Tasks Module**: Apple Reminders vs. Markdown-based vs. Hybrid?
- **Notes Module**: Apple Notes integration vs. Markdown-only?
- **Distribution**: Mac App Store submission? Or Homebrew-only?
- **Plugin System**: Allow third-party modules? Or keep core-only?
- **Cloud Sync**: Optional encrypted cloud backup? Or strictly local?
- How to handle AI context limits when full project context is large?
- How to make bidirectional Obsidian sync robust and conflict-free?
- How to handle agent errors gracefully (wrong triage, missed commitment)?

---

## Constraints

### Technical Constraints

| Constraint | Requirement | Rationale |
|------------|-------------|-----------|
| **Tech Stack** | Swift 6.0+, Swift Argument Parser, libSQL, Foundation, OSAKit | Native macOS performance, type safety |
| **Performance** | <1s search latency at 100k items, <1s startup, <500MB memory | Speed and flow are core to the experience |
| **Data Access** | Read-only from Apple databases; AppleScript for all writes | Never risk corrupting Apple's data |
| **Permissions** | Full Disk Access + Automation required | Needed for database reads and AppleScript |
| **Agent Compatibility** | All commands must support `--json` with schemas | ClaudEA cannot parse freeform text reliably |
| **Offline-first** | Core functionality works without internet | Local data should always be accessible |
| **Fast startup** | Commands execute in <1 second | Terminal workflow demands instant response |
| **Low memory** | Should not bog down the machine | Background sync must be lightweight |

### Security & Privacy Principles

1. **Local-First**: All data stays on user's Mac
2. **Read-Only Source**: Never modify Apple's databases directly
3. **No Cloud**: No data sent to external servers unless explicitly requested
4. **Transparent**: Users can inspect all data in SQLite/markdown
5. **Permissioned**: Request only necessary macOS permissions
6. **No Telemetry**: No data collection by default
7. **User Control**: Users control what data is exported and where

### Development Constraints

1. **Swift-Only**: Core implementation must be in Swift
2. **SPM-Compatible**: Must build with Swift Package Manager
3. **Homebrew Distribution**: Primary distribution method
4. **Documentation-First**: All features must be documented
5. **Conventional Commits**: Semantic versioning with clear history

### Potential Risks ("Dream Ruiners")

| Risk | Impact | Mitigation |
|------|--------|------------|
| Apple database format changes | Schema could change without warning | Build resilience; detect schema version |
| AI context limits | Claude's window may not fit all data | Smart summarization; context assembly |
| AI reliability across sessions | Context loss between conversations | Persistent memory via beads/Obsidian |
| Complexity creep | Building too much, too fast | Stay focused; ship incrementally |
| Performance at scale | 100k+ emails needs optimization | Careful indexing; query optimization |
| AppleScript limitations | Some operations may not be scriptable | Document limitations; workarounds |

---

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

### Architecture Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Modular monolith (not microservices) | Shared infrastructure (DB, search, sync); single binary simplicity; code reuse without duplication | ✓ Good |
| libSQL over raw SQLite | SQLite-compatible with better tooling, FTS5 support, future vector extensions (sqlite-vss) | ✓ Good |
| CLI-first, GUI later (Phase 7+) | Build stable, well-tested foundation before adding UI complexity; scriptability from day one | — Pending |
| AppleScript for write operations | Only reliable way to interact with Mail.app/Calendar.app without private APIs | ✓ Good |
| Hybrid data architecture | Unified libSQL for intelligence layer; module-owned source data mirrors | ✓ Good |

### Data Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Vault-scoped configuration | Each vault has its own config + account bindings; supports multiple contexts | — Pending |
| ID format `module:native_id` | Consistent cross-module addressing; e.g., `mail:12345`, `cal:abc123`, `con:xyz789` | ✓ Good |
| Markdown + YAML frontmatter for exports | Obsidian-friendly; human-readable; version-controllable | ✓ Good |
| JSON for agent interchange | ClaudEA cannot parse freeform text; structured output required | — Pending |

### Integration Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Obsidian as home base | Markdown vault is the human interface; agent reads/writes vault; bidirectional sync | — Pending |
| Claude Code as orchestration layer | CLI invocation + MCP servers; natural language interface; IDE integration | — Pending |
| beads for multi-session work | Issue tracking with dependencies for work that spans sessions | ✓ Good |

### Design Principles

1. **Text-file native**: Everything stored as markdown, SQLite, JSON. No proprietary formats.
2. **CLI-first**: Terminal-based, scriptable, automation-friendly.
3. **Open source dependencies**: Prefer OSS for everything we control.
4. **Deterministic over probabilistic**: Scripts > prompts > agents. Use AI only where reasoning is needed.
5. **Composability over monoliths**: Small, single-purpose tools that chain together.
6. **Data layer simplicity**: Markdown for notes, SQLite for structured data, JSON for interchange.
7. **Progressive enhancement**: Simple data layer → scripts → workflows → AI agents.

---

## Success Metrics

### Technical Metrics

| Metric | Target |
|--------|--------|
| Search latency (100k items) | < 1 second |
| Sync latency | < 5 seconds |
| Export throughput | > 100 items/second |
| Startup time | < 1 second |
| Memory usage | < 500MB |
| Crash rate | 99.9% uptime (no crashes) |
| Data loss | Zero |
| Error rate | < 1 error per 1000 operations |

### Agent Metrics

| Metric | Target |
|--------|--------|
| Agent success rate | > 95% (after P0 fixes) |
| Agent retry rate | < 5% |
| Token efficiency | Compact mode uses < 10% tokens of verbose |

### User Experience Goals

| Goal | Measure |
|------|---------|
| Daily active usage | Integrated into workflow |
| Mail.app opened | Rarely (agent handles most operations) |
| "What am I forgetting?" | Always has a useful answer |
| Morning briefing | Captures everything important |
| Context persistence | Never lost between AI sessions |

### Long-term Adoption (Future)

- 1,000 active users (Year 1)
- 10,000 active users (Year 2)
- 10% of ClaudEA users using SwiftEA
- User rating 4.5+/5
- < 5% uninstall rate

---

## Vision Goals Reference

### ClaudEA Ecosystem Goals (VG)

| ID | Type | Goal | Description |
|----|------|------|-------------|
| **VG-1** | Core | Unified Knowledge Graph | Query across email, calendar, contacts, tasks, and notes in one interface. All personal data connected and searchable. No more fragmented silos. |
| **VG-2** | Core | Delegation Not Assistance | The agent MANAGES your systems (task manager, inbox triage, dashboards). You manage by exception—stepping in only for decisions requiring human judgment. |
| **VG-3** | Core | Never Lose Context | Everything is connected in a queryable knowledge graph. No information falls through the cracks. Context persists across sessions and tools. "What am I forgetting?" always has an answer. |
| **VG-5** | Supporting | Data Sovereignty | Own your data in open formats (markdown, SQLite, JSON). No vendor lock-in. Everything inspectable, portable, and under your control. |
| **VG-6** | Supporting | Progressive Automation | Start with scripts, add workflows, escalate to AI agents only where reasoning is needed. Deterministic over probabilistic. Build confidence before complexity. |
| **VG-7** | Supporting | Composable Tools | Small CLI tools that chain together (Unix philosophy). Build systems from reusable components. Each piece inspectable and replaceable. |
| **VG-8** | Supporting | Obsidian as Home Base | The markdown vault is the human interface. Agent reads vault for context, writes digests and dashboards there. Bidirectional sync. Your notes are the source of truth. |

### SwiftEA Strategic Goals (SG)

| ID | Type | Goal | Description |
|----|------|------|-------------|
| **SG-1** | Core | Unified PIM Access | Provide programmatic CLI access to all macOS PIM data (Mail, Calendar, Contacts, Reminders, Notes) through a single tool. |
| **SG-2** | Core | Cross-Module Intelligence | Enable search, linking, and queries across all data types. Build the unified knowledge graph foundation. |
| **SG-3** | Core | Data Liberation | Export all data to open formats (markdown, JSON) for use by ClaudEA, Obsidian, or any downstream tool. |
| **SG-4** | Supporting | ClaudEA-Ready Output | Ensure all commands produce JSON output parseable by AI agents. Enable ClaudEA automation workflows. |
| **SG-5** | Supporting | Local-First Architecture | All data stored locally. No cloud dependencies. Privacy-preserving by design. |
| **SG-6** | Supporting | Modular Extensibility | Maintain clean module boundaries. New data sources can be added without disrupting existing functionality. |

---

## Project Conventions

### Code Style

- Follow Swift API Design Guidelines
- Use SwiftFormat for consistent formatting
- Prefer explicit types over type inference for public APIs
- Use `PascalCase` for types and protocols
- Use `camelCase` for variables, functions, and enum cases
- Use descriptive names that indicate purpose and type
- Add documentation comments for public APIs
- Use `MARK:` comments to organize code sections

### Architecture Patterns

- **Modular Monolith**: Single application with clear internal module boundaries
- **Layered Architecture**: Core layer (shared) + Module layer (data sources) + CLI layer (interface)
- **Repository Pattern**: For data access abstraction
- **Command Pattern**: For CLI command implementations
- **Observer Pattern**: For change detection and sync

### Module Protocol

```swift
protocol SwiftEAModule {
  var name: String { get }
  var version: String { get }

  func sync() async throws
  func search(_ query: String) async throws -> [Item]
  func get(id: String) async throws -> Item
  func export(id: String, format: ExportFormat) async throws -> Data
  func performAction(_ action: Action) async throws
}
```

### Testing Strategy

| Type | Scope |
|------|-------|
| Unit Tests | Core components, module logic, utilities |
| Integration Tests | Module interactions with Apple databases |
| End-to-End Tests | Full CLI command execution |
| Performance Tests | Search benchmarks (1k, 10k, 50k, 100k), sync latency, export throughput |
| Agent UX Tests | Synthetic agent simulator; JSON schema validation; error recovery testing |

### Git Workflow

- **Branching**: Feature branches from `main`
- **Commits**: Conventional commits with semantic prefixes
- **Format**: `<type>(<scope>): <description>`
- **Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`
- **Scopes**: `core`, `mail`, `calendar`, `contacts`, `cli`, `docs`, `build`
- **Versioning**: Semantic versioning (MAJOR.MINOR.PATCH)

---

## External Dependencies

### Core Dependencies

| Dependency | Purpose |
|------------|---------|
| libSQL | Database engine for SwiftEA mirror database (SQLite-compatible) |
| Swift Argument Parser | CLI framework |
| Foundation | macOS system APIs |
| OSAKit | AppleScript execution |

### Optional Dependencies (Future)

| Dependency | Purpose |
|------------|---------|
| sqlite-vss | Vector similarity search for semantic queries |
| SwiftCrypto | Encryption if needed |
| SwiftMarkdown | Markdown parsing/generation |

### macOS System Dependencies

| Dependency | Purpose |
|------------|---------|
| FSEvents | File system change notifications |
| Security Framework | Keychain access if needed |

### Ecosystem Dependencies

| Dependency | Purpose |
|------------|---------|
| Obsidian | Target for markdown exports |
| Claude Code | AI orchestration layer |
| mcp-obsidian | MCP server for Obsidian integration |
| beads | Issue tracking for multi-session work |
| Raycast/Alfred | Launcher integration (future) |

---

## References

| Document | Location | Purpose |
|----------|----------|---------|
| ClaudEA Ecosystem Master Plan | `.d-spec/swiftea-claudea-vision/claudea-swiftea-ecosystem-master-plan.md` | Full ecosystem vision, VG goals |
| SwiftEA Architecture Master Plan | `.d-spec/swiftea-claudea-vision/swiftea-architecture-master-plan.md` | Technical architecture, SG goals |
| Agent UX Audit | `.d-spec/swiftea-claudea-vision/agent-ux-audit.md` | Agent-readiness recommendations |
| Project Conventions | `.d-spec/swiftea-claudea-vision/project.md` | Tech stack, code style |
| Roadmap | `.d-spec/swiftea-claudea-vision/roadmap.md` | Phase breakdown |
| Execution Tracking | `.beads/` | Issue tracker |

---

*Last updated: 2026-01-15 after comprehensive vision document review*
