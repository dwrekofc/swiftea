# SwiftEA - Architecture & Design Document

## Executive Summary

**SwiftEA** (Swift Executive Assistant) is a unified CLI tool that provides programmatic access to macOS personal information management (PIM) data—email, calendar, contacts, tasks, and notes. Built as a modular monolith, SwiftEA serves as the data access layer for ClaudEA, enabling AI-powered executive assistant workflows across the user's entire knowledge base.

**Core Philosophy**: One tool, unified knowledge graph, modular architecture.

---

## Vision & Goals

### Primary Vision
Transform fragmented macOS data sources (Mail, Calendar, Contacts) into a unified, searchable, AI-accessible knowledge base that enables ClaudEA to function as a true executive assistant.

### Strategic Goals

1. **Unified Knowledge Access**: Single interface to query across all personal data types
2. **Cross-Module Intelligence**: Link and search across emails, events, contacts, tasks, and notes
3. **ClaudEA Integration**: Provide the foundation for AI-powered workflows
4. **Data Liberation**: Export all data to open formats (markdown, JSON)
5. **Custom Intelligence Layer**: Add AI insights and metadata across all data types
6. **Future-Proof Architecture**: Modular design that scales as new data sources are added

### Non-Goals (Out of Scope)

- ❌ Replace native macOS apps (Mail.app, Calendar.app)
- ❌ Build GUI applications
- ❌ Sync with cloud services (we use macOS as the sync layer)
- ❌ Cross-platform support (macOS only, leveraging Apple's ecosystem)

---

## Architecture Overview

### Modular Monolith Pattern

SwiftEA is built as a **modular monolith**: a single application with clear internal module boundaries.

**Benefits**:
- Shared infrastructure (database, search, sync, export)
- Cross-module features (unified search, linked metadata)
- Single installation and update process
- Consistent CLI interface
- Code reuse without code duplication

**Structure**:
```
SwiftEA
  ├── Core (Shared Infrastructure)
  │   ├── Database Layer
  │   ├── Search Engine
  │   ├── Sync Engine
  │   ├── Export System
  │   └── Metadata Manager
  │
  ├── Modules (Data Sources)
  │   ├── MailModule
  │   ├── CalendarModule
  │   ├── ContactsModule
  │   ├── TasksModule (future)
  │   └── NotesModule (future)
  │
  └── CLI (User Interface)
      └── Command Router
```

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         SwiftEA CLI                             │
│                    (Command Line Interface)                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                ┌─────────────┼─────────────┐
                │             │             │
                ▼             ▼             ▼
        ┌───────────┐  ┌──────────┐  ┌────────────┐
        │   Mail    │  │ Calendar │  │  Contacts  │
        │  Module   │  │  Module  │  │   Module   │
        └───────────┘  └──────────┘  └────────────┘
                │             │             │
                └─────────────┼─────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │          SwiftEA Core Layer             │
        ├─────────────────────────────────────────┤
        │ • Database (SQLite + FTS5)              │
        │ • Search Engine (Unified + Semantic)    │
        │ • Sync Engine (FSEvents + Polling)      │
        │ • Export System (Markdown/JSON)         │
        │ • Metadata Manager (Custom Fields)      │
        │ • Link Manager (Cross-module)           │
        └─────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌──────────────┐      ┌─────────────┐      ┌──────────────┐
│ Apple Mail   │      │   Calendar  │      │   Contacts   │
│  SQLite DB   │      │   SQLite DB │      │   SQLite DB  │
│  .emlx files │      │   .calendar │      │   vCards     │
└──────────────┘      └─────────────┘      └──────────────┘
```

---

## Core Layer Components

### 1. Database Layer

**Purpose**: Unified data access and storage

**Architecture**:
- **Primary Database**: `~/.config/swiftea/swiftea.db` (SQLite)
- **Mirror Tables**: Copies of Apple's databases (read-only source)
- **Metadata Tables**: Custom user/AI-generated data
- **Index Tables**: FTS5 full-text search indexes
- **Link Tables**: Cross-module relationships

**Schema Overview**:
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
  link_type TEXT,                   -- 'related', 'parent', 'child', 'reference'
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

-- Module-specific tables
CREATE TABLE mail_mirror (...);    -- From MailModule spec
CREATE TABLE calendar_mirror (...);
CREATE TABLE contacts_mirror (...);
```

**Database Features**:
- **WAL mode**: Concurrent read/write
- **Foreign key constraints**: Data integrity
- **Automatic timestamps**: Track all changes
- **JSON support**: Flexible custom fields
- **Transactions**: Atomic operations
- **Indexes**: Optimized queries

### 2. Search Engine

**Purpose**: Fast, unified search across all data types

**Capabilities**:
1. **Full-Text Search** (FTS5)
   - Keyword search across all content
   - Boolean operators (AND, OR, NOT)
   - Phrase matching
   - Relevance ranking (BM25)

2. **Structured Queries**
   - Filter by module, type, date, status
   - Metadata field queries
   - Complex boolean combinations

3. **Cross-Module Search**
   - Single query across emails, events, contacts
   - Unified result ranking
   - Faceted results (group by type)

4. **Semantic Search** (Phase 4)
   - Vector embeddings (sqlite-vss)
   - Meaning-based queries
   - Automatic synonym handling

**Search API**:
```bash
# Basic search
swiftea search "project alpha"                    # All modules
swiftea search "project alpha" --mail             # Mail only
swiftea search "project alpha" --mail --calendar  # Multiple modules

# Advanced search
swiftea search "budget AND Q1" --after 2026-01-01 --ranked
swiftea search '"exact phrase"' --snippet

# Structured query
swiftea query --field priority_score --value ">7" --all
swiftea query --tag urgent --tag finance --mail
```

### 3. Sync Engine

**Purpose**: Keep SwiftEA database synchronized with Apple's data sources

**Strategy**: Hybrid approach
1. **File System Watcher** (FSEvents): Real-time change detection
2. **Periodic Validation**: Full sync every N minutes
3. **Manual Refresh**: On-demand sync

**Architecture**:
```
┌─────────────────────────────────────────────┐
│           Sync Coordinator                  │
│  • Manages all module sync operations       │
│  • Handles conflicts and errors             │
│  • Provides sync status                     │
└─────────────────────────────────────────────┘
                    │
        ┌───────────┼───────────┐
        │           │           │
        ▼           ▼           ▼
  ┌─────────┐ ┌─────────┐ ┌─────────┐
  │  Mail   │ │Calendar │ │Contacts │
  │  Sync   │ │  Sync   │ │  Sync   │
  └─────────┘ └─────────┘ └─────────┘
```

**Sync Features**:
- **Incremental sync**: Only changed items
- **Change detection**: Checksums and timestamps
- **Conflict resolution**: Last-write-wins (configurable)
- **Error recovery**: Retry with exponential backoff
- **Status reporting**: Per-module sync state

**Sync Commands**:
```bash
swiftea sync                        # Sync all modules
swiftea sync --mail                 # Sync specific module
swiftea sync --watch                # Start background watcher
swiftea sync --validate             # Full validation sync
swiftea sync --status               # Show sync status
```

### 4. Export System

**Purpose**: Convert data to portable formats (markdown, JSON)

**Formats**:
- **Markdown**: YAML frontmatter + markdown body (Obsidian-friendly)
- **JSON**: Structured data (programmatic access)
- **CSV**: Tabular data (spreadsheet import)
- **vCard/iCal**: Native formats (future)

**Export Architecture**:
```
┌─────────────────────────────────────────────┐
│          Export Coordinator                 │
│  • Format selection                         │
│  • Template management                      │
│  • Batch processing                         │
└─────────────────────────────────────────────┘
                    │
        ┌───────────┼───────────┐
        │           │           │
        ▼           ▼           ▼
  ┌──────────┐ ┌──────────┐ ┌──────────┐
  │Markdown  │ │   JSON   │ │   CSV    │
  │Exporter  │ │Exporter  │ │Exporter  │
  └──────────┘ └──────────┘ └──────────┘
```

**Export Features**:
- **Template-based**: Customizable output formats
- **Batch export**: Multiple items in one command
- **Incremental export**: Only changed items
- **Filename patterns**: Configurable naming
- **Directory structure**: Organized output

**Export Commands**:
```bash
# Single item export
swiftea export --id mail:12345 --format markdown

# Batch export
swiftea export --query "project:Alpha" --format markdown --output ~/vault/

# Full export (all data)
swiftea export --all --format markdown --output ~/vault/swiftea/

# Module-specific export
swiftea mail export --query "from:bob" --format json --array
```

### 5. Metadata Manager

**Purpose**: Manage custom fields and AI-generated insights

**Features**:
- **Dynamic schema**: Add fields without migrations
- **Type safety**: Validate field types
- **Versioning**: Track metadata changes
- **Bulk operations**: Update many items at once

**Metadata Commands**:
```bash
# Add custom column (ad-hoc schema extension)
swiftea meta add-field --name urgency_level --type INTEGER

# Set metadata
swiftea meta set --id mail:12345 --field priority_score --value 9
swiftea meta set --id cal:789 --field linked_projects --value '["Alpha"]'

# Batch metadata update
swiftea meta update --query "tag:urgent" --field priority_score --value 10

# Query by metadata
swiftea query --meta priority_score ">7" --all
```

### 6. Link Manager

**Purpose**: Create and manage relationships between items across modules

**Link Types**:
- **Related**: General association
- **Parent/Child**: Hierarchical relationship
- **Reference**: One item references another
- **Thread**: Items in conversation/sequence

**Link Features**:
- **Bidirectional**: Links work both ways
- **Typed**: Different relationship semantics
- **Queryable**: Find linked items
- **Transitive**: Follow link chains

**Link Commands**:
```bash
# Create links
swiftea link --email mail:12345 --event cal:789
swiftea link --email mail:12345 --contact con:456 --type reference

# Query links
swiftea links --id mail:12345              # Show all links for item
swiftea links --id mail:12345 --events     # Show only event links

# Remove links
swiftea unlink --email mail:12345 --event cal:789
```

---

## Module Architecture

### Module Interface (Protocol)

All modules implement a common interface:

```swift
protocol SwiftEAModule {
  var name: String { get }
  var version: String { get }

  // Data access
  func sync() async throws
  func search(_ query: String) async throws -> [Item]
  func get(id: String) async throws -> Item

  // Export
  func export(id: String, format: ExportFormat) async throws -> Data
  func exportBatch(query: String, format: ExportFormat) async throws -> [Data]

  // Actions (module-specific)
  func performAction(_ action: Action) async throws
}

struct Item {
  let id: String
  let moduleId: String
  let type: ItemType
  let title: String
  let content: String
  let metadata: [String: Any]
  let createdAt: Date
  let updatedAt: Date
}
```

### Module Structure

Each module follows this structure:

```
MailModule/
├── Sources/
│   ├── DataAccess/          # Read from Apple's DB
│   ├── Sync/                # Sync logic
│   ├── Search/              # Module-specific search
│   ├── Export/              # Format conversion
│   ├── Actions/             # Operations (send, archive, etc.)
│   └── Models/              # Data models
├── Tests/
└── README.md
```

### Module Lifecycle

1. **Initialization**: Register with core, setup database tables
2. **Sync**: Mirror data from Apple's source
3. **Index**: Update FTS5 search index
4. **Ready**: Available for queries and actions

---

## Modules

### 1. Mail Module

**Status**: Phase 1 - In Development

**Purpose**: Access and manage Apple Mail data

**Data Sources**:
- SQLite: `~/Library/Mail/V[x]/MailData/Envelope Index`
- Files: `~/Library/Mail/V[x]/[Account]/[Mailbox]/Messages/*.emlx`

**Capabilities**:
- Read emails with full metadata
- Search email content (FTS5)
- Export to markdown/JSON
- Send, reply, draft (AppleScript)
- Archive, delete, move (AppleScript)
- Flag, label, mark read/unread (AppleScript)
- Create rules and filters

**See**: `swift-mail-cli-spec.md` for detailed specification

### 2. Calendar Module

**Status**: Phase 2 - Planned

**Purpose**: Access and manage Apple Calendar data

**Data Sources**:
- SQLite: `~/Library/Calendars/Calendar Cache`
- Files: `.calendar` bundles

**Planned Capabilities**:
- Read events with attendees, location, notes
- Search events by date, title, attendees
- Export to markdown/JSON
- Create, update, delete events (AppleScript)
- Manage attendees and responses
- Handle recurring events

**CLI Examples**:
```bash
swiftea cal list --today
swiftea cal list --week --calendar "Work"
swiftea cal search "standup"
swiftea cal create --title "Meeting" --date "2026-01-07 14:00" --duration 60
swiftea cal export --id cal:12345 --format markdown
```

**Metadata Integration**:
- Link events to projects
- Link events to related emails
- AI summaries of meetings
- Action items from calendar notes

### 3. Contacts Module

**Status**: Phase 2/3 - Planned

**Purpose**: Access and manage Apple Contacts data

**Data Sources**:
- SQLite: `~/Library/Application Support/AddressBook/AddressBook-v22.abcddb`
- vCard exports

**Planned Capabilities**:
- Read contacts with all fields
- Search by name, email, organization
- Export to markdown/JSON
- Create, update, delete contacts (AppleScript)
- Manage contact groups
- Photo/avatar access

**CLI Examples**:
```bash
swiftea contacts find "bob"
swiftea contacts find --company "Acme Corp"
swiftea contacts get --id con:12345
swiftea contacts create --name "Bob Smith" --email "bob@example.com"
swiftea contacts export --all --format markdown
```

**Metadata Integration**:
- Link contacts to projects
- Link contacts to emails/events (automatic)
- Relationship context (client, colleague, vendor)
- Interaction history

### 4. Tasks Module

**Status**: Phase 3+ - Future

**Purpose**: Unified task management

**Possible Approaches**:

**Option A**: Apple Reminders integration
- Access Reminders.app SQLite database
- Sync tasks to/from Reminders

**Option B**: Markdown-based tasks
- Tasks live in markdown files (Obsidian/Logseq style)
- SwiftEA provides CLI to manage them
- No Apple app dependency

**Option C**: Hybrid
- Support both Reminders and markdown tasks
- Bidirectional sync

**CLI Examples** (conceptual):
```bash
swiftea tasks list --today
swiftea tasks list --project Alpha
swiftea tasks create --title "Review spec" --due tomorrow --priority high
swiftea tasks complete --id task:12345
swiftea tasks link --task task:123 --email mail:456
```

### 5. Notes Module

**Status**: Phase 3+ - Future

**Purpose**: Access notes and documents

**Possible Approaches**:

**Option A**: Apple Notes integration
- Access Notes.app database
- Export notes to markdown

**Option B**: Markdown vault only
- Notes already in markdown (Obsidian/Logseq)
- SwiftEA provides search/metadata on top of files
- No Apple app dependency

**Option C**: Hybrid
- Import Apple Notes to markdown
- Ongoing sync or one-time migration

**CLI Examples** (conceptual):
```bash
swiftea notes search "project alpha"
swiftea notes export --id note:123 --format markdown
swiftea notes link --note note:123 --email mail:456
```

---

## Cross-Module Features

### 1. Unified Search

**The Killer Feature**: Search across all data types in one query

**Examples**:
```bash
# Search everything
swiftea search "project alpha"
# Returns: emails, events, contacts, tasks, notes

# Scoped search
swiftea search "budget" --mail --calendar
# Returns: emails and events only

# Faceted results
swiftea search "Q1 planning" --facets
# Groups results by module: Mail (15), Calendar (3), Contacts (2)

# Ranked cross-module
swiftea search "urgent" --ranked --limit 20
# Returns top 20 results across all modules by relevance
```

**Implementation**:
- Single FTS5 index with module field
- Unified ranking algorithm
- Type-aware result formatting

### 2. Cross-Module Linking

**Purpose**: Connect related items across data types

**Use Cases**:
- Link email thread to calendar event
- Link contact to all related emails
- Link project to all emails, events, tasks, notes

**Examples**:
```bash
# Manual linking
swiftea link --email mail:123 --event cal:456

# Automatic linking (smart detection)
swiftea auto-link --email mail:123
# Detects: event in email body, contact in from field, etc.

# Query links
swiftea links --email mail:123
# Returns: Linked to: event:cal:456, contact:con:789

# Follow links
swiftea context --email mail:123 --depth 2
# Returns: Email + linked event + event attendees (contacts)
```

**Implementation**:
- Links table (bidirectional)
- Link types (related, parent, child, reference)
- Transitive queries (follow chains)

### 3. Unified Metadata

**Purpose**: Same metadata schema works across all data types

**Examples**:
```bash
# Set metadata on any item
swiftea meta set --id mail:123 --field priority_score --value 9
swiftea meta set --id cal:456 --field priority_score --value 9
swiftea meta set --id con:789 --field relationship --value "client"

# Query across modules
swiftea query --meta priority_score ">7" --all
# Returns: High-priority emails, events, contacts, tasks

# Project association
swiftea meta set --query "subject:alpha" --field project --value "ProjectAlpha"
swiftea query --meta project "ProjectAlpha" --all
# Returns: All items tagged with project
```

### 4. Context Assembly

**Purpose**: Gather all related information for a topic/project

**The ClaudEA Superpower**:
```bash
swiftea context --project "ProjectAlpha" --json
```

**Returns**:
```json
{
  "project": "ProjectAlpha",
  "summary": {
    "emails": 47,
    "events": 5,
    "contacts": 8,
    "tasks": 12
  },
  "emails": [...],
  "events": [...],
  "contacts": [...],
  "tasks": [...],
  "links": [...],
  "timeline": [...]  // Chronological view of all items
}
```

**ClaudEA Usage**:
```bash
# ClaudEA generates project status report
claudea report --project "ProjectAlpha" \
  --data "$(swiftea context --project ProjectAlpha --json)"

# ClaudEA finds all related items
claudea related --email mail:123
# Uses: swiftea context --id mail:123 --depth 2 --json
```

### 5. Bulk Operations

**Purpose**: Apply operations across modules

**Examples**:
```bash
# Export everything for a project
swiftea export --project "ProjectAlpha" --all --format markdown

# Update metadata in bulk
swiftea meta update --tag urgent --field priority_score --value 10

# Link all project items
swiftea auto-link --project "ProjectAlpha"
```

---

## CLI Interface

### Command Structure

**Format**: `swiftea <command> [subcommand] [options]`

### Top-Level Commands

```bash
# Module commands
swiftea mail <subcommand>        # Mail operations
swiftea cal <subcommand>         # Calendar operations
swiftea contacts <subcommand>    # Contacts operations
swiftea tasks <subcommand>       # Tasks operations (future)
swiftea notes <subcommand>       # Notes operations (future)

# Cross-module commands
swiftea search <query>           # Search all modules
swiftea query [filters]          # Structured query
swiftea export [options]         # Export data
swiftea link [items]             # Link items
swiftea context [options]        # Gather context

# System commands
swiftea sync [options]           # Sync with Apple data
swiftea meta [subcommand]        # Metadata operations
swiftea config [subcommand]      # Configuration
swiftea status                   # System status
swiftea version                  # Version info
swiftea help [command]           # Help
```

### Common Patterns

**ID Format**: `module:native_id`
- `mail:12345` - Email with ROWID 12345
- `cal:abc123` - Calendar event
- `con:xyz789` - Contact

**Query Syntax**: Gmail-style search
```bash
swiftea search "from:bob subject:urgent after:2026-01-01"
swiftea search "is:unread has:attachment tag:finance"
```

**Pipeline Support**:
```bash
swiftea search "urgent" --json | jq '.[] | .id' | swiftea export --stdin
```

### Global Options

```bash
--verbose, -v          # Verbose output
--quiet, -q            # Minimal output
--json                 # JSON output
--dry-run              # Preview without executing
--config <path>        # Custom config file
```

---

## Configuration

### Config File

**Location**: `~/.config/swiftea/config.json`

**Structure**:
```json
{
  "swiftea": {
    "version": "1.0.0",
    "database": "~/.config/swiftea/swiftea.db",
    "modules": {
      "mail": {
        "enabled": true,
        "priority": 1
      },
      "calendar": {
        "enabled": true,
        "priority": 2
      },
      "contacts": {
        "enabled": true,
        "priority": 3
      }
    }
  },
  "sync": {
    "strategy": "hybrid",
    "watcherEnabled": true,
    "periodicIntervalMinutes": 5,
    "autoSyncOnQuery": true
  },
  "search": {
    "defaultLimit": 100,
    "enableRanking": true,
    "enableSnippets": true,
    "crossModuleByDefault": true
  },
  "export": {
    "defaultFormat": "markdown",
    "outputDirectory": "~/Documents/swiftea-exports",
    "preserveStructure": true,
    "templates": {
      "markdown": "frontmatter-body",
      "json": "detailed"
    }
  },
  "metadata": {
    "autoTagging": true,
    "autoLinking": true
  },
  "logging": {
    "level": "info",
    "file": "~/.config/swiftea/swiftea.log",
    "maxSizeMB": 10
  }
}
```

---

## Development Roadmap

### Phase 1: Foundation (Current)
**Timeline**: Months 1-3
**Status**: In Progress

**Deliverables**:
- ✅ SwiftEA architecture design
- ✅ Core layer implementation
  - SQLite database setup
  - Basic FTS5 search
  - Sync engine (manual + periodic)
  - Export system (markdown/JSON)
- ✅ Mail Module (full implementation)
  - Database mirroring
  - Search functionality
  - Export to markdown/JSON
  - Basic actions (via AppleScript)
- ✅ CLI infrastructure
  - Command routing
  - Argument parsing
  - Output formatting

**Success Criteria**:
- `swiftea mail` fully functional
- Can export 50k emails to markdown
- Search across emails in < 1 second
- ClaudEA can import emails into Obsidian

### Phase 2: Calendar & Contacts
**Timeline**: Months 4-6

**Deliverables**:
- 📅 Calendar Module implementation
  - Event access and search
  - Export to markdown/JSON
  - Event creation/management (AppleScript)
- 👥 Contacts Module implementation
  - Contact access and search
  - Export to markdown/JSON
  - Contact management (AppleScript)
- 🔗 Cross-module linking
  - Link table implementation
  - Automatic link detection
  - Link queries
- 🔍 Unified search improvements
  - Cross-module ranking
  - Faceted results

**Success Criteria**:
- All three modules (mail, calendar, contacts) working
- Can link emails to events and contacts
- Unified search returns results from all modules
- ClaudEA can gather full context for meetings

### Phase 3: Advanced Features
**Timeline**: Months 7-9

**Deliverables**:
- 🎯 Context assembly
  - Project-based context gathering
  - Timeline view
  - Relationship graphs
- 🏷️ Advanced metadata
  - Ad-hoc field addition
  - Bulk metadata operations
  - Metadata templates
- ⚡ Performance optimization
  - Query optimization
  - Caching layer
  - Parallel processing
- 🔄 Real-time sync
  - FSEvents watcher
  - Incremental updates
  - Conflict resolution

**Success Criteria**:
- `swiftea context` provides comprehensive project views
- Handles 100k+ items with sub-second queries
- Real-time sync latency < 5 seconds
- ClaudEA can manage complex multi-module workflows

### Phase 4: AI & Semantic Features
**Timeline**: Months 10-12

**Deliverables**:
- 🧠 Semantic search
  - Vector embeddings (sqlite-vss)
  - Meaning-based queries
  - Automatic categorization
- 🤖 AI-powered features
  - Automatic summarization
  - Priority scoring
  - Smart linking
  - Task extraction
- 📊 Analytics & insights
  - Communication patterns
  - Time tracking
  - Relationship strength
- 🔌 Extended integrations
  - Tasks module (Reminders or markdown)
  - Notes module (Apple Notes or markdown)
  - External tools (Todoist, Notion, etc.)

**Success Criteria**:
- Semantic search "understands" queries
- AI features provide 90%+ accurate insights
- ClaudEA can fully automate email triage
- SwiftEA becomes the central hub for all knowledge work

### Phase 5+: Future Vision
**Timeline**: Year 2+

**Possible Directions**:
- 🌐 Web interface (read-only dashboard)
- 📱 Mobile companion app (query and view)
- 🔗 Integration with other macOS apps (Things, OmniFocus, Bear)
- 🚀 Public API for third-party integrations
- 📦 Plugin system for community extensions
- ☁️ Optional cloud sync (encrypted)

---

## Technical Stack

### Languages & Frameworks

- **Swift 6.0+**: Core language (native macOS, fast, safe)
- **Swift Argument Parser**: CLI argument handling
- **SQLite.swift**: Database access
- **Foundation**: macOS system APIs
- **OSAKit**: AppleScript execution

### Dependencies

**Core**:
- `sqlite3` (system): Database engine
- `swift-argument-parser`: CLI framework
- `SQLite.swift`: Swift SQLite wrapper

**Optional** (future):
- `sqlite-vss`: Vector similarity search
- `swift-markdown`: Markdown parsing/generation
- `swift-crypto`: Encryption (if needed)

### Build System

- **Swift Package Manager** (SPM): Dependency management
- **Xcode**: IDE and build tools (optional)
- **GitHub Actions**: CI/CD
- **Homebrew**: Distribution

---

## Testing Strategy

### Unit Tests
- Core layer components (database, search, sync, export)
- Module-specific logic (parsers, formatters, queries)
- Utility functions

### Integration Tests
- Module interactions with Apple databases
- Cross-module linking
- Sync operations
- Export workflows

### End-to-End Tests
- Full CLI command execution
- Multi-module workflows
- ClaudEA integration scenarios

### Performance Tests
- Search benchmarks (1k, 10k, 50k, 100k items)
- Sync latency measurements
- Export throughput
- Memory profiling

### Test Data
- Synthetic email/calendar/contact datasets
- Real-world anonymized data (with permission)
- Edge cases (corrupted files, missing data, etc.)

---

## Security & Privacy

### Principles

1. **Local-First**: All data stays on user's Mac
2. **Read-Only Source**: Never modify Apple's databases
3. **No Cloud**: No data sent to external servers (unless explicitly requested)
4. **Transparent**: Users can inspect all data
5. **Permissioned**: Request only necessary macOS permissions

### Required Permissions

**Full Disk Access**:
- Required to read Apple Mail/Calendar/Contacts databases
- User must grant in System Settings

**Automation Access**:
- Required for AppleScript operations (send email, create events, etc.)
- User must grant in System Settings

### Data Handling

- **Passwords**: Never stored or accessed (use macOS Keychain)
- **Credentials**: Rely on Mail.app/Calendar.app authentication
- **Logs**: Exclude sensitive content by default
- **Exports**: User controls output location and format

### Threat Model

**In Scope**:
- Unauthorized local access (mitigated by file permissions)
- Data corruption (mitigated by backups and validation)
- Privacy leaks via logs (mitigated by sanitization)

**Out of Scope**:
- Network attacks (no network access)
- Remote exploitation (local-only tool)
- Malware (standard macOS security applies)

---

## Distribution & Installation

### Homebrew (Primary)

```bash
brew tap swiftea/tap
brew install swiftea
```

**Auto-update**: `brew upgrade swiftea`

### Manual Installation

```bash
# Download release
curl -L https://github.com/swiftea/swiftea/releases/latest/download/swiftea-macos.tar.gz -o swiftea.tar.gz

# Extract and install
tar -xzf swiftea.tar.gz
sudo mv swiftea /usr/local/bin/

# Verify
swiftea version
```

### From Source

```bash
git clone https://github.com/swiftea/swiftea.git
cd swiftea
swift build -c release
sudo cp .build/release/swiftea /usr/local/bin/
```

---

## ClaudEA Integration

### Integration Points

**1. Data Access**
```bash
# ClaudEA queries for context
swiftea search "project alpha" --json | claudea analyze

# ClaudEA gets full context
claudea brief --project "Alpha" \
  --data "$(swiftea context --project Alpha --json)"
```

**2. Automated Actions**
```bash
# ClaudEA triages inbox
swiftea search "is:unread" --json | claudea triage | \
  swiftea meta update --stdin --field processing_status

# ClaudEA auto-archives
claudea identify-newsletters --data "$(swiftea search is:unread --json)" | \
  swiftea archive --stdin
```

**3. Knowledge Base Population**
```bash
# Initial setup: export everything to Obsidian vault
swiftea export --all --format markdown --output ~/vault/swiftea/

# Ongoing sync: export new items
swiftea sync --watch
swiftea export --changed --format markdown --output ~/vault/swiftea/
```

**4. Task Extraction**
```bash
# ClaudEA extracts tasks from emails
swiftea search "action item OR TODO" --json | \
  claudea extract-tasks | \
  swiftea tasks import --stdin
```

**5. Meeting Prep**
```bash
# ClaudEA prepares for upcoming meeting
claudea meeting-prep --event "$(swiftea cal get --id cal:123 --json)"
# Returns: Agenda, attendee context, related emails, action items
```

### ClaudEA Skills (Future)

Pre-built ClaudEA commands that leverage SwiftEA:

```bash
claudea /email-triage          # Auto-triage inbox using swiftea
claudea /meeting-prep <event>  # Prepare for meeting
claudea /project-status <name> # Generate project report
claudea /find-related <item>   # Find all related items
claudea /extract-tasks         # Extract tasks from emails/events
```

---

## Success Metrics

### Technical Metrics

**Performance**:
- Search latency < 1 second (100k items)
- Sync latency < 5 seconds
- Export throughput > 100 items/second

**Reliability**:
- 99.9% uptime (no crashes)
- Zero data loss
- < 1 error per 1000 operations

**Scale**:
- Support 100k+ items per module
- Efficient memory usage (< 500MB)
- Fast startup (< 1 second)

### User Metrics

**Adoption**:
- 1,000 active users (Year 1)
- 10,000 active users (Year 2)
- 10% of ClaudEA users using SwiftEA

**Engagement**:
- Daily active users > 50%
- Average 10+ commands per day
- 80%+ retention (30 days)

**Satisfaction**:
- User rating 4.5+/5
- ClaudEA workflows rated 9+/10
- < 5% uninstall rate

---

## Open Questions

1. **Tasks Module**: Apple Reminders vs. Markdown-based vs. Hybrid?
2. **Notes Module**: Apple Notes integration vs. Markdown-only?
3. **Semantic Search**: Which embedding provider (OpenAI, Anthropic, local)?
4. **Distribution**: Mac App Store submission? Or Homebrew-only?
5. **Plugin System**: Allow third-party modules? Or keep core-only?
6. **Cloud Sync**: Optional encrypted cloud backup? Or strictly local?

---

## Contributing

### Development Setup

```bash
# Clone repo
git clone https://github.com/swiftea/swiftea.git
cd swiftea

# Install dependencies
swift package resolve

# Build
swift build

# Run tests
swift test

# Run locally
swift run swiftea help
```

### Code Structure

```
SwiftEA/
├── Sources/
│   ├── SwiftEA/              # CLI entry point
│   ├── SwiftEACore/          # Shared infrastructure
│   ├── MailModule/           # Mail module
│   ├── CalendarModule/       # Calendar module (future)
│   └── ContactsModule/       # Contacts module (future)
├── Tests/
│   ├── SwiftEACoreTests/
│   ├── MailModuleTests/
│   └── IntegrationTests/
├── Documentation/
│   ├── Architecture.md       # This file
│   ├── MailModule.md
│   ├── CalendarModule.md
│   └── API.md
├── Scripts/
│   ├── setup.sh
│   └── release.sh
├── Package.swift
└── README.md
```

### Contribution Guidelines

1. **Fork** the repository
2. **Create** a feature branch (`feature/amazing-feature`)
3. **Write** tests for new functionality
4. **Ensure** all tests pass (`swift test`)
5. **Document** changes in relevant `.md` files
6. **Submit** a pull request

---

## License

**Recommendation**: MIT License or Apache 2.0 (permissive, open-source)

---

## Conclusion

SwiftEA provides the foundational data access layer for ClaudEA to become a true AI-powered executive assistant. By unifying access to email, calendar, contacts, tasks, and notes in a single modular CLI tool, SwiftEA enables workflows that are impossible with fragmented tools.

**Key Architectural Decisions**:
- ✅ Modular monolith (not microservices)
- ✅ Shared core infrastructure
- ✅ Cross-module intelligence built-in
- ✅ CLI-first, ClaudEA-optimized
- ✅ Local-first, privacy-preserving
- ✅ Open-source, extensible

**Next Steps**:
1. Complete Phase 1 (Mail Module + Core)
2. Begin Phase 2 (Calendar + Contacts)
3. Iterate based on ClaudEA usage patterns
4. Build toward unified knowledge graph vision

---

**Document Version**: 1.0
**Last Updated**: 2026-01-06
**Status**: Approved Architecture
**Author**: ClaudEA Team
