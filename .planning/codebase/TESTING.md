# Testing Patterns

**Analysis Date:** 2026-01-15

## Test Framework

**Runner:**
- XCTest (Apple's native testing framework)
- Config: `Package.swift` (Swift Package Manager)

**Assertion Library:**
- XCTest assertions (`XCTAssertEqual`, `XCTAssertTrue`, `XCTAssertNotNil`, etc.)

**Run Commands:**
```bash
swift test                    # Run all tests
swift test --filter <name>    # Run specific test
swift build                   # Build without running tests
```

**CI Integration:**
- Tests are quality gates for ralph-tui workflow
- All tasks must pass `swift build` and `swift test` before completion

## Test File Organization

**Location:**
- Co-located in separate `Tests/` directory at package root
- Mirror structure of source: `Tests/SwiftEAKitTests/` and `Tests/SwiftEACLITests/`

**Naming:**
- Test files named `*Tests.swift`
- Test class names match file: `final class MailSyncTests: XCTestCase`
- Mirror source file names: `MailSync.swift` → `MailSyncTests.swift`

**Structure:**
```
Tests/
├── SwiftEAKitTests/          # Tests for SwiftEAKit module
│   ├── MailSyncTests.swift
│   ├── StableIdGeneratorTests.swift
│   ├── AppleScriptServiceTests.swift
│   ├── ThreadDetectionServiceTests.swift
│   └── VaultManagerTests.swift
└── SwiftEACLITests/          # Tests for CLI commands
    ├── MailCommandTests.swift
    └── MailCommandValidationTests.swift
```

## Test Structure

**Suite Organization:**
```swift
import XCTest
@testable import SwiftEAKit

final class StableIdGeneratorTests: XCTestCase {
    var generator: StableIdGenerator!

    override func setUp() {
        super.setUp()
        generator = StableIdGenerator()
    }

    override func tearDown() {
        generator = nil
        super.tearDown()
    }

    // MARK: - ID Generation with Message-ID

    func testGenerateIdWithMessageId() {
        let id = generator.generateId(
            messageId: "<test123@example.com>",
            subject: nil,
            sender: nil,
            date: nil,
            appleRowId: nil
        )

        XCTAssertEqual(id.count, 32, "ID should be 32 characters")
        XCTAssertTrue(generator.isValidId(id), "Generated ID should be valid")
    }

    // Additional tests...
}
```

**Patterns:**
- Test classes inherit from `XCTestCase`
- Test methods prefixed with `test`: `func testGenerateIdWithMessageId()`
- `setUp()` creates test fixtures before each test
- `tearDown()` cleans up after each test
- `// MARK:` comments organize tests by feature area
- Instance variables for system under test (often force unwrapped `!` in test context)

## Mocking

**Framework:** Manual mocking (no third-party mocking library detected)

**Patterns:**
```swift
/// Mock FileManager that simulates missing Apple Mail directory
private class MockFileManagerNoMail: FileManager {
    override var homeDirectoryForCurrentUser: URL {
        return URL(fileURLWithPath: NSTemporaryDirectory())
    }

    override func fileExists(atPath path: String) -> Bool {
        return false
    }

    override func isReadableFile(atPath path: String) -> Bool {
        return false
    }
}

// Usage
let mockFileManager = MockFileManagerNoMail()
let mockDiscovery = EnvelopeIndexDiscovery(fileManager: mockFileManager)
let sync = MailSync(mailDatabase: mailDatabase, discovery: mockDiscovery)
```

**What to Mock:**
- External dependencies (FileManager, system services)
- Services that require system state (Apple Mail, EventKit)
- Network or file I/O operations
- Time-dependent operations (use fixed `Date(timeIntervalSince1970: 1736177400)`)

**What NOT to Mock:**
- Value types (structs) - use real instances
- Pure functions with no side effects
- Database operations in integration tests (use temporary databases)

## Fixtures and Factories

**Test Data:**
```swift
// Inline fixture creation
let testTime = Date(timeIntervalSince1970: 1736177400)
let message = MailMessage(
    id: "test-1",
    appleRowId: 100,
    subject: "Test Subject",
    senderName: "John Doe",
    senderEmail: "john@example.com",
    isRead: true,
    isFlagged: false
)

// File-based fixtures for .emlx parsing
let emlxContent = """
241
Message-ID: <test123@example.com>
From: John Doe <john@example.com>
Subject: Simple Test Email

This is a test body.
"""
let testFilePath = (testDir as NSString).appendingPathComponent("test.emlx")
try emlxContent.write(toFile: testFilePath, atomically: true, encoding: .utf8)
```

**Location:**
- Fixtures created inline within test methods
- File fixtures written to temporary directories
- Temporary database created per test suite in `setUp()`

**Pattern:**
```swift
override func setUp() {
    super.setUp()
    testDir = NSTemporaryDirectory() + "swiftea-test-\(UUID().uuidString)"
    try! FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)

    let dbPath = (testDir as NSString).appendingPathComponent("test.db")
    mailDatabase = MailDatabase(databasePath: dbPath)
    try! mailDatabase.initialize()
}

override func tearDown() {
    mailDatabase.close()
    try? FileManager.default.removeItem(atPath: testDir)
    super.tearDown()
}
```

## Coverage

**Requirements:** No explicit coverage target enforced in configuration

**View Coverage:**
```bash
swift test --enable-code-coverage
# Coverage reports in .build/debug/codecov/
```

**Practice:**
- Comprehensive unit tests for core logic (ID generation, parsing, validation)
- Integration tests for database operations
- Error path testing (verify all error cases throw correctly)
- Edge case coverage (empty strings, nil values, special characters)

## Test Types

**Unit Tests:**
- Test individual functions and methods in isolation
- Use mocks for dependencies
- Fast execution (no I/O, no system dependencies)
- Examples: `StableIdGeneratorTests`, `ThreadIDGeneratorTests`, `CalendarIdGeneratorTests`

**Integration Tests:**
- Test components working together
- Use real temporary databases
- May interact with filesystem (but not production data)
- Examples: `MailSyncTests`, `MailDatabaseTests`, `VaultManagerTests`

**E2E Tests:**
- Not detected in analyzed test files
- CLI commands tested through `MailCommandTests`
- Limited E2E due to dependency on system services (Mail.app, EventKit)

## Common Patterns

**Async Testing:**
- Not observed (codebase uses synchronous APIs)
- If needed, would use `XCTestExpectation`:
```swift
let expectation = self.expectation(description: "Async operation")
service.performAsync {
    expectation.fulfill()
}
waitForExpectations(timeout: 5.0)
```

**Error Testing:**
```swift
func testSyncFailsWithoutAppleMail() {
    let mockFileManager = MockFileManagerNoMail()
    let mockDiscovery = EnvelopeIndexDiscovery(fileManager: mockFileManager)
    let sync = MailSync(mailDatabase: mailDatabase, discovery: mockDiscovery)

    XCTAssertThrowsError(try sync.sync()) { error in
        XCTAssertTrue(
            error is EnvelopeDiscoveryError || error is MailSyncError,
            "Expected discovery or sync error, got \(type(of: error))"
        )
    }
}
```

**Validation Testing:**
```swift
func testIsValidIdWithValidId() {
    let validId = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
    XCTAssertTrue(generator.isValidId(validId), "32 hex chars should be valid")
}

func testIsValidIdWithTooShort() {
    let shortId = "abc123"
    XCTAssertFalse(generator.isValidId(shortId), "Short ID should be invalid")
}
```

**Equality Testing:**
```swift
func testGenerateIdWithMessageIdIsStable() {
    let id1 = generator.generateId(messageId: "<stable@example.com>", ...)
    let id2 = generator.generateId(messageId: "<stable@example.com>", ...)

    XCTAssertEqual(id1, id2, "Same Message-ID should produce same ID")
}
```

**Boundary Testing:**
```swift
func testSyncProgressPercentageWithZeroTotal() {
    let progress = SyncProgress(phase: .discovering, current: 0, total: 0, message: "")
    XCTAssertEqual(progress.percentage, 0.0)
}

func testGenerateIdWithNoDataFallsBackToUUID() {
    let id = generator.generateId(
        messageId: nil,
        subject: nil,
        sender: nil,
        date: nil,
        appleRowId: nil
    )
    XCTAssertEqual(id.count, 32, "UUID fallback should be 32 chars")
}
```

## Test Naming

**Pattern:** `test<FunctionName><Scenario><ExpectedOutcome>`

**Examples:**
- `testGenerateIdWithMessageId` - Test the happy path
- `testGenerateIdWithMessageIdIsStable` - Test deterministic behavior
- `testGenerateIdNormalizesMessageId` - Test specific transformation
- `testIsValidIdWithTooShort` - Test validation with invalid input
- `testSyncFailsWithoutAppleMail` - Test error condition

## Assertions

**Common XCTest Assertions:**
```swift
XCTAssertEqual(actual, expected, "Description")
XCTAssertNotEqual(actual, unexpected)
XCTAssertTrue(condition, "Description")
XCTAssertFalse(condition)
XCTAssertNil(optional)
XCTAssertNotNil(optional, "Description")
XCTAssertThrowsError(try expression) { error in
    // Verify error type and details
}
```

**Assertion Messages:**
- Optional message parameter for failure context
- Used for complex assertions: `"ID should be 32 characters"`
- Describes expected behavior, not implementation

## Test Organization

**MARK Comments:**
```swift
// MARK: - ID Generation with Message-ID
// MARK: - ID Generation with Header Fallback
// MARK: - ID Validation
// MARK: - Edge Cases
// MARK: - Integration Tests: Script Generation Validation
```

**Logical Grouping:**
- Tests grouped by feature area using `// MARK:`
- Related tests placed together (happy path, edge cases, error cases)
- Setup/teardown at top of class
- Helper methods at bottom (if any)

## Dependencies in Tests

**@testable Import:**
```swift
import XCTest
@testable import SwiftEAKit
```

**Purpose:**
- Access internal APIs for testing
- Test implementation details when necessary
- Verify private behavior through public API where possible

## Temporary Resources

**Pattern:**
```swift
var testDir: String!

override func setUp() {
    super.setUp()
    testDir = NSTemporaryDirectory() + "swiftea-test-\(UUID().uuidString)"
    try! FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
}

override func tearDown() {
    try? FileManager.default.removeItem(atPath: testDir)
    testDir = nil
    super.tearDown()
}
```

**Guidelines:**
- Create unique temporary directories per test suite
- Clean up in `tearDown()` to avoid leaking resources
- Use `NSTemporaryDirectory()` for temporary file storage
- Generate unique names with `UUID()` to prevent collisions

## Test Data Strategies

**Fixed Timestamps:**
```swift
let testTime = Date(timeIntervalSince1970: 1736177400)
```

**Unique IDs:**
```swift
let testFilePath = (testDir as NSString).appendingPathComponent("test-\(UUID()).emlx")
```

**Deterministic Data:**
- Use fixed values for reproducibility
- Avoid random data in tests
- Use specific test strings: `"test@example.com"`, `"Test Subject"`

## Quality Gates

**Required for Task Completion:**
```
- [ ] `swift build` passes
- [ ] `swift test` passes
```

**Practice:**
- All code changes must include tests
- Tests written first (TDD observed in some areas)
- No commits without passing tests
- CI enforces quality gates via ralph-tui

---

*Testing analysis: 2026-01-15*
