# SwiftEA Test Tutorial

A step-by-step guide to set up and test SwiftEA with a fresh vault.

---

## What You'll Do

By the end of this tutorial, you'll have:

- Built SwiftEA from source
- Created a test vault
- Synced your Mail and Calendar data
- Searched and exported your data
- Tested mail actions (archive, flag, reply)

**Time required:** 10-15 minutes

---

## Prerequisites

Before starting, make sure you have:

- macOS 14 or later
- Xcode Command Line Tools installed
- Apple Mail configured with at least one account
- macOS Calendar with some events

---

## Step 1: Grant System Permissions

SwiftEA needs permission to access your Mail and Calendar data. Set these up first to avoid interruptions later.

### Full Disk Access (Required for Mail)

1. Open **System Settings**
2. Go to **Privacy & Security** → **Full Disk Access**
3. Click the **+** button
4. Add your terminal app (Terminal, iTerm, Warp, etc.)
5. Restart your terminal

### Calendar Access

Calendar permission is granted automatically when you first run a calendar command. You'll see a system prompt asking for access.

### Automation (Required for Mail Actions)

When you first run a mail action (like archive or reply), macOS will ask permission to control Mail.app. Click **OK** to allow.

---

## Step 2: Build SwiftEA

Open your terminal and navigate to the SwiftEA project directory:

```bash
cd /path/to/swiftea
```

Build the project:

```bash
swift build
```

This takes about 30-60 seconds the first time. You'll see output ending with:

```
Build complete!
```

Verify the build succeeded:

```bash
.build/debug/swea --help
```

You should see the SwiftEA help text with available commands.

---

## Step 3: Create a Test Vault

A vault is SwiftEA's workspace where all your synced data lives. Create one in a temporary location:

```bash
.build/debug/swea vault init --path ~/Desktop/test-vault
```

You should see:

```
Vault initialized at /Users/you/Desktop/test-vault
```

Now navigate into your vault:

```bash
cd ~/Desktop/test-vault
```

**Important:** SwiftEA commands auto-detect the vault when you're inside it. All following commands assume you're in the vault directory.

---

## Step 4: Sync Your Mail

Run a full mail sync to import your email metadata:

```bash
.build/debug/swea mail sync --verbose
```

You'll see progress output like:

```
Starting mail sync...
Found 3 accounts
Syncing mailboxes...
Processing messages...
Sync complete: 1,234 messages synced
```

**Note:** This only syncs metadata (sender, subject, date, etc.), not full message bodies. Your original Mail data is never modified.

---

## Step 5: Search Your Mail

Try some searches to explore your synced data.

### Basic Search

```bash
.build/debug/swea mail search "meeting"
```

### Search with Filters

Find unread emails:

```bash
.build/debug/swea mail search "is:unread"
```

Find emails from a specific sender:

```bash
.build/debug/swea mail search "from:someone@example.com"
```

Find emails with attachments:

```bash
.build/debug/swea mail search "has:attachment"
```

Combine filters:

```bash
.build/debug/swea mail search "from:boss@company.com is:unread after:2025-01-01"
```

### Available Search Filters

| Filter | Example | Description |
|--------|---------|-------------|
| `from:` | `from:alice@example.com` | Sender email or name |
| `to:` | `to:me@example.com` | Recipient |
| `subject:` | `subject:invoice` | Subject line |
| `mailbox:` | `mailbox:INBOX` | Mailbox name |
| `is:` | `is:unread`, `is:flagged` | Message status |
| `has:` | `has:attachment` | Has attachments |
| `after:` | `after:2025-01-01` | Date range start |
| `before:` | `before:2025-12-31` | Date range end |

---

## Step 6: View a Message

Pick a message ID from your search results and view it:

```bash
.build/debug/swea mail show <message-id>
```

For JSON output (useful for scripting):

```bash
.build/debug/swea mail show <message-id> --json
```

---

## Step 7: Export Mail to Markdown

Export emails matching a query to Markdown files (compatible with Obsidian):

```bash
.build/debug/swea mail export --query "is:flagged" --format markdown --output ./mail-exports
```

Check the exported files:

```bash
ls ./mail-exports
```

Each email becomes a Markdown file with YAML frontmatter containing metadata.

---

## Step 8: Test Mail Actions

**Caution:** These actions modify your actual Mail.app data. Use test emails or be careful with message IDs.

### Flag a Message

```bash
.build/debug/swea mail flag --id <message-id> --set
```

Open Mail.app to verify the flag appeared.

### Unflag It

```bash
.build/debug/swea mail flag --id <message-id> --unset
```

### Mark as Read/Unread

```bash
.build/debug/swea mail mark --id <message-id> --unread
.build/debug/swea mail mark --id <message-id> --read
```

### Archive a Message

```bash
.build/debug/swea mail archive --id <message-id> --dry-run
```

The `--dry-run` flag shows what would happen without actually archiving. Remove it to perform the action:

```bash
.build/debug/swea mail archive --id <message-id> --yes
```

### Compose a New Email

This opens a draft in Mail.app:

```bash
.build/debug/swea mail compose --to "test@example.com" --subject "Test from SwiftEA" --body "Hello from the command line!"
```

---

## Step 9: Sync Your Calendar

Now let's sync calendar data:

```bash
.build/debug/swea cal sync --verbose
```

If prompted for calendar access, click **OK**.

You'll see:

```
Starting calendar sync...
Found 5 calendars
Syncing events...
Sync complete: 342 events synced
```

---

## Step 10: Explore Your Calendar

### List Your Calendars

```bash
.build/debug/swea cal calendars
```

### View Upcoming Events

```bash
.build/debug/swea cal list --from today --limit 10
```

### Search Events

```bash
.build/debug/swea cal search "standup"
```

### View Event Details

```bash
.build/debug/swea cal show <event-id> --with-attendees
```

---

## Step 11: Export Calendar

Export to iCalendar format (.ics):

```bash
.build/debug/swea cal export --format ics --output ./calendar-backup.ics
```

Export to Markdown:

```bash
.build/debug/swea cal export --format markdown --output ./calendar-exports
```

---

## Step 12: Enable Watch Mode (Optional)

Watch mode keeps your vault in sync automatically.

### Start Mail Watch Daemon

```bash
.build/debug/swea mail sync --watch
```

This runs in the background, syncing every 5 minutes.

### Start Calendar Watch Daemon

```bash
.build/debug/swea cal sync --watch
```

Calendar watch responds to real-time changes via EventKit notifications.

### Check Daemon Status

```bash
.build/debug/swea mail sync --status
.build/debug/swea cal sync --status
```

### Stop Daemons

```bash
.build/debug/swea mail sync --stop
.build/debug/swea cal sync --stop
```

---

## Cleanup

When you're done testing, you can delete the test vault:

```bash
rm -rf ~/Desktop/test-vault
```

---

## Quick Reference

### Common Commands

| Task | Command |
|------|---------|
| Init vault | `swea vault init --path <path>` |
| Sync mail | `swea mail sync` |
| Search mail | `swea mail search "<query>"` |
| View message | `swea mail show <id>` |
| Export mail | `swea mail export --format markdown --output <path>` |
| Sync calendar | `swea cal sync` |
| List events | `swea cal list` |
| Search events | `swea cal search "<query>"` |
| Export calendar | `swea cal export --format ics --output <path>` |

### Getting Help

```bash
# General help
.build/debug/swea --help

# Command-specific help
.build/debug/swea mail --help
.build/debug/swea mail search --help
```

---

## Troubleshooting

### "Permission denied" or "Full Disk Access required"

Make sure you've added your terminal to Full Disk Access (Step 1) and restarted your terminal.

### "No messages found"

1. Check that Apple Mail has at least one configured account
2. Open Mail.app and let it download messages
3. Re-run `swea mail sync`

### "Calendar access denied"

1. Open System Settings → Privacy & Security → Calendars
2. Find your terminal app and enable access
3. Restart your terminal

### Mail actions don't work

1. When prompted, allow SwiftEA to control Mail.app
2. Check System Settings → Privacy & Security → Automation
3. Ensure your terminal can control Mail.app

---

## Next Steps

- Explore the `--json` flag for scripting and automation
- Set up watch mode for continuous sync
- Check out the project README for architecture details
- Review open issues with `bd ready` for contribution opportunities
