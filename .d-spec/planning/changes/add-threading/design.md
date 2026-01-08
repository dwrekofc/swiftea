## Context
Email conversation threading is a critical feature for effective email management. Currently, emails are treated as individual items without conversation context, making it difficult to follow discussions, understand context, and manage email workflows. This feature adds conversation threading based on email headers with performance optimized for large inboxes.

## Goals / Non-Goals

### Goals:
- **Accurate Threading**: Header-based threading following RFC 5322 standards
- **Performance**: Handle 100k+ email inboxes efficiently
- **CLI Integration**: Seamless addition to existing SwiftEA CLI
- **Export Compatibility**: Enhanced markdown/JSON exports with thread structure
- **Future Foundation**: Prepare for Obsidian email GUI plugin

### Non-Goals:
- **Perfect Threading**: 100% accuracy for all edge cases (accepts ~95% accuracy)
- **Real-time Updates**: Thread detection during live email reception
- **GUI Implementation**: This phase focuses on CLI and backend only
- **Cross-Platform**: Optimized for macOS Apple Mail databases only
- **AI Threading**: Smart thread merging/splitting using AI

## Decisions

### Decision: Header-based Threading
**What**: Use Message-ID, References, In-Reply-To headers for thread detection
**Why**: Most accurate method, follows email standards, handles complex cases
**Alternatives considered**: 
- Subject-based: Less accurate, prone to false groupings
- Time-based: Unreliable, misses delayed replies
- AI-based: Too complex for MVP, performance concerns

### Decision: Fast & Simple Implementation
**What**: Optimize for speed over handling all edge cases
**Why**: Large inbox performance is critical for user experience
**Alternatives considered**:
- Comprehensive parsing: Slower but more accurate
- Hybrid approach: Good balance but more complex
- Configurable: Most flexible but adds complexity

### Decision: Separate Threads Table
**What**: Create dedicated `threads` table separate from email data
**Why**: Efficient thread queries, thread-level metadata, clear separation
**Alternatives considered**:
- Add columns to mail_mirror: Simpler but less efficient for thread queries
- Document store in JSON: Flexible but less queryable
- Graph database: Overkill for this use case

### Decision: Thread ID Generation Algorithm
**What**: Use References header chain as primary thread ID source
**Why**: Follows email conversation chain accurately
**Alternatives considered**:
- Message-ID of first email: Simple but breaks with missing emails
- Hash of participants + subject: Works for simple cases but unreliable
- UUID per detected thread: Unique but doesn't preserve relationships

### Decision: Performance Targets
**What**: 5-second thread detection for 100k emails, 2-second thread queries
**Why**: Responsive user experience even with large inboxes
**Alternatives considered**:
- Higher accuracy with slower processing: Better thread detection but poor UX
- Background processing: Better UX but more complex implementation
- Progressive enhancement: Start fast, improve accuracy later

## Risks / Trade-offs

### Risk: Thread Detection Accuracy
- **Risk**: Header-based threading may miss emails with malformed headers
- **Mitigation**: Log warnings, provide fallback subject grouping, allow manual correction

### Risk: Performance with Large Inboxes
- **Risk**: Thread detection may be slow for very large inboxes (>500k emails)
- **Mitigation**: Batch processing, optimized queries, performance monitoring

### Risk: Database Migration Complexity
- **Risk**: Schema changes may require data migration on existing installations
- **Mitigation**: Provide migration script, clear documentation, rollback plan

### Risk: Export Format Changes
- **Risk**: Thread-aware exports may break existing ClaudEA workflows
- **Mitigation**: Maintain backward compatibility, provide migration guide

### Trade-off: Speed vs Accuracy
- **Trade-off**: Fast processing vs perfect thread detection
- **Decision**: Prioritize speed for MVP, improve accuracy in future phases

## Migration Plan

### Phase 1: Schema Migration
1. Create backup of existing database
2. Run migration script to add thread columns
3. Create new threads and thread_messages tables
4. Validate schema changes

### Phase 2: Data Migration
1. Run initial thread detection on existing emails
2. Populate thread metadata columns
3. Verify thread detection accuracy
4. Provide progress reporting

### Phase 3: Feature Rollout
1. Enable new CLI commands
2. Update export formats with thread support
3. Monitor performance and accuracy
4. Gather user feedback

### Rollback Plan
1. Disable thread CLI commands
2. Remove thread metadata from exports
3. Provide script to remove thread columns (if needed)
4. Restore from backup in case of critical issues

## Open Questions

1. **Thread Merging**: Should we merge threads with similar subjects but different thread IDs?
2. **Manual Correction**: Should users be able to manually fix thread groupings?
3. **Thread Labels**: Should thread-level labels be different from email labels?
4. **Cross-Account Threading**: How to handle same conversation across multiple email accounts?
5. **Real-time Updates**: Should thread detection run automatically on new emails?

## Technical Implementation Details

### Thread ID Algorithm
```swift
func generateThreadID(from email: MailMessage) -> String {
    // Primary: Use References header chain
    if let references = email.headers.references {
        return generateThreadIDFromReferences(references)
    }
    
    // Secondary: Use In-Reply-To header
    if let replyTo = email.headers.inReplyTo {
        return replyTo
    }
    
    // Fallback: Use Message-ID as thread starter
    return email.headers.messageID ?? UUID().uuidString
}

func generateThreadIDFromReferences(_ references: String) -> String {
    // Parse space-separated message IDs
    let messageIDs = references.split(separator: " ").map(String.init)
    
    // Use the first message ID in the chain (original message)
    guard let firstMessageID = messageIDs.first else {
        return UUID().uuidString
    }
    
    return firstMessageID
}
```

### Database Schema
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

-- Enhanced mail_mirror table
ALTER TABLE mail_mirror ADD COLUMN thread_id TEXT;
ALTER TABLE mail_mirror ADD COLUMN thread_position INTEGER;
ALTER TABLE mail_mirror ADD COLUMN thread_total INTEGER;

-- Indexes for performance
CREATE INDEX idx_mail_mirror_thread_id ON mail_mirror(thread_id);
CREATE INDEX idx_thread_messages_thread_id ON thread_messages(thread_id);
CREATE INDEX idx_thread_messages_email_id ON thread_messages(email_id);
```

### Performance Optimizations
- **Batch Processing**: Process emails in batches of 1000
- **Caching**: Cache thread metadata for frequent queries
- **Indexes**: Strategic database indexes for common queries
- **Lazy Loading**: Load thread content only when needed
- **Streaming Export**: Stream emails to disk during export

## Success Criteria
- **Thread Detection**: >95% accuracy on test email dataset
- **Performance**: <5s thread detection for 100k emails
- **CLI Response**: <2s for thread listing queries
- **Export Speed**: >100 emails per second export rate
- **User Satisfaction**: 80% of test users prefer threaded view