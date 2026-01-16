# Coding Conventions

**Analysis Date:** 2026-01-15

## Naming Patterns

**Files:**
- PascalCase for types: `VaultManager.swift`, `MailSync.swift`, `StableIdGenerator.swift`
- Suffixes indicate purpose: `*Tests.swift` for test files, `*Command.swift` for CLI commands, `*Service.swift` for services
- Descriptive compound names: `AppleScriptService.swift`, `EnvelopeIndexDiscovery.swift`, `CachedThreadDetectionService.swift`

**Functions:**
- camelCase for all functions
- Verb-based naming for actions: `generateId()`, `executeQuery()`, `syncMailboxes()`, `detectMailboxMoves()`
- Boolean queries use `is` prefix: `isVault()`, `isValidId()`
- Internal functions use `private` modifier and descriptive names: `performSync()`, `parseDate()`, `reportProgress()`

**Variables:**
- camelCase for all variables
- Property names are descriptive nouns: `mailDatabase`, `envelopeInfo`, `threadDetectionService`
- Boolean properties use `is`, `has`, or modal verbs: `isRead`, `isFlagged`, `hasAttachments`, `watchEnabled`
- Constants use camelCase: `vaultDirName`, `configFileName`, `defaultMailLaunchTimeout`
- Temporary variables are concise: `db`, `sql`, `id`

**Types:**
- PascalCase for all types (classes, structs, enums, protocols)
- Error enums use `Error` suffix: `VaultError`, `MailSyncError`, `AppleScriptError`, `MailDatabaseError`
- Model types are descriptive nouns: `VaultConfig`, `MailMessage`, `SyncResult`, `TrackedMessageInfo`
- Enum cases use camelCase: `.inbox`, `.archive`, `.syncingMessages`, `.automationPermissionDenied`

## Code Style

**Formatting:**
- No automated formatter detected (no .swiftformat, .swiftlint.yml, or swift-format config)
- Consistent 4-space indentation observed
- Opening braces on same line (K&R style): `func sync() throws -> SyncResult {`
- Blank lines separate logical sections within functions
- Properties grouped by visibility (public, private) and purpose

**Linting:**
- No linter configuration detected
- Code follows Swift conventions without enforcement
- Minimal use of force unwrapping (`!`) - prefers optional binding

## Import Organization

**Order:**
1. System frameworks (Foundation, AppKit, EventKit)
2. External dependencies (ArgumentParser, Libsql, GRDB, ICalendarKit, CryptoKit, SQLite3)
3. Internal modules (SwiftEAKit, SwiftEACLI)

**Example:**
```swift
import Foundation
import ArgumentParser
import SwiftEAKit
```

**Path Aliases:**
- No path aliases detected
- Uses explicit module imports with `@testable import SwiftEAKit` in tests

## Error Handling

**Patterns:**
- Custom error enums conforming to `Error` and `LocalizedError`
- Error cases include associated values for context: `.creationFailed(path: String, underlying: Error)`
- All error enums implement `errorDescription` property
- Some errors provide `recoveryGuidance` property for user assistance
- Throwing functions use explicit `throws` keyword
- Error propagation with `try` at call sites
- Error wrapping pattern: catch lower-level errors and wrap in domain-specific errors

**Example:**
```swift
public enum MailSyncError: Error, LocalizedError {
    case sourceConnectionFailed(underlying: Error)
    case sourceDatabaseLocked
    case queryFailed(query: String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .sourceConnectionFailed(let error):
            return "Failed to connect to Apple Mail database: \(error.localizedDescription)"
        case .sourceDatabaseLocked:
            return "Apple Mail database is locked. Please close Mail and try again."
        case .queryFailed(let query, let error):
            return "Query failed: \(query)\nError: \(error.localizedDescription)"
        }
    }
}
```

**Recovery Guidance Pattern:**
```swift
public var recoveryGuidance: String? {
    switch self {
    case .automationPermissionDenied:
        return "Grant permission in System Settings > Privacy & Security > Automation"
    case .mailAppNotResponding:
        return "Ensure Mail.app is running and try opening Mail.app manually"
    default:
        return nil
    }
}
```

## Logging

**Framework:** Standard library `print()` for console output

**Patterns:**
- Progress reporting through callback closures: `onProgress: ((SyncProgress) -> Void)?`
- CLI commands output directly to stdout using `print()`
- No structured logging framework detected
- Error messages include context and suggestions for resolution
- Status messages in commands use emoji sparingly (✓ for success)

**Example:**
```swift
private func reportProgress(_ phase: SyncPhase, _ current: Int, _ total: Int, _ message: String) {
    let progress = SyncProgress(phase: phase, current: current, total: total, message: message)
    onProgress?(progress)
}
```

## Comments

**When to Comment:**
- Public API documentation using `///` triple-slash comments
- Complex algorithms and non-obvious logic
- Important architectural decisions and constraints
- Workarounds with explanation of why they exist
- Minimal inline comments - code is self-documenting through naming

**JSDoc/TSDoc:**
- Swift uses `///` for documentation comments
- Parameter documentation: `/// - Parameter path: The path where the vault should be created`
- Return documentation: `/// - Returns: A stable, deterministic hash-based ID`
- Throws documentation: `/// - Throws: VaultError if initialization fails`
- Section markers with `// MARK: -` for organization

**Example:**
```swift
/// Generate a stable ID for an email message
/// - Parameters:
///   - messageId: RFC822 Message-ID header (preferred)
///   - subject: Email subject
///   - sender: Sender email address
///   - date: Date sent or received
///   - appleRowId: Apple Mail row ID (fallback component)
/// - Returns: A stable, deterministic hash-based ID
public func generateId(
    messageId: String?,
    subject: String?,
    sender: String?,
    date: Date?,
    appleRowId: Int?
) -> String {
    // Implementation
}
```

**MARK Comments:**
```swift
// MARK: - Source Database Operations
// MARK: - Mailbox Sync
// MARK: - Message Sync
// MARK: - Thread Detection
// MARK: - Progress Reporting
```

## Function Design

**Size:** Functions vary from small helpers (5-10 lines) to larger orchestration methods (50-100 lines)

**Parameters:**
- Named parameters for clarity
- Optional parameters use `?` type annotation: `sender: String?`
- Default values for optional behavior: `forceFullSync: Bool = false`
- Multiple parameters grouped logically with vertical alignment
- Use of structs/enums to group related parameters: `MailSyncOptions`, `BatchInsertConfig`

**Return Values:**
- Explicit return types always specified
- Throwing functions return values or throw errors (no Result type observed)
- Multiple return values use tuples or dedicated result types: `SyncResult`, `ThreadDetectionSyncResult`
- `@discardableResult` annotation when return value is optional: `@discardableResult public func initializeVault(...)`

**Example:**
```swift
public func sync(forceFullSync: Bool = false) throws -> SyncResult {
    // Implementation
}

private func processMessage(
    _ row: MessageRow,
    mailBasePath: String
) throws -> (added: Bool, updated: Bool) {
    // Implementation
}
```

## Module Design

**Exports:**
- All public API marked with `public` keyword
- Internal helpers use `private` or `internal` (default)
- Structs and classes expose minimal public surface area
- Extension-based organization for related functionality

**Example:**
```swift
public final class VaultManager {
    public static let vaultDirName = ".swiftea"
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func isVault(at path: String) -> Bool {
        // Implementation
    }

    private func createDatabase(at basePath: String) throws {
        // Implementation
    }
}

extension StableIdGenerator {
    public func isValidId(_ id: String) -> Bool {
        // Implementation
    }
}
```

**Barrel Files:**
- Not applicable in Swift
- Module exports controlled by `public` access control
- Main module file is `SwiftEAKit.swift` with minimal exports

## Concurrency

**Patterns:**
- Types marked `Sendable` for thread-safety: `public struct SyncProgress: Sendable`
- `@unchecked Sendable` used sparingly for legacy types: `public final class MailSync: @unchecked Sendable`
- Synchronous API (no async/await detected in analyzed files)
- Thread-safety through immutability and value types (structs)

## Access Control

**Levels:**
- `public` for API exposed to CLI and external consumers
- `private` for implementation details within a type
- `internal` (default) for module-internal types and functions
- No `open` or `fileprivate` observed

**Pattern:**
```swift
public final class MailSync {
    private let mailDatabase: MailDatabase
    private var sourceDb: OpaquePointer?

    public var options: MailSyncOptions
    public var onProgress: ((SyncProgress) -> Void)?

    public init(...) { }
    public func sync(...) throws -> SyncResult { }

    private func performSync(...) throws -> SyncResult { }
    private func reportProgress(...) { }
}
```

## Type Safety

**Patterns:**
- Strong typing throughout - minimal `Any` types
- Enums for constrained values: `SyncPhase`, `MailboxType`, `AccountType`
- Optional types used appropriately: `String?`, `Int?`, `Date?`
- Type inference used for local variables where clear
- Explicit types for public properties and function signatures

**Example:**
```swift
public enum SyncPhase: String, Sendable {
    case discovering = "Discovering"
    case syncingMessages = "Syncing messages"
    case complete = "Complete"
}

public struct SyncProgress: Sendable {
    public let phase: SyncPhase
    public let current: Int
    public let total: Int
}
```

## Codable Pattern

**Usage:**
- Configuration types conform to `Codable`: `VaultConfig`, `MailSettings`, `CalendarSettings`
- Custom `init(from decoder:)` for backward compatibility
- JSON encoding with `.prettyPrinted` and `.sortedKeys` formatting
- ISO8601 date encoding strategy

**Example:**
```swift
public struct VaultConfig: Codable {
    public let version: String
    public let createdAt: Date
    public var accounts: [BoundAccount]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        accounts = try container.decodeIfPresent([BoundAccount].self, forKey: .accounts) ?? []
    }
}
```

---

*Convention analysis: 2026-01-15*
