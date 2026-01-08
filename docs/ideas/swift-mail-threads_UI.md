# Swift Mail CLI - Threaded Conversations & UI Vision

## Summary
This document captures key decisions for implementing email conversation threading in Swift Mail CLI and outlines the vision for future HTML/CSS/JS email GUI.

## Current Decisions (Implemented Now)

### 1. Threading Strategy ✅
**Decision:** Header-based threading for maximum accuracy
- Uses Message-ID, References, In-Reply-To headers from emails
- Follows RFC 5322 email standards precisely
- Handles forwarded emails correctly
- Primary focus for MVP implementation

**Advantages:**
- Most accurate threading method
- Handles complex email chains correctly
- Standard-compliant approach
- Best for professional email workflows

### 2. User Interface ✅
**Decision:** Both CLI-first + enhanced export approach
- CLI commands for quick conversation viewing
- Enhanced markdown/JSON exports for ClaudEA workflows
- Thread context included in project summaries

**CLI Commands to Implement:**
```bash
# List all conversations
swiftea mail threads [--limit N] [--sort date|count] [--participant email]

# View specific conversation
swiftea mail thread --id thread-123 [--format text|json|markdown]

# Export threads to Obsidian vault
swiftea mail export-threads --output ~/vault/email-threads/
```

### 3. Performance Approach ✅
**Decision:** Fast & Simple threading for large inboxes
- Basic header parsing only for speed
- Designed for 100k+ email databases
- Minimal processing overhead
- Prioritizes large inbox performance over edge cases

**Performance Targets:**
- Thread detection on 100k emails: < 5 seconds
- Conversation viewing: instant response
- Export operations: < 1 second per 100 emails

## Future Vision: HTML/CSS/JS Email GUI

### 4. Obsidian Email Plugin (Future Phase)
**Goal:** Create Gmail/Notion Mail-like interface for email triage
- Built with HTML/CSS/JS as web component
- Deployed as Obsidian plugin
- Connects to Swift Mail CLI commands for actions

**GUI Features:**
- **Conversation View**: Threaded email interface
- **Triage Actions**: Tag, move, delete, archive, flag
- **Search & Filter**: Advanced email filtering
- **Quick Actions**: Keyboard shortcuts for common tasks
- **Dark/Light Theme**: Match Obsidian appearance

**Technical Architecture:**
```
Obsidian Plugin (HTML/CSS/JS)
    ↓
Swift Mail CLI Backend API
    ↓
libSQL Database Mirror
    ↓
Apple Mail (Source)
```

**Integration Points:**
- Plugin calls Swift CLI commands via system calls
- Markdown export for Obsidian notes
- Real-time sync with Apple Mail changes
- Persistent state in Obsidian's data folder

### 5. Action Delegation Pattern
**GUI ↔ CLI Workflow:**
1. User clicks "Archive" in GUI
2. Plugin executes: `swiftea mail archive --id mail:12345`
3. CLI updates libSQL mirror database
4. CLI runs AppleScript to archive in Mail.app
5. Plugin UI updates to reflect change

**Advantages:**
- Single source of truth (CLI commands)
- No duplicate logic between GUI and CLI
- Easy to test and debug
- Consistent behavior across interfaces

## Implementation Phases

### Phase 1: Core Threading (Current)
- Implement header-based thread detection
- Add CLI commands for thread viewing
- Enhance markdown export with conversation grouping
- Update database schema with thread metadata

### Phase 2: Enhanced Features
- Thread summaries and AI insights
- Cross-module linking (threads ↔ calendar events)
- Advanced filtering and search by conversation
- Performance optimizations for massive inboxes

### Phase 3: UI Foundations
- Design Obsidian plugin architecture
- Create basic HTML interface
- Implement action delegation to CLI
- Test integration with Swift Mail CLI

### Phase 4: Full GUI (Future)
- Production-ready Obsidian plugin
- Gmail-like conversation interface
- Advanced triage workflows
- Keyboard shortcuts and productivity features

## Technical Implementation Details

### Thread ID Generation Algorithm
```swift
func generateThreadID(from email: MailMessage) -> String {
    // 1. Check References header (full chain)
    if let references = email.headers.references {
        return generateThreadIDFromReferences(references)
    }
    
    // 2. Check In-Reply-To header
    if let replyTo = email.headers.inReplyTo {
        return replyTo
    }
    
    // 3. Use Message-ID as thread starter
    return email.headers.messageID ?? UUID().uuidString
}
```

### Database Schema Updates
```sql
-- Thread metadata table
CREATE TABLE threads (
    thread_id TEXT PRIMARY KEY,
    original_subject TEXT,
    normalized_subject TEXT,
    participant_emails TEXT, -- JSON array
    participant_names TEXT,    -- JSON array
    start_timestamp INTEGER,
    last_timestamp INTEGER,
    message_count INTEGER,
    is_read BOOLEAN DEFAULT FALSE,
    labels TEXT,              -- JSON array
    metadata TEXT             -- JSON for custom fields
);

-- Link emails to threads
CREATE TABLE thread_messages (
    thread_id TEXT,
    email_id TEXT,
    position INTEGER,
    FOREIGN KEY (thread_id) REFERENCES threads(thread_id),
    FOREIGN KEY (email_id) REFERENCES mail_mirror(email_id),
    PRIMARY KEY (thread_id, email_id)
);
```

### Export Formats Enhancement

**Markdown Thread Export:**
```markdown
---
thread_id: thread-abc123
participants: ["alice@company.com", "bob@company.com"]
message_count: 5
dates: "2026-01-05 → 2026-01-07"
labels: ["work", "project-alpha"]
---

# Budget Discussion Thread

## Message 1/5: Alice → Bob & Carol
**Date:** 2026-01-05 09:00
**Subject:** Q1 Budget Review

Message content...

## Message 2/5: Bob → Alice
**Date:** 2026-01-05 10:30  
**Subject:** Re: Q1 Budget Review

Reply content...
```

**JSON Thread Export:**
```json
{
  "thread_id": "thread-abc123",
  "subject": "Budget Discussion",
  "participants": [
    {"email": "alice@company.com", "name": "Alice"},
    {"email": "bob@company.com", "name": "Bob"}
  ],
  "messages": [
    {
      "email_id": "mail:12345",
      "position": 1,
      "date": "2026-01-05T09:00:00Z",
      "from": "alice@company.com",
      "subject": "Q1 Budget Review",
      "content": "..."
    }
  ],
  "statistics": {
    "count": 5,
    "duration_days": 2,
    "participant_count": 3
  }
}
```

## Success Metrics

### Phase 1 (Threading Core)
- ✅ Thread detection accuracy: >95% on test dataset
- ✅ CLI performance: <5s for 100k emails
- ✅ Export maintains conversation structure
- ✅ Thread commands integrate with existing CLI

### Future GUI Phase
- Triage speed: <2s per email action
- User satisfaction: 80% prefer over native Mail.app
- Obsidian integration: seamless markdown export
- Action reliability: 99.9% success rate

## Open Questions for Future

1. **Thread Merging**: Should we merge threads with similar subjects?
2. **AI Summarization**: Add thread summaries using ClaudEA?
3. **Thread Prioritization**: Smart ranking based on engagement?
4. **Cross-Platform**: Web interface beyond Obsidian plugin?
5. **Real-time Updates**: Push notifications for new messages?

## Next Steps

1. Create OpenSpec change proposal for conversation threading
2. Implement Phase 1 (database schema + CLI commands)
3. Test with sample email dataset
4. Gather feedback on thread detection accuracy
5. Plan Phase 2 enhancements based on usage patterns