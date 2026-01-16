# Mail Database Migration Guide

This guide helps you safely upgrade your SwiftEA mail database to support email threading and other new features.

## Overview

SwiftEA uses a versioned migration system to upgrade the mail database schema. The migration command is idempotent - it only applies migrations that haven't been applied yet, so it's safe to run multiple times.

**Current Schema Version:** V7

## Before You Begin

### 1. Check Your Current Version

First, check your current database schema version:

```bash
swea mail migrate --status
```

This shows:
- Your current schema version
- The latest available version
- Any pending migrations
- Migration history

### 2. Backup Your Database

**Important:** Always backup your database before running migrations.

```bash
# Navigate to your vault
cd /path/to/your/vault

# Backup the mail database
cp .swiftea/mail.db .swiftea/mail.db.backup

# Verify the backup
ls -la .swiftea/mail.db*
```

The database is typically located at:
```
<vault>/.swiftea/mail.db
```

You can also use the `--database` flag to check a specific database path:

```bash
swea mail migrate --status --database /path/to/mail.db
```

## Step-by-Step Migration

### Step 1: Stop the Sync Daemon (if running)

If you have automatic sync enabled, stop it first:

```bash
swea mail sync --stop
swea mail sync --status  # Verify daemon is stopped
```

### Step 2: Create a Backup

```bash
cp <vault>/.swiftea/mail.db <vault>/.swiftea/mail.db.backup-$(date +%Y%m%d-%H%M%S)
```

### Step 3: Run the Migration

```bash
# Apply all pending migrations
swea mail migrate

# Or with verbose output to see details
swea mail migrate --verbose
```

Example output:
```
Database: /path/to/vault/.swiftea/mail.db
Pre-migration version: V2
✓ Migrated from V2 to V7
  Applied 5 migration(s):
    V3: Threading headers (in_reply_to, threading_references)
    V4: Threads table and thread_id column on messages
    V5: Thread-messages junction table for many-to-many relationships
    V6: Thread position metadata (thread_position, thread_total)
    V7: Large inbox query optimization indexes
```

### Step 4: Verify the Migration

```bash
swea mail migrate --status --verbose
```

You should see:
- Current version matches latest version (V7)
- All tables marked with ✓
- Threading columns present in messages table

### Step 5: Resync to Populate Threading Data

After migration, run a full sync to populate the new threading metadata:

```bash
swea mail sync --full
```

This will:
- Parse threading headers (In-Reply-To, References) from all messages
- Create thread records
- Populate thread position metadata

### Step 6: Restart the Sync Daemon (optional)

```bash
swea mail sync --watch
```

## Migration Details

### What Each Migration Does

| Version | Description |
|---------|-------------|
| V1 | Initial schema: messages, recipients, attachments, mailboxes, FTS5 search |
| V2 | Bidirectional sync: mailbox_status, pending_sync_action columns |
| V3 | Threading headers: in_reply_to, threading_references columns |
| V4 | Threads table: conversation-level metadata, thread_id on messages |
| V5 | Thread-messages junction: many-to-many thread/message relationships |
| V6 | Thread position: thread_position, thread_total columns |
| V7 | Query optimization: indexes for large inboxes (>100k emails) |

### New Tables (V4+)

**threads table:**
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT | 32-character hex thread ID |
| subject | TEXT | Normalized subject |
| participant_count | INTEGER | Unique senders |
| message_count | INTEGER | Messages in thread |
| first_date | INTEGER | Earliest message timestamp |
| last_date | INTEGER | Latest message timestamp |

**thread_messages junction table:**
| Column | Type | Description |
|--------|------|-------------|
| thread_id | TEXT | Foreign key to threads |
| message_id | TEXT | Foreign key to messages |
| added_at | INTEGER | When message was added to thread |

### New Columns on messages (V3+)

| Column | Version | Description |
|--------|---------|-------------|
| in_reply_to | V3 | In-Reply-To header value |
| threading_references | V3 | JSON array of References header |
| thread_id | V4 | Foreign key to threads table |
| thread_position | V6 | Position within thread (1-indexed) |
| thread_total | V6 | Total messages in thread |

## Rollback Procedure

If you need to revert to the pre-migration state:

### Option 1: Restore from Backup

```bash
# Stop any running sync daemon
swea mail sync --stop

# Restore the backup
cp <vault>/.swiftea/mail.db.backup <vault>/.swiftea/mail.db

# Verify by checking the version
swea mail migrate --status
```

### Option 2: Fresh Start

If you don't have a backup or want a clean slate:

```bash
# Stop any running sync daemon
swea mail sync --stop

# Remove the existing database
rm <vault>/.swiftea/mail.db

# Run a full sync to create a fresh database
swea mail sync --full
```

This creates a new database at the latest schema version and syncs all messages fresh.

## Common Issues and Solutions

### "Database is locked" Error

The migration requires exclusive access to the database.

**Solutions:**
1. Stop the sync daemon: `swea mail sync --stop`
2. Wait for any running sync operations to complete
3. Ensure no other process is accessing the database
4. Retry the migration

### "Permission denied" Error

The tool needs read/write access to the database file.

**Solutions:**
1. Check file permissions: `ls -la <vault>/.swiftea/mail.db`
2. Ensure you own the file or have write permissions
3. Check parent directory permissions

### Migration Appears to Hang

Large databases may take time to migrate, especially V7 which adds indexes.

**Solutions:**
1. Use `--verbose` to see progress
2. For very large databases (>100k messages), expect index creation to take several minutes
3. Don't interrupt - let it complete

### Threads Not Appearing After Migration

The migration adds schema support but doesn't populate thread data.

**Solution:**
Run a full sync to populate threading metadata:
```bash
swea mail sync --full
```

### JSON Output for Automation

For scripting or CI/CD integration, use JSON output:

```bash
# Check status as JSON
swea mail migrate --status --json

# Run migration with JSON output
swea mail migrate --json
```

Example JSON output:
```json
{
  "database_path": "/path/to/mail.db",
  "was_new_database": false,
  "pre_migration_version": 2,
  "post_migration_version": 7,
  "migrations_applied": 5,
  "success": true
}
```

## New Database Creation

If no database exists, the migration command creates one with the latest schema:

```bash
# Creates new database at V7
swea mail migrate

# Verify
swea mail migrate --status
```

Output:
```
✓ Created new database at V7
  Applied 7 migration(s)
```

## FAQ

### Do I need to backup every time?

For production data, yes. The migration is designed to be safe, but hardware failures or interruptions could corrupt the database. A backup takes seconds and provides peace of mind.

### Can I skip migrations?

No. Migrations must be applied in order. Each migration depends on the previous schema version.

### Will I lose any data?

No. All migrations are additive - they add new columns, tables, and indexes without modifying existing data. Your existing messages, attachments, and metadata remain intact.

### How long does migration take?

- Empty database: < 1 second
- Small database (<10k messages): 1-5 seconds
- Medium database (10k-100k messages): 5-30 seconds
- Large database (>100k messages): 1-5 minutes (mostly index creation in V7)

### Can I migrate while Mail.app is running?

Yes. The migration operates on SwiftEA's local database, not Apple Mail's database. However, stop the sync daemon first to avoid concurrent access.

### What if I'm upgrading from a very old version?

The migration system handles all version jumps. If you're at V1, running `swea mail migrate` will sequentially apply V2, V3, V4, V5, V6, and V7 in order.
