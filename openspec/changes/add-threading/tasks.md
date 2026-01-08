## 1. Database Schema Updates
- [ ] 1.1 Add thread metadata columns to mail_mirror table
- [ ] 1.2 Create threads table for conversation-level metadata
- [ ] 1.3 Create thread_messages junction table
- [ ] 1.4 Add indexes for thread lookups
- [ ] 1.5 Implement database migration script

## 2. Thread Detection Implementation
- [ ] 2.1 Implement Message-ID, References, In-Reply-To header parsing
- [ ] 2.2 Create thread ID generation algorithm
- [ ] 2.3 Build thread detection service
- [ ] 2.4 Add thread metadata extraction
- [ ] 2.5 Create thread detection tests with sample emails

## 3. CLI Commands
- [ ] 3.1 Implement `swiftea mail threads` command
- [ ] 3.2 Implement `swiftea mail thread --id <id>` command
- [ ] 3.3 Add filtering options (--limit, --sort, --participant)
- [ ] 3.4 Add output format options (text, json, markdown)
- [ ] 3.5 Write CLI tests

## 4. Enhanced Export
- [ ] 4.1 Update markdown export to include thread metadata
- [ ] 4.2 Update JSON export with full thread structure
- [ ] 4.3 Add thread export command: `swiftea mail export-threads`
- [ ] 4.4 Ensure conversation grouping in project exports
- [ ] 4.5 Test export formats with sample threads

## 5. Integration & Performance
- [ ] 5.1 Integrate thread detection into sync process
- [ ] 5.2 Add thread caching for performance
- [ ] 5.3 Optimize queries for large inboxes (>100k emails)
- [ ] 5.4 Add performance benchmarks
- [ ] 5.5 Test with synthetic large email datasets

## 6. Documentation
- [ ] 6.1 Update mail module documentation
- [ ] 6.2 Add usage examples for thread commands
- [ ] 6.3 Document thread detection algorithm
- [ ] 6.4 Create migration guide for thread metadata
- [ ] 6.5 Update project roadmap with future GUI plans