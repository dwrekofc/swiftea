# SwiftEA Machine-Interface Design Document
## Agent-First UX Audit & Recommendations

**Date:** 2026-01-12
**Scope:** SwiftEA CLI + SwiftEAKit
**Primary User:** Autonomous AI Agents (ClaudEA integration)
**Secondary User:** Human operators (via agent-friendly interfaces)

**Input Context:**
- `.d-spec/code-review-A.md` (Staff Engineer Audit - Architecture & Reliability)
- `.d-spec/code-review-B.md` (Comprehensive Review - Correctness & Implementation)

---

## Executive Summary

SwiftEA is currently optimized for human CLI interaction with formatted output, implicit error handling, and interactive flows. For autonomous agent consumption (especially ClaudEA), the system requires:

1. **Structured output modes** (JSON) for all commands
2. **Non-interactive execution** with explicit failure modes
3. **Machine-readable error codes** with recovery hints
4. **Context-efficient status snapshots** for agent re-orientation
5. **Idempotency contracts** for safe retry logic

**Critical Agent Friction Score:** 8/10 (High)
Current state would cause frequent agent failures, context exhaustion, and infinite retry loops.

---

## 1. Output Spec: From Visual to Structural

### Current State (Human-Optimized)
| Command | Current Output | Agent Problem |
|---------|---------------|---------------|
| `swiftea mail search` | Formatted table with colors | No schema; agents must parse freeform text |
| `swiftea mail show` | Pretty-printed email with headers | Mixed format; HTML stripping lossy |
| `swiftea vault status` | Human-readable prose ("2 accounts bound") | Requires regex parsing |
| `swiftea sync` | Progress messages + "Success!" | No structured completion signal |
| Error messages | Freeform strings | No error codes; agents hallucinate fixes |

### Recommendations

#### R-1.1: Mandate `--json` Flag for All Commands [P0]
Every command MUST support `--json` output mode with a defined schema.

**Implementation:**
```swift
protocol AgentReadable {
    func toJSON() -> Data
    var schema: JSONSchema { get }
}

// Global flag in ArgumentParser
@Flag(name: .long, help: "Output as JSON (agent-friendly)")
var json: Bool = false
```

**Example Schema (mail search):**
```json
{
  "command": "mail.search",
  "timestamp": "2026-01-12T10:30:00Z",
  "status": "success",
  "data": {
    "results": [
      {
        "id": "msg-abc123",
        "subject": "Re: Quarterly Review",
        "sender": {"name": "Alice", "email": "alice@example.com"},
        "date": "2026-01-10T14:22:00Z",
        "mailbox": "INBOX",
        "accountId": "acc-xyz",
        "isRead": true,
        "isDeleted": false
      }
    ],
    "count": 1,
    "query": "quarterly review"
  }
}
```

**Priority:** P0 (Blocker for agent adoption)
**Files Affected:**
- All command files under `Sources/SwiftEACLI/Commands/`
- Add `JSONEncodable` protocol to `Sources/SwiftEAKit/Core/`

---

#### R-1.2: Stable ID Output Guarantee [P0]
Per code-review-B §137-143, stable IDs are not actually stable (use `rowid` in fallback).

**Agent Requirement:**
```json
{
  "id": "msg-abc123",
  "idStrategy": "messageId",  // or "fallback"
  "idStability": "permanent"   // or "session", "rebuild-unsafe"
}
```

Agents need to know if an ID will survive:
- Apple Mail DB rebuild
- Mailbox migration
- Cross-machine sync

**Recommendation:**
- Add `idStability` enum to output
- Document stability guarantees in JSON schema
- Emit warnings when using fallback IDs

**Priority:** P0 (Data integrity for ClaudEA)
**Files Affected:** `Sources/SwiftEAKit/Modules/MailModule/StableIdGenerator.swift`

---

#### R-1.3: Timestamp Standardization [P1]
Per code-review-B §64, timestamps use Swift's `.description` (locale-dependent).

**Current (Broken for Agents):**
```
dateSent: "2026-01-12 10:30:00 +0000"  // Swift description format
```

**Required (ISO 8601):**
```json
{
  "dateSent": "2026-01-12T10:30:00Z",
  "dateReceived": "2026-01-12T10:30:05Z"
}
```

