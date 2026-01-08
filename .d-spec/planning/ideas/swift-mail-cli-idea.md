# Idea
I want to create a swift CLI program that allows me or ClaudEA (see claudea-ideas/CLAUDEA.md) to programmatically access my apple mail by directly accessing the SQLite DB that apple mail stores locally with all the email data and by accessing the .emlx files.

## Accessing the Metadata (The SQL Layer)
Apple Mail tracks all emails in a SQLite database. I want to mirror this SQLite db to my own instance and keeYour Swift code must query this to find out what emails exist before it can read them.
- Locate the Database: The database is typically found at ~/Library/Mail/V[x]/MailData/Envelope Index, where V[x] changes with macOS versions (e.g., V10, V14).
- Bypass Permissions: Your Swift executable must be granted Full Disk Access in System Settings, or it will see the database file as empty or protected.
- Query the Schema: You will use a library like SQLite.swift to run raw SQL queries. The primary tables are typically messages, subjects, and addresses. You would join these tables to build a MessageSummary struct containing the ROWID and directory_id needed to find the file.
Phase 2: Resolving the Content (The File Layer)
The SQL database rarely stores the full body text. Instead, it points to a file on disk.
- Construct the Path: Using the directory_id from your SQL query, you must traverse the Mail directory structure (e.g., ~/Library/Mail/V10/[AccountID]/[Mailbox]/Messages/[ROWID].emlx). You may need to read the PersistenceInfo.plist file in the Mail directory to understand the current version's folder structure.

1. The "Read" Layer: Direct SQLite Access (Brute Force)
Since there is no API to fetch messages, developers directly read the internal database Apple Mail uses to index content.
- The Database: Mail stores its metadata (Subject, Sender, Date, Read Status) in a SQLite database called Envelope Index, located at ~/Library/Mail/V[x]/MailData/Envelope Index.
- The Method: You use standard SQLite libraries (in Python, Swift, or Node) to run SELECT queries against this file.
- Capability: This provides instant access to the list of emails, threading, and status flags without launching the Mail app.
- Constraint: This requires Full Disk Access permissions from the user. It is strictly read-only; writing to this database will corrupt the user's mail index.
  - **FEATURE REQUIREMENT** I need to be able to add my own metadata and context/insights on top of the emails so I want to create a mirror of this SQLite DB that stays in sync in near-realtime (using something like rsync) and since I then have write-access to that mirror I can add my own columns and update those columens. either in one big table or using a joined table of my own data.@Claude, I need your help evaluating different approaches.

2. The "Content" Layer: Parsing .emlx Files
The SQLite database rarely stores the full body of the email. Instead, it points to files on the disk.
- The File Format: Apple stores individual messages as .emlx files.
- Structure: An .emlx file is essentially a standard raw email (RFC822/MIME) with a byte-count header at the top and an XML property list (plist) at the bottom containing metadata.
- The Method: To "read" an email, your code queries the Envelope Index to find the path to the .emlx file, then uses a standard text parser or email library to extract the body text.
- **FEATURE REQUIREMENT** I want the ability to parse the EMLX files and export them to markdown, JSON, and possibly other file types for my Claudea workflows.


3. The "Action" Layer: AppleScript (Automation)
To perform actions (Send, Reply, Draft, Move), you cannot use the file system. You must use Apple's automation scripting language.
- The API: Apple Mail exposes a "Scripting Dictionary" that allows external apps to control it via Apple Events.
- Usage: You effectively send commands like "Tell application 'Mail' to send a message to 'Bob' with subject 'Hello'".
- Wrappers: In modern development (TypeScript/Node/Swift), developers wrap these AppleScript commands inside functions (e.g., runAppleScript(...)) to bridge the gap between their code and the Mail app.
- Constraint: This is slower than reading files and requires the Mail app to be running.
- **Feature requirement** I just want to have prebuilt applescripts that tell apple mail to take specific actions on my email without needing to open the app. basic things like: reply, draft, send, delete, archive, flag/label, etc.


Summary of the "Unofficial SDK" Architecture
If you are building your AI Executive Assistant to interface with Apple Mail, your "SDK" is actually this hybrid stack:

| Capability | "SDK" Component | Technology |
| ---------- | --------------- | ---------- |
| List/Search Emails | Envelope Index | SQLite Query |
| Read Body Text | .emlx Files | File System + Parser |
| Send/Reply/Draft | Automation | AppleScript / osascript |
| Live Updates | Database Watchers | Polling Envelope Index for changes |


# ROADMAP
the long term vision is to create a extensible and integrated framework and UI for managing my email, calendar, communications and core productivity apps in one place in a way that adheres to the claudea-ideas/standards.md so I can easily collaborate with an AI agent on my basic productivity
1. Swift CLI to access mail and take action using prebuilt apple scripts
2. build Obsidian email UI that uses the local mirror created in the previous phase so I can have a GUI for reading, replying to and taking action on my email in Obsidian. build this as a obsidian plugin.
3. using the combined Swift CLI and Obsidian plugin, I want to be able to turn emails into .md files in my obsidian vault that can then be assigned to tasks, project context, resources, etc. and ensure that my ClaudEA agent can collaborate with me in my email and take action on my email
4. add calendar, reminders, contacts, and imessage capabilities to the Swift Mail CLI which becomes the "Swift Agent CLI"
