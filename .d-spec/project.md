# Project Context

## Purpose
**SwiftEA (Swift Executive Assistant)** is a unified CLI tool that provides programmatic access to macOS personal information management (PIM) data—email, calendar, contacts, tasks, and notes. Built as a modular monolith, SwiftEA serves as the data access layer for ClaudEA, enabling AI-powered executive assistant workflows across the user's entire knowledge base.

**Core Philosophy**: One tool, unified knowledge graph, modular architecture.

**Primary Goals**:
1. **Unified Knowledge Access**: Single interface to query across all personal data types
2. **Cross-Module Intelligence**: Link and search across emails, events, contacts, tasks, and notes
3. **ClaudEA Integration**: Provide the foundation for AI-powered workflows
4. **Data Liberation**: Export all data to open formats (markdown, JSON)
5. **Custom Intelligence Layer**: Add AI insights and metadata across all data types

**Non-Goals**:
- ❌ Replace native macOS apps (Mail.app, Calendar.app)
- ❌ Build GUI applications
- ❌ Sync with cloud services (we use macOS as the sync layer)
- ❌ Cross-platform support (macOS only, leveraging Apple's ecosystem)

## Tech Stack
- **Swift 6.0+**: Core language (native macOS, fast, safe)
- **Swift Argument Parser**: CLI argument handling
- **libSQL**: Core database engine for SwiftEA/ClaudEA backend and all mirror databases (FTS5 for search)
- **Foundation**: macOS system APIs
- **OSAKit**: AppleScript execution

**Development Tools**:
- Swift Package Manager (SPM) for dependency management
- Xcode (optional, for development)
- Homebrew for distribution
- GitHub Actions for CI/CD

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
- **Layered Architecture**: Core layer (shared infrastructure) + Module layer (data sources) + CLI layer (interface)
- **Repository Pattern**: For data access abstraction
- **Command Pattern**: For CLI command implementations
- **Observer Pattern**: For change detection and sync

**Module Structure**:
- Each module implements `SwiftEAModule` protocol
- Modules are independent but share core infrastructure
- Modules can be enabled/disabled via configuration

### Testing Strategy
- **Unit Tests**: Core components, module-specific logic, utilities
- **Integration Tests**: Module interactions with Apple databases
- **End-to-End Tests**: Full CLI command execution
- **Performance Tests**: Search benchmarks, sync latency, export throughput
- **Test Data**: Synthetic datasets + real-world anonymized data

**Testing Tools**:
- XCTest framework
- Quick/Nimble (if needed for BDD)
- Performance measurement tools

### Git Workflow
- **Branching**: Feature branches from `main`
- **Commits**: Conventional commits with semantic prefixes
- **PRs**: Required for all changes, with code review
- **Versioning**: Semantic versioning (MAJOR.MINOR.PATCH)

**Commit Message Format**:
```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`
**Scopes**: `core`, `mail`, `calendar`, `contacts`, `cli`, `docs`, `build`

## Domain Context

### macOS Personal Information Management (PIM)
- **Apple Mail**: Uses SQLite database (`Envelope Index`) + `.emlx` files (note: Apple's source databases are SQLite)
- **Apple Calendar**: Uses SQLite database (`Calendar Cache`) + `.calendar` bundles
- **Apple Contacts**: Uses SQLite database (`AddressBook-v22.abcddb`) + vCards
- **Apple Reminders**: SQLite database for tasks (potential integration)
- **Apple Notes**: SQLite database for notes (potential integration)

### Data Access Methods
1. **Direct Database Access**: Read-only access to Apple's SQLite databases
2. **File System Access**: Read `.emlx` files, `.calendar` bundles, vCards
3. **AppleScript Automation**: Write operations (send, create, update, delete)
4. **Mirror Databases**: SwiftEA maintains its own libSQL database with custom metadata

### Security & Privacy
- **Full Disk Access**: Required to read Apple's databases
- **Automation Access**: Required for AppleScript operations
- **Local-First**: All data stays on user's Mac
- **No Cloud**: No data sent to external servers unless explicitly requested

### ClaudEA Integration
SwiftEA is designed as the data access layer for ClaudEA (AI executive assistant). ClaudEA uses SwiftEA to:
- Query user's personal data across all modules
- Export data to markdown/JSON for AI processing
- Execute actions via CLI commands
- Build context for AI-powered workflows

## Important Constraints

### Technical Constraints
1. **Read-Only Source Access**: Never modify Apple's databases directly
2. **macOS-Only**: Leverages macOS-specific APIs and file locations
3. **Permission Requirements**: Users must grant Full Disk Access and Automation permissions
4. **Performance**: Must handle large datasets (100k+ items per module)
5. **Data Integrity**: Must maintain sync between Apple data and mirror database

### Business Constraints
1. **Privacy-First**: No telemetry or data collection by default
2. **Open Source**: All code must be inspectable and auditable
3. **User Control**: Users must control what data is exported and where
4. **Backwards Compatibility**: Major version changes should have migration paths

### Development Constraints
1. **Swift-Only**: Core implementation must be in Swift
2. **SPM-Compatible**: Must build with Swift Package Manager
3. **Homebrew Distribution**: Primary distribution method
4. **Documentation-First**: All features must be documented

## External Dependencies

### Core Dependencies
- **libSQL**: Swift wrapper for libSQL (SQLite-compatible)
- **Swift Argument Parser**: CLI framework
- **libSQL**: Database engine for SwiftEA's mirror database

### Optional Dependencies (Future)
- **libSQL vector extensions**: Vector similarity search for semantic search
- **SwiftCrypto**: For encryption if needed
- **SwiftMarkdown**: For markdown parsing/generation

### macOS System Dependencies
- **Foundation Framework**: System APIs
- **OSAKit**: AppleScript execution
- **FSEvents**: File system change notifications
- **Security Framework**: Keychain access (if needed)

### ClaudEA Ecosystem Dependencies
- **Obsidian**: Target for markdown exports
- **libSQL FTS5**: Full-text search capabilities
- **JSON**: Data interchange format for AI workflows

### Integration Points
- **Apple Mail**: Via SQLite + `.emlx` files + AppleScript
- **Apple Calendar**: Via SQLite + `.calendar` + AppleScript
- **Apple Contacts**: Via SQLite + vCards + AppleScript
- **Apple Reminders**: Potential future integration
- **Apple Notes**: Potential future integration