**Priority:** P1 (Data corruption risk)
**Files Affected:** All commands emitting dates

---

## 2. Eliminating Interactivity: The "Stop" Problem

### Current Interactive Flows (Agent Blockers)

| Command | Interactive Prompt | Agent Problem |
|---------|-------------------|---------------|
| `swiftea vault bind` | AppleScript permission dialog | Hangs waiting for GUI interaction |
| `swiftea mail delete` | "Are you sure? (y/n)" | Agents can't respond to STDIN |
| `swiftea sync` (first run) | Account selection menu | Blocks on numbered input |

### Recommendations

#### R-2.1: Non-Interactive Mode (Global Flag) [P0]
```swift
// Add to root command
@Flag(name: .long, help: "Non-interactive mode (fail on required input)")
var nonInteractive: Bool = false
```

**Behavior:**
- All commands that would prompt MUST fail immediately with `ERR_INTERACTIVE_REQUIRED`
- Error includes exact flags needed to bypass interaction

**Example:**
```json
{
  "status": "error",
  "code": "ERR_INTERACTIVE_REQUIRED",
  "message": "Command requires interactive input",
  "recovery": {
    "hint": "Use --account-id or --all to specify target",
    "examples": [
      "swiftea mail delete --id msg-123 --confirm",
      "swiftea sync --account-id acc-xyz"
    ]
  }
}
```

**Priority:** P0 (Agent execution blocker)
**Files Affected:** All CLI commands, `Sources/SwiftEACLI/Commands/*.swift`

---

#### R-2.2: Explicit Confirmation Flags [P0]
Replace all `y/n` prompts with flags:
- `--confirm` or `--yes` for destructive actions
- `--force` for override scenarios
- `--dry-run` for preview mode

**Example:**
```bash
# Current (blocks agent)
$ swiftea mail delete --query "spam"
> Delete 42 messages? (y/n): _

# Agent-friendly
$ swiftea mail delete --query "spam" --confirm --json
{"status": "success", "deleted": 42}
```

**Priority:** P0
**Files Affected:** `MailCommand.swift` (delete, archive, move)

---

## 3. Error Ergonomics & Self-Correction

### Current Error Handling (Agent Hostile)

Per code-review-A §53-55, AppleScript errors are swallowed:
```swift
// Current
func discoverAllAccounts() -> [Account] {
    do {
        return try runAppleScript()
    } catch {
        return []  // Silent failure!
    }
}
```

**Agent Impact:** Agent sees "0 accounts" and can't diagnose permission issues vs AppleScript failures vs legitimate empty state.

### Recommendations

#### R-3.1: Functional Error Code Taxonomy [P0]

Define error code hierarchy with recovery hints:

```swift
enum SwiftEAError: Error, Codable {
    case ERR_AUTH_001(hint: String)    // AppleScript permission denied
    case ERR_SYNC_001(hint: String)    // Apple Mail DB not found
    case ERR_SYNC_002(hint: String)    // Mirror DB corrupted
    case ERR_SQL_001(hint: String)     // SQL injection detected
    case ERR_STATE_001(hint: String)   // Vault not initialized
    case ERR_STATE_002(hint: String)   // No accounts bound
}
```

**JSON Output:**
```json
{
  "status": "error",
  "code": "ERR_AUTH_001",
  "message": "AppleScript permission denied",
  "recovery": {
    "hint": "Grant 'Automation' permission in System Settings → Privacy",
    "docUrl": "https://swiftea.dev/docs/permissions",
    "canRetry": false,
    "requiresHumanIntervention": true
  },
  "context": {
    "command": "vault.bind",
    "args": ["--account", "alice@example.com"]
  }
}
```

**Priority:** P0 (Agent infinite loops without this)
**Files Affected:**
- New `Sources/SwiftEAKit/Core/Errors.swift`
- All command error handling

---

#### R-3.2: Recovery Logic Map [P0]

| Error Code | Current Behavior | Recovery Hint for Agent |
|------------|-----------------|------------------------|
| `ERR_AUTH_001` | Silent → empty accounts | "Run 'swiftea doctor --permissions' to check" |
| `ERR_SYNC_001` | Crash or generic error | "Verify Apple Mail is configured; check ~/Library/Mail" |
| `ERR_SYNC_002` | Partial sync succeeds | "Run 'swiftea vault rebuild --force' to reset mirror" |
| `ERR_SQL_001` | Query fails mid-sync | "This is a bug; report with --debug-sql output" |
| `ERR_STATE_001` | "Vault not found" | "Run 'swiftea vault init' first" |
| `ERR_STATE_002` | "No accounts bound" | "Run 'swiftea vault bind' to configure accounts" |

**Implementation:**
```swift
extension SwiftEAError {
    var recoveryHint: RecoveryHint {
        switch self {
        case .ERR_AUTH_001:
            return RecoveryHint(
                command: "swiftea doctor --permissions",
                requiresHuman: true,
                docUrl: "https://swiftea.dev/docs/permissions"
            )
        // ...
        }
    }
}
```

**Priority:** P0
**Files Affected:** All modules emitting errors

---

#### R-3.3: Observability for Swallowed Errors [P1]

Per code-review-A §104-107, parse errors are swallowed during sync.

**Agent Requirement:** Emit warnings in JSON output even on "success":
```json
{
  "status": "success",
  "data": {"messagesSynced": 1234},
  "warnings": [
    {
      "code": "WARN_PARSE_001",
      "message": "Failed to parse 3 .emlx files",
      "affectedIds": ["msg-abc", "msg-def", "msg-ghi"],
      "hint": "Bodies will be missing for these messages"
    }
  ]
}
```

**Priority:** P1 (Data loss detection)
**Files Affected:** `MailSync.swift`, all commands

---

## 4. Token Efficiency & Context Density

### Current Verbosity Issues

| Output Type | Human Format | Token Cost | Agent Need |
|-------------|-------------|-----------|------------|
| Progress logs | Animated spinner + "Syncing mailbox 3/10..." | 50+ tokens/line | Silent mode |
| Error stack traces | Full Swift backtrace | 500+ tokens | Error code only |
| Success messages | "✅ Done! Synced 1,234 messages in 3.2s" | 15 tokens | `{"status": "ok"}` (3 tokens) |

### Recommendations

#### R-4.1: Compact Mode (--compact) [P1]
```bash
# Verbose (human)
$ swiftea mail sync
Discovering mailboxes...
Found 12 mailboxes
Syncing "INBOX" (1/12)...
  - 543 new messages
  - 12 deleted
Syncing "Sent" (2/12)...
  ...
✅ Done! Synced 1,234 messages in 3.2s

# Compact (agent)
$ swiftea mail sync --compact --json
{"status":"ok","synced":1234,"duration":3.2}
```

**Implementation:**
- Suppress all progress output in compact mode
- Emit single-line JSON result only
- Log verbosity to file, not stdout

**Priority:** P1 (Context window optimization)
**Files Affected:** All commands with progress output

---

#### R-4.2: Delta Output for Status Commands [P1]

**Current:**
```bash
$ swiftea status
Vault: /path/to/vault
Accounts:
  - alice@example.com (Mail, Calendar)
  - bob@work.com (Mail)
Mail: 12,543 messages, 2,341 unread
Last sync: 2026-01-12 10:30:00
```

**Agent-Optimized (only changes since last check):**
```json
{
  "status": "ok",
  "delta": {
    "mail": {
      "unread": "+12",  // 12 new unread
      "total": "12543"  // absolute count
    },
    "lastSync": "2026-01-12T10:30:00Z"
  }
}
```

**Priority:** P1
**Files Affected:** `StatusCommand.swift`

---

## 5. State Visibility & Re-Orientation

### Agent Re-Orientation Problem

**Scenario:** Agent loses context mid-session (e.g., context window compaction). Needs to answer:
1. "What vault am I in?"
2. "What accounts are bound?"
3. "What's the sync state?"
4. "Are there any background operations running?"

**Current Solution:** Agent must run 4+ commands and parse freeform output.

### Recommendations

#### R-5.1: System Snapshot Command [P0]
```bash
$ swiftea inspect --json
```

**Output (Single JSON Blob):**
```json
{
  "version": "1.2.0",
  "environment": {
    "vaultPath": "/path/to/vault",
    "configPath": "~/.config/swiftea",
    "macOS": "15.2",
    "swiftVersion": "6.0"
  },
  "vault": {
    "initialized": true,
    "version": 1,
    "accounts": [
      {
        "id": "acc-xyz",
        "email": "alice@example.com",
        "services": ["mail", "calendar"],
        "lastSync": "2026-01-12T10:30:00Z"
      }
    ]
  },
  "sync": {
    "status": "idle",  // or "running", "failed"
    "daemonRunning": true,
    "lastRun": "2026-01-12T10:30:00Z",
    "nextRun": "2026-01-12T11:00:00Z"
  },
  "health": {
    "mirrorDbIntact": true,
    "appleMailReachable": true,
    "permissions": {
      "automation": true,
      "fullDiskAccess": false
    }
  }
}
```

**Priority:** P0 (Agent orientation)
**Files Affected:** New `InspectCommand.swift`

---

#### R-5.2: Persistent Operation Log [P1]

**Problem:** Per code-review-A §76-79, concurrent syncs can interleave without detection.

**Agent Need:** Query "what operations are running or failed recently?"

```bash
$ swiftea operations --json
```

**Output:**
```json
{
  "active": [
    {
      "id": "op-12345",
      "command": "mail.sync",
      "startedAt": "2026-01-12T10:30:00Z",
      "pid": 54321
    }
  ],
  "recent": [
    {
      "id": "op-12344",
      "command": "mail.sync",
      "status": "success",
      "duration": 3.2,
      "completedAt": "2026-01-12T10:29:00Z"
    }
  ]
}
```

**Priority:** P1
**Files Affected:** New operation tracking layer

---

## 6. Agent Friction Priority Matrix

### P0 (Critical - Agent Cannot Function)

| ID | Issue | Current Impact | Recommendation | Files |
|----|-------|---------------|----------------|-------|
| AF-1 | No JSON output mode | Agent must parse freeform text → high error rate | R-1.1: `--json` flag | All commands |
| AF-2 | Interactive prompts block execution | Agent hangs indefinitely | R-2.1, R-2.2: Non-interactive mode | MailCommand, VaultCommand |
| AF-3 | Errors lack machine codes | Agent hallucinates fixes → infinite loops | R-3.1: Error taxonomy | All error handling |
| AF-4 | No state snapshot | Agent cannot re-orient after context loss | R-5.1: `inspect` command | New file |
| AF-5 | Unstable IDs | ClaudEA loses message references across syncs | R-1.2: Stable ID contract | StableIdGenerator.swift |

**Estimated Agent Success Rate with P0s unfixed:** 20%
**Estimated Agent Success Rate with P0s fixed:** 85%

---

### P1 (High - Agent Performance Degraded)

| ID | Issue | Current Impact | Recommendation | Files |
|----|-------|---------------|----------------|-------|
| AF-6 | Verbose output exhausts context | Agent hits token limits on large operations | R-4.1: Compact mode | All commands |
| AF-7 | Silent failures | Agent thinks operation succeeded despite errors | R-3.3: Warnings in JSON | MailSync.swift |
| AF-8 | No operation visibility | Agent can't detect concurrent/failed syncs | R-5.2: Operation log | New subsystem |

---

### P2 (Medium - Agent Workarounds Exist)

| ID | Issue | Current Impact | Recommendation | Files |
|----|-------|---------------|----------------|-------|
| AF-9 | Non-ISO timestamps | Agent must normalize dates → risk of parsing errors | R-1.3: ISO 8601 only | All date outputs |
| AF-10 | Status output not delta-based | Agent wastes tokens on redundant state | R-4.2: Delta mode | StatusCommand.swift |

---

## 7. Implementation Phases

### Phase 1: Unblock Agent Execution (P0s)
**Goal:** Make SwiftEA usable by agents without constant failures.

**Deliverables:**
1. `--json` flag for all commands (R-1.1)
2. `--non-interactive` mode (R-2.1)
3. Error code taxonomy (R-3.1)
4. `swiftea inspect` command (R-5.1)
5. Stable ID contract fix (R-1.2)

**Duration:** ~2-3 weeks (estimated)

---

### Phase 2: Optimize Agent Performance (P1s)
**Goal:** Reduce agent token usage and improve reliability.

**Deliverables:**
1. `--compact` mode (R-4.1)
2. Warnings in JSON output (R-3.3)
3. Operation log (R-5.2)

**Duration:** ~1-2 weeks

---

### Phase 3: Polish (P2s)
**Goal:** Eliminate edge cases and improve agent ergonomics.

**Deliverables:**
1. ISO 8601 timestamps (R-1.3)
2. Delta status output (R-4.2)

**Duration:** ~1 week

---

## 8. Testing Strategy for Agent-UX

### Test Harness Requirements

1. **Synthetic Agent Simulator:**
   - Script that calls SwiftEA CLI as an agent would
   - Parse JSON outputs, validate schemas
   - Retry on errors using recovery hints
   - Measure: success rate, token usage, retry count

2. **Non-Interactive Validation:**
   - All commands must work with `--non-interactive --json`
   - No STDIN reads allowed
   - No ANSI color codes in JSON mode

3. **Error Recovery Testing:**
   - Trigger each error code deliberately
   - Verify recovery hint is actionable
   - Ensure agents can fix and retry

---

## 9. Documentation Requirements

### For Agents (JSON Schemas)

1. **OpenAPI/JSON Schema Spec:**
   - Document every command's JSON output schema
   - Include error codes and recovery hints
   - Publish at `swiftea.dev/api/`

2. **Error Code Reference:**
   - Comprehensive list of all `ERR_*` codes
   - For each: cause, recovery hint, retry policy

3. **State Machine Diagrams:**
   - Document valid command sequences
   - E.g., "Must run `vault init` before `vault bind`"

---

## 10. Breaking Changes & Migration

### Backwards Compatibility Strategy

1. **Dual Output Mode (Temporary):**
   - Default: Human-readable (existing behavior)
   - `--json`: Agent-friendly
   - Deprecation: Remove human mode in v2.0

2. **Error Format Migration:**
   - Phase 1: Add error codes alongside existing messages
   - Phase 2: Require error codes in all responses
   - Phase 3: Remove freeform error strings

3. **Interactive Prompts:**
   - Phase 1: Add `--yes` / `--confirm` flags
   - Phase 2: Warn when interactive mode used
   - Phase 3: Require explicit flag in v2.0

---

## Appendix A: Comparison Table

| Feature | Human Preference | AI Agent Preference | Current State | Gap |
|---------|-----------------|---------------------|---------------|-----|
| Output Format | Formatted tables, colors | JSON with schema | Tables only | High |
| Timestamps | Locale-aware | ISO 8601 | Swift `.description` | High |
| Errors | Helpful prose | Error code + recovery hint | Freeform strings | Critical |
| Progress | Animated spinners | Silent or single summary | Spinners | Medium |
| Confirmations | Interactive prompts | `--confirm` flags | Interactive only | Critical |
| State visibility | `status` command | `inspect --json` with full snapshot | Partial only | High |
| Stable IDs | N/A | Guaranteed permanence | Unstable (uses rowid) | Critical |

---

## Appendix B: Error Code Quick Reference

| Code | Category | Requires Human | Can Retry | Recovery Command |
|------|----------|----------------|-----------|-----------------|
| `ERR_AUTH_001` | Permissions | Yes | No | `swiftea doctor --permissions` |
| `ERR_SYNC_001` | Configuration | No | Yes | `swiftea vault status --json` |
| `ERR_SYNC_002` | Data integrity | No | Yes | `swiftea vault rebuild` |
| `ERR_SQL_001` | Internal | No | No | Report bug |
| `ERR_STATE_001` | Configuration | No | No | `swiftea vault init` |
| `ERR_STATE_002` | Configuration | No | No | `swiftea vault bind` |

---

## Summary

**Current Agent-Readiness Score: 2/10**
**Target Agent-Readiness Score: 9/10**

**Critical Path:**
1. Implement P0 recommendations (5 items)
2. Add JSON schema documentation
3. Test with synthetic agent workloads
4. Measure: retry rate < 5%, success rate > 95%

**ROI:** With P0s fixed, ClaudEA integration becomes viable. Current state would require constant human intervention and fail >50% of operations.
