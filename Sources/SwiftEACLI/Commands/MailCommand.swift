import AppKit
import ArgumentParser
import Foundation
import SwiftEAKit

// MARK: - Date Extension for ISO 8601 formatting

extension Date {
    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: self)
    }
}

// MARK: - Standard Error Output Helper

/// Write a message to stderr for error/warning output.
/// This ensures errors dont corrupt stdout when piping (e.g., JSON output to jq).
private func printError(_ message: String) {
    fputs("\(message)\n", stderr)
}

public struct Mail: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "mail",
        abstract: "Mail operations (sync, search, show, export, actions)",
        discussion: """
            swea mail commands interact with Apple Mail.app to sync, search,
            and perform actions on your email.

            GETTING STARTED
            The typical workflow is: sync -> search/show -> export

              swea mail sync              # Sync mail to local database
              swea mail sync --watch      # Start automatic background sync
              swea mail search "query"    # Search synced messages
              swea mail export            # Export to markdown files

            QUICK WORKFLOW
              # First time: sync all mail
              swea mail sync

              # For ongoing use: start automatic sync
              swea mail sync --watch

              # Search and export as needed
              swea mail search "from:alice@example.com"
              swea mail export --query "from:alice"

            NOTE: 'sync' populates the database. 'export' creates .md files.
            Run both if you want files you can open in Obsidian.

            AUTOMATION PERMISSION
            Action commands (archive, delete, move, flag, mark, reply, compose)
            require macOS Automation permission for Mail.app. On first run, macOS
            will prompt you to grant permission. To grant permission manually:

              1. Open System Settings > Privacy & Security > Automation
              2. Find swea (or Terminal if running from terminal)
              3. Enable the toggle for Mail.app

            SAFETY FLAGS
            Destructive actions (archive, delete, move) require explicit confirmation:

              --dry-run    Preview what would happen without making changes
              --yes        Confirm the action and execute it

            Running a destructive action without --yes or --dry-run will show an
            error explaining the requirement.

            EXAMPLES
              # Sync mail from Apple Mail
              swea mail sync

              # Start automatic sync (recommended for regular use)
              swea mail sync --watch

              # Force a full resync if needed
              swea mail sync --full

              # Search for emails from a specific sender
              swea mail search "from:alice@example.com"

              # Export all mail to markdown files
              swea mail export

              # Export filtered mail to custom location
              swea mail export --query "from:alice" --output ~/Documents/Mail

              # Preview archiving a message (no changes made)
              swea mail archive --id mail-abc123 --dry-run

              # Archive a message (requires confirmation)
              swea mail archive --id mail-abc123 --yes

              # Flag a message
              swea mail flag --id mail-abc123 --set

              # Compose a new email draft
              swea mail compose --to bob@example.com --subject "Hello"
            """,
        subcommands: [
            MailSyncCommand.self,
            MailSearchCommand.self,
            MailShowCommand.self,
            MailExportCommand.self,
            MailExportThreadsCommand.self,
            // Action commands
            MailArchiveCommand.self,
            MailDeleteCommand.self,
            MailMoveCommand.self,
            MailFlagCommand.self,
            MailMarkCommand.self,
            MailReplyCommand.self,
            MailComposeCommand.self
        ]
    )

    public init() {}
}

struct MailSyncCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync mail data from Apple Mail and export to Swiftea/Mail/",
        discussion: """
            Syncs mail data from Apple Mail to a local SQLite database for fast
            searching. By default, performs an incremental sync (only new/changed
            messages). Use --full to resync everything.

            After sync, new messages are automatically exported as markdown files
            to Swiftea/Mail/ for use with Obsidian or other markdown tools.
            Use --no-export to disable automatic export.

            For automatic sync, use --watch to start a background daemon that
            keeps your mail database and markdown exports up to date.

            EXAMPLES
              swea mail sync              # Incremental sync + auto-export
              swea mail sync --full       # Full resync + export all
              swea mail sync --no-export  # Sync only, skip markdown export
              swea mail sync --watch      # Start automatic sync daemon
              swea mail sync --status     # Check sync/daemon status
              swea mail sync --stop       # Stop the daemon
            """
    )

    @Flag(name: .long, help: "Install and start watch daemon for continuous sync")
    var watch: Bool = false

    @Flag(name: .long, help: "Stop the watch daemon")
    var stop: Bool = false

    @Flag(name: .long, help: "Show sync status and watch daemon state")
    var status: Bool = false

    @Flag(name: .long, help: "Force a full sync, ignoring previous sync state")
    var full: Bool = false

    @Flag(name: .long, help: "Show detailed progress")
    var verbose: Bool = false

    @Flag(name: .long, help: "Run as persistent daemon with sleep/wake detection (internal use)")
    var daemon: Bool = false

    @Flag(name: .long, help: "Disable automatic export to Swiftea/Mail/ after sync")
    var noExport: Bool = false

    @Option(name: .long, help: "Sync interval in seconds for watch mode (default: 300, minimum: 30)")
    var interval: Int?

    // MARK: - Retry Configuration (for daemon mode)

    /// Maximum number of retry attempts for transient errors
    private static let maxRetryAttempts = 5

    /// Base delay in seconds for exponential backoff
    private static let baseRetryDelay: TimeInterval = 2.0

    /// Maximum delay in seconds between retries
    private static let maxRetryDelay: TimeInterval = 60.0

    /// Errors that are considered transient and worth retrying
    private func isTransientError(_ error: Error) -> Bool {
        let description = error.localizedDescription.lowercased()
        // Database lock errors, network timeouts, permission issues that may be temporary
        return description.contains("locked") ||
               description.contains("busy") ||
               description.contains("timeout") ||
               description.contains("temporarily") ||
               description.contains("try again")
    }

    // MARK: - Daemon-safe Logging

    /// Detect if running as a LaunchAgent daemon (no TTY attached)
    private var isDaemonMode: Bool {
        // When run by launchd, there's no TTY and stdout is not interactive
        // isatty() returns non-zero if stdout is connected to a terminal, 0 otherwise
        return isatty(STDOUT_FILENO) == 0
    }

    /// Log a message with optional timestamp prefix for daemon mode.
    /// Ensures output is flushed immediately so logs are captured.
    private func log(_ message: String) {
        if isDaemonMode {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            fputs("[\(timestamp)] \(message)\n", stdout)
            fflush(stdout)
        } else {
            print(message)
        }
    }

    /// Log an error message to stderr, ensuring it's flushed for daemon mode.
    private func logError(_ message: String) {
        if isDaemonMode {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            fputs("[\(timestamp)] ERROR: \(message)\n", stderr)
            fflush(stderr)
        } else {
            fputs("Error: \(message)\n", stderr)
        }
    }

    /// Minimum allowed sync interval in seconds
    private static let minIntervalSeconds = 30

    /// Default sync interval in seconds (1 minute)
    private static let defaultIntervalSeconds = 60

    func validate() throws {
        // --watch and --stop are mutually exclusive
        if watch && stop {
            throw MailValidationError.watchAndStopMutuallyExclusive
        }

        // Validate --interval if provided
        if let interval = interval {
            if interval < Self.minIntervalSeconds {
                throw MailValidationError.invalidInterval(minimum: Self.minIntervalSeconds)
            }
        }
    }

    func run() throws {
        // Log startup for daemon mode debugging
        if isDaemonMode {
            log("mail sync started (daemon mode, pid=\(ProcessInfo.processInfo.processIdentifier))")
            log("working directory: \(FileManager.default.currentDirectoryPath)")
        }

        // In daemon mode, use retry with exponential backoff for transient errors
        if isDaemonMode {
            try executeSyncWithRetry()
        } else {
            // Interactive mode: no retry, immediate failure feedback
            do {
                try executeSync()
            } catch {
                logError("\(error.localizedDescription)")
                throw error
            }
        }
    }

    /// Execute sync with exponential backoff retry for transient errors (daemon mode)
    private func executeSyncWithRetry() throws {
        var lastError: Error?
        var attempt = 0

        while attempt < Self.maxRetryAttempts {
            do {
                try executeSync()
                log("mail sync completed successfully")
                return
            } catch {
                lastError = error
                attempt += 1

                // Check if error is transient and worth retrying
                if isTransientError(error) && attempt < Self.maxRetryAttempts {
                    // Calculate exponential backoff delay with jitter
                    let delay = min(
                        Self.baseRetryDelay * pow(2.0, Double(attempt - 1)),
                        Self.maxRetryDelay
                    )
                    // Add 10-20% random jitter to prevent thundering herd
                    let jitter = delay * Double.random(in: 0.1...0.2)
                    let totalDelay = delay + jitter

                    log("Transient error (attempt \(attempt)/\(Self.maxRetryAttempts)): \(error.localizedDescription)")
                    log("Retrying in \(String(format: "%.1f", totalDelay)) seconds...")

                    Thread.sleep(forTimeInterval: totalDelay)
                } else {
                    // Non-transient error or max retries reached
                    break
                }
            }
        }

        // All retries exhausted or non-transient error
        if let error = lastError {
            logError("Sync failed after \(attempt) attempt(s): \(error.localizedDescription)")
            log("mail sync failed")
            throw error
        }
    }

    private func executeSync() throws {
        let vault = try VaultContext.require()

        // Create mail database in vault's data folder
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        if verbose || isDaemonMode {
            log("Mail database: \(mailDbPath)")
        }

        // Handle --status flag
        if status {
            try showSyncStatus(mailDatabase: mailDatabase, vault: vault)
            return
        }

        // Handle --watch flag
        if watch {
            try installWatchDaemon(vault: vault, verbose: verbose)
            return
        }

        // Handle --stop flag
        if stop {
            try stopWatchDaemon(verbose: verbose)
            return
        }

        // Handle --daemon flag: run as persistent daemon with sleep/wake detection
        if daemon {
            try runPersistentDaemon(mailDatabase: mailDatabase, vault: vault)
            return
        }

        // Create sync engine
        let sync = MailSync(mailDatabase: mailDatabase)

        // Wire up progress callback for verbose mode
        if verbose {
            var lastPhase: String = ""
            var lastProgressTime = Date()
            sync.onProgress = { progress in
                // Always show phase changes
                if progress.phase.rawValue != lastPhase {
                    if !lastPhase.isEmpty {
                        print("") // newline after previous phase
                    }
                    lastPhase = progress.phase.rawValue
                    lastProgressTime = Date()
                }

                // For message sync, show periodic updates (every 0.5s or phase change)
                let now = Date()
                let elapsed = now.timeIntervalSince(lastProgressTime)
                if elapsed >= 0.5 || progress.current == progress.total {
                    lastProgressTime = now
                    if progress.total > 0 {
                        let pct = Int(progress.percentage)
                        // Use carriage return to update in place
                        print("\r  [\(progress.phase.rawValue)] \(progress.current)/\(progress.total) (\(pct)%) - \(progress.message)", terminator: "")
                        fflush(stdout)
                    } else {
                        print("\r  [\(progress.phase.rawValue)] \(progress.message)", terminator: "")
                        fflush(stdout)
                    }
                }
            }
        }

        log("Syncing mail from Apple Mail...")

        do {
            let result = try sync.sync(forceFullSync: full)

            if verbose {
                print("") // Final newline after progress
            }

            log("Sync complete:")
            log("  Messages processed: \(result.messagesProcessed)")
            log("  Messages added: \(result.messagesAdded)")
            log("  Messages updated: \(result.messagesUpdated)")
            log("  Mailboxes: \(result.mailboxesProcessed)")
            log("  Duration: \(String(format: "%.2f", result.duration))s")

            if !result.errors.isEmpty {
                log("\nWarnings/Errors:")
                for error in result.errors.prefix(10) {
                    log("  - \(error)")
                }
                if result.errors.count > 10 {
                    log("  ... and \(result.errors.count - 10) more")
                }
            }

            // Auto-export new messages to Swiftea/Mail/ unless disabled
            if !noExport {
                try performAutoExport(mailDatabase: mailDatabase, vault: vault)
            }

            // Process pending backward sync actions (archive/delete from SwiftEA to Apple Mail)
            try performBackwardSync(mailDatabase: mailDatabase)
        } catch let error as MailSyncError {
            logError("Sync failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    // MARK: - Auto-Export

    /// Export newly synced messages to Swiftea/Mail/ as markdown files
    private func performAutoExport(mailDatabase: MailDatabase, vault: VaultContext) throws {
        let exportDir = (vault.dataFolderPath as NSString).appendingPathComponent("Mail")
        let exporter = MailExporter(mailDatabase: mailDatabase)

        do {
            let exportResult = try exporter.exportNewMessages(to: exportDir)

            if exportResult.exported > 0 {
                log("Auto-export:")
                log("  Exported \(exportResult.exported) message(s) to Swiftea/Mail/")
            }

            if !exportResult.errors.isEmpty && verbose {
                for error in exportResult.errors.prefix(5) {
                    log("  Warning: \(error)")
                }
                if exportResult.errors.count > 5 {
                    log("  ... and \(exportResult.errors.count - 5) more export errors")
                }
            }
        } catch {
            // Log but don't fail sync if export has issues
            logError("Auto-export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Backward Sync

    /// Process pending backward sync actions (archive/delete from SwiftEA to Apple Mail)
    private func performBackwardSync(mailDatabase: MailDatabase) throws {
        let backwardSync = MailSyncBackward(mailDatabase: mailDatabase)

        do {
            let result = try backwardSync.processPendingActions()

            // Log results if any actions were processed
            if result.archived > 0 || result.deleted > 0 {
                log("Backward sync:")
                log("  Archived: \(result.archived), Deleted: \(result.deleted)")
            }

            // Log warnings for failed actions
            if result.failed > 0 {
                logError("Backward sync failed for \(result.failed) message(s)")
                for error in result.errors.prefix(5) {
                    logError("  - \(error)")
                }
                if result.errors.count > 5 {
                    logError("  ... and \(result.errors.count - 5) more errors")
                }
            }
        } catch {
            // Log but don't fail sync if backward sync has issues
            logError("Backward sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Status

    private func showSyncStatus(mailDatabase: MailDatabase, vault: VaultContext) throws {
        let summary = try mailDatabase.getSyncStatusSummary()
        let daemonStatus = getDaemonStatus()

        print("Mail Sync Status")
        print("================")
        print("")

        // Daemon status
        print("Watch Daemon: \(daemonStatus.isRunning ? "running" : "stopped")")
        if let pid = daemonStatus.pid {
            print("  PID: \(pid)")
        }
        print("")

        // Sync state
        print("Last Sync:")
        print("  State: \(summary.state.rawValue)")

        if let lastSync = summary.lastSyncTime {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            print("  Time: \(formatter.string(from: lastSync))")
        } else {
            print("  Time: Never")
        }

        if let duration = summary.duration {
            print("  Duration: \(String(format: "%.2f", duration))s")
        }

        if let isIncremental = summary.isIncremental {
            print("  Type: \(isIncremental ? "incremental" : "full")")
        }

        // Message counts
        if summary.messagesAdded > 0 || summary.messagesUpdated > 0 || summary.messagesDeleted > 0 {
            print("  Messages: +\(summary.messagesAdded) ~\(summary.messagesUpdated) -\(summary.messagesDeleted)")
        }

        // Error if any
        if let error = summary.lastSyncError {
            print("")
            printError("Last Error: \(error)")
        }

        // Database location
        print("")
        print("Database: \(vault.dataFolderPath)/mail.db")
    }

    private struct DaemonStatus {
        let isRunning: Bool
        let pid: Int?
    }

    private func getDaemonStatus() -> DaemonStatus {
        // Use `launchctl list` (all services) to get tab-separated format
        // Note: `launchctl list SERVICE_NAME` returns dictionary format, not tabular
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    // Find the line containing our service label
                    // Format: "PID\tStatus\tLabel" where PID is "-" if not running
                    for line in output.split(separator: "\n") {
                        if line.contains("com.swiftea.mail.sync") {
                            let components = line.split(separator: "\t")
                            if components.count >= 3 {
                                let pidStr = String(components[0])
                                if pidStr != "-", let pid = Int(pidStr), pid > 0 {
                                    return DaemonStatus(isRunning: true, pid: pid)
                                }
                                // Job exists but not running (PID is "-")
                                return DaemonStatus(isRunning: false, pid: nil)
                            }
                        }
                    }
                }
            }
        } catch {
            // launchctl failed, daemon not loaded
        }

        return DaemonStatus(isRunning: false, pid: nil)
    }

    // MARK: - Watch Daemon

    private static let launchAgentLabel = "com.swiftea.mail.sync"

    /// Get the effective sync interval (user-specified or default)
    private var effectiveSyncInterval: Int {
        interval ?? Self.defaultIntervalSeconds
    }

    private func getLaunchAgentPath() -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDir)/Library/LaunchAgents/\(Self.launchAgentLabel).plist"
    }

    /// Format interval for human-readable output
    private func formatInterval(_ seconds: Int) -> String {
        if seconds >= 60 && seconds % 60 == 0 {
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            return "\(seconds) seconds"
        }
    }

    private func installWatchDaemon(vault: VaultContext, verbose: Bool) throws {
        let launchAgentPath = getLaunchAgentPath()
        let executablePath = ProcessInfo.processInfo.arguments[0]

        // Resolve to absolute path if needed
        let absoluteExecutablePath: String
        if executablePath.hasPrefix("/") {
            absoluteExecutablePath = executablePath
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            absoluteExecutablePath = (currentDir as NSString).appendingPathComponent(executablePath)
        }

        // Create LaunchAgents directory if needed
        let launchAgentsDir = (getLaunchAgentPath() as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: launchAgentsDir) {
            try FileManager.default.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
        }

        // Create log directory
        let logDir = "\(vault.dataFolderPath)/logs"
        if !FileManager.default.fileExists(atPath: logDir) {
            try FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        }

        // Run initial sync before starting watch daemon (swiftea-7im.12)
        // This ensures the database is populated before the daemon starts incremental syncs
        print("Running initial sync before starting watch daemon...")
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()

        // Sync will auto-detect incremental mode based on last_sync_time in database
        let sync = MailSync(mailDatabase: mailDatabase)

        do {
            let result = try sync.sync()
            print("Initial sync complete:")
            print("  Messages: +\(result.messagesAdded) ~\(result.messagesUpdated)")
            print("  Duration: \(String(format: "%.2f", result.duration))s")
            if !result.errors.isEmpty {
                print("  Warnings: \(result.errors.count)")
            }
        } catch {
            printError("Warning: Initial sync failed: \(error.localizedDescription)")
            printError("The daemon will retry on its first run.")
        }

        mailDatabase.close()

        // Generate plist content
        // Uses --daemon mode for a persistent process with sleep/wake detection.
        // KeepAlive ensures the daemon is restarted if it exits.
        let syncInterval = effectiveSyncInterval
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(Self.launchAgentLabel)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(absoluteExecutablePath)</string>
                    <string>mail</string>
                    <string>sync</string>
                    <string>--daemon</string>
                    <string>--interval</string>
                    <string>\(syncInterval)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <true/>
                <key>StandardOutPath</key>
                <string>\(logDir)/mail-sync.log</string>
                <key>StandardErrorPath</key>
                <string>\(logDir)/mail-sync.log</string>
                <key>WorkingDirectory</key>
                <string>\(vault.rootPath)</string>
                <key>EnvironmentVariables</key>
                <dict>
                    <key>PATH</key>
                    <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
                </dict>
            </dict>
            </plist>
            """

        // Write plist file
        try plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)

        if verbose {
            print("Created LaunchAgent: \(launchAgentPath)")
        }

        // Unload if already loaded (ignore errors)
        let unloadProcess = Process()
        unloadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        unloadProcess.arguments = ["unload", launchAgentPath]
        unloadProcess.standardOutput = FileHandle.nullDevice
        unloadProcess.standardError = FileHandle.nullDevice
        try? unloadProcess.run()
        unloadProcess.waitUntilExit()

        // Load the LaunchAgent
        let loadProcess = Process()
        loadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        loadProcess.arguments = ["load", launchAgentPath]

        let errorPipe = Pipe()
        loadProcess.standardError = errorPipe

        try loadProcess.run()
        loadProcess.waitUntilExit()

        if loadProcess.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            printError("Failed to load LaunchAgent: \(errorOutput)")
            throw ExitCode.failure
        }

        print("Watch daemon installed and started")
        print("  Mode: Persistent daemon with sleep/wake detection")
        print("  Interval: \(formatInterval(syncInterval))")
        print("  Logs: \(logDir)/mail-sync.log")
        print("")
        print("Use 'swea mail sync --status' to check status")
        print("Use 'swea mail sync --stop' to stop the daemon")
    }

    private func stopWatchDaemon(verbose: Bool) throws {
        let launchAgentPath = getLaunchAgentPath()

        // Check if plist exists
        guard FileManager.default.fileExists(atPath: launchAgentPath) else {
            print("Watch daemon is not installed")
            return
        }

        // Unload the LaunchAgent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", launchAgentPath]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            // Check if it was already unloaded
            if !errorOutput.contains("Could not find specified service") {
                printError("Warning: \(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        // Remove the plist file
        try? FileManager.default.removeItem(atPath: launchAgentPath)

        if verbose {
            print("Removed LaunchAgent: \(launchAgentPath)")
        }

        print("Watch daemon stopped and uninstalled")
    }

    // MARK: - Persistent Daemon with Sleep/Wake Detection

    /// Run as a persistent daemon that syncs on startup, on a schedule, and on system wake.
    /// This mode is used internally by the LaunchAgent for sleep/wake-aware syncing.
    private func runPersistentDaemon(mailDatabase: MailDatabase, vault: VaultContext) throws {
        let syncInterval = effectiveSyncInterval
        let exportDir = (vault.dataFolderPath as NSString).appendingPathComponent("Mail")

        log("Starting persistent mail sync daemon (pid=\(ProcessInfo.processInfo.processIdentifier))")
        log("Sync interval: \(formatInterval(syncInterval))")
        log("Export directory: \(exportDir)")

        // Run initial incremental sync on startup
        log("Running initial sync...")
        performDaemonSync(mailDatabase: mailDatabase, exportDir: exportDir)

        // Create a daemon controller to handle sleep/wake events
        let controller = MailSyncDaemonController(
            mailDatabase: mailDatabase,
            exportDir: exportDir,
            syncIntervalSeconds: TimeInterval(syncInterval),
            logger: log
        )

        // Start the run loop - this blocks until the daemon is terminated
        controller.startRunLoop()

        log("Daemon shutting down")
    }
}

// MARK: - Mail Sync Daemon Controller

/// Controls the mail sync daemon with sleep/wake detection.
/// Uses NSWorkspace notifications to detect system wake and trigger incremental sync.
final class MailSyncDaemonController: NSObject {
    private let mailDatabase: MailDatabase
    private let exportDir: String
    private let logger: (String) -> Void
    private var isSyncing = false
    private let syncQueue = DispatchQueue(label: "com.swiftea.mail.sync.daemon")
    private var syncTimer: Timer?
    private let backwardSync: MailSyncBackward

    /// Interval between scheduled syncs (configurable, default 1 minute)
    private let syncIntervalSeconds: TimeInterval

    /// Minimum interval between syncs to prevent rapid-fire syncing
    private static let minSyncIntervalSeconds: TimeInterval = 30

    /// Track last sync time to debounce wake events
    private var lastSyncTime: Date?

    init(mailDatabase: MailDatabase, exportDir: String, syncIntervalSeconds: TimeInterval = 60, logger: @escaping (String) -> Void) {
        self.mailDatabase = mailDatabase
        self.exportDir = exportDir
        self.syncIntervalSeconds = syncIntervalSeconds
        self.logger = logger
        self.backwardSync = MailSyncBackward(mailDatabase: mailDatabase)
        super.init()

        // Register for sleep/wake notifications
        registerForPowerNotifications()
    }

    deinit {
        unregisterForPowerNotifications()
        syncTimer?.invalidate()
    }

    /// Start the run loop. Blocks until the daemon is terminated.
    func startRunLoop() {
        // Schedule periodic sync timer
        scheduleSyncTimer()

        // Run the main run loop to receive notifications
        // This blocks until the process is terminated
        RunLoop.current.run()
    }

    // MARK: - Power Notifications

    private func registerForPowerNotifications() {
        let workspace = NSWorkspace.shared
        let center = workspace.notificationCenter

        // System woke from sleep
        center.addObserver(
            self,
            selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // System is about to sleep
        center.addObserver(
            self,
            selector: #selector(systemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        logger("Registered for sleep/wake notifications")
    }

    private func unregisterForPowerNotifications() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func systemDidWake(_ notification: Notification) {
        logger("System woke from sleep - triggering catch-up sync")
        triggerSync(reason: "wake")
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        logger("System going to sleep")
        // Cancel any pending sync timer - we'll sync on wake instead
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Sync Timer

    private func scheduleSyncTimer() {
        // Invalidate existing timer
        syncTimer?.invalidate()

        // Schedule new timer on the main run loop
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncIntervalSeconds, repeats: true) { [weak self] _ in
            self?.triggerSync(reason: "scheduled")
        }

        logger("Scheduled sync timer (every \(Int(syncIntervalSeconds))s)")
    }

    // MARK: - Sync Execution

    /// Trigger a sync, debouncing rapid-fire requests.
    private func triggerSync(reason: String) {
        // Debounce: don't sync if we synced very recently
        if let lastSync = lastSyncTime {
            let elapsed = Date().timeIntervalSince(lastSync)
            if elapsed < Self.minSyncIntervalSeconds {
                logger("Skipping \(reason) sync (last sync was \(Int(elapsed))s ago)")
                return
            }
        }

        // Don't spawn duplicate syncs
        syncQueue.async { [weak self] in
            guard let self = self else { return }

            if self.isSyncing {
                self.logger("Sync already in progress, skipping \(reason) sync")
                return
            }

            self.isSyncing = true
            self.lastSyncTime = Date()

            self.performSync(reason: reason)

            self.isSyncing = false

            // Re-schedule timer after wake (in case it was cancelled during sleep)
            if reason == "wake" {
                DispatchQueue.main.async {
                    self.scheduleSyncTimer()
                }
            }
        }
    }

    /// Perform the actual sync with retry logic.
    private func performSync(reason: String) {
        logger("Starting \(reason) sync...")

        let maxRetryAttempts = 5
        let baseRetryDelay: TimeInterval = 2.0
        let maxRetryDelay: TimeInterval = 60.0

        var attempt = 0
        var lastError: Error?

        while attempt < maxRetryAttempts {
            do {
                let sync = MailSync(mailDatabase: mailDatabase)
                let result = try sync.sync()

                logger("Sync complete: +\(result.messagesAdded) ~\(result.messagesUpdated) (\(String(format: "%.2f", result.duration))s)")

                if !result.errors.isEmpty {
                    logger("  \(result.errors.count) warning(s)")
                }

                // Auto-export new messages after successful sync
                performAutoExport()

                // Process pending backward sync actions (archive/delete from SwiftEA to Apple Mail)
                performBackwardSync()
                return

            } catch {
                lastError = error
                attempt += 1

                // Check if error is transient
                let description = error.localizedDescription.lowercased()
                let isTransient = description.contains("locked") ||
                                  description.contains("busy") ||
                                  description.contains("timeout") ||
                                  description.contains("temporarily") ||
                                  description.contains("try again")

                if isTransient && attempt < maxRetryAttempts {
                    let delay = min(baseRetryDelay * pow(2.0, Double(attempt - 1)), maxRetryDelay)
                    let jitter = delay * Double.random(in: 0.1...0.2)
                    let totalDelay = delay + jitter

                    logger("Transient error (attempt \(attempt)/\(maxRetryAttempts)): \(error.localizedDescription)")
                    logger("Retrying in \(String(format: "%.1f", totalDelay))s...")

                    Thread.sleep(forTimeInterval: totalDelay)
                } else {
                    break
                }
            }
        }

        if let error = lastError {
            logger("ERROR: Sync failed after \(attempt) attempt(s): \(error.localizedDescription)")
        }
    }

    /// Export newly synced messages to Swiftea/Mail/ as markdown files
    private func performAutoExport() {
        let exporter = MailExporter(mailDatabase: mailDatabase)

        do {
            let exportResult = try exporter.exportNewMessages(to: exportDir)

            if exportResult.exported > 0 {
                logger("Auto-export: \(exportResult.exported) message(s) to Swiftea/Mail/")
            }

            if !exportResult.errors.isEmpty {
                logger("  \(exportResult.errors.count) export warning(s)")
            }
        } catch {
            logger("ERROR: Auto-export failed: \(error.localizedDescription)")
        }
    }

    /// Process pending backward sync actions (archive/delete from SwiftEA to Apple Mail)
    private func performBackwardSync() {
        do {
            let result = try backwardSync.processPendingActions()

            // Log results if any actions were processed
            if result.archived > 0 || result.deleted > 0 {
                logger("Backward sync: \(result.archived) archived, \(result.deleted) deleted")
            }

            // Log warnings for failed actions
            if result.failed > 0 {
                logger("WARNING: Backward sync failed for \(result.failed) message(s)")
                for error in result.errors.prefix(3) {
                    logger("  - \(error)")
                }
                if result.errors.count > 3 {
                    logger("  ... and \(result.errors.count - 3) more errors")
                }
            }
        } catch {
            logger("ERROR: Backward sync failed: \(error.localizedDescription)")
        }
    }
}

/// Perform a sync in daemon mode with retry logic.
/// This is a standalone function for use during daemon startup.
private func performDaemonSync(mailDatabase: MailDatabase, exportDir: String) {
    let maxRetryAttempts = 5
    let baseRetryDelay: TimeInterval = 2.0
    let maxRetryDelay: TimeInterval = 60.0

    var attempt = 0

    while attempt < maxRetryAttempts {
        do {
            let sync = MailSync(mailDatabase: mailDatabase)
            let result = try sync.sync()

            let timestamp = ISO8601DateFormatter().string(from: Date())
            fputs("[\(timestamp)] Sync complete: +\(result.messagesAdded) ~\(result.messagesUpdated) (\(String(format: "%.2f", result.duration))s)\n", stdout)
            fflush(stdout)

            // Auto-export new messages after successful sync
            performDaemonAutoExport(mailDatabase: mailDatabase, exportDir: exportDir)

            // Process pending backward sync actions (archive/delete from SwiftEA to Apple Mail)
            performDaemonBackwardSync(mailDatabase: mailDatabase)
            return

        } catch {
            attempt += 1

            let description = error.localizedDescription.lowercased()
            let isTransient = description.contains("locked") ||
                              description.contains("busy") ||
                              description.contains("timeout") ||
                              description.contains("temporarily") ||
                              description.contains("try again")

            if isTransient && attempt < maxRetryAttempts {
                let delay = min(baseRetryDelay * pow(2.0, Double(attempt - 1)), maxRetryDelay)
                let jitter = delay * Double.random(in: 0.1...0.2)
                let totalDelay = delay + jitter

                let timestamp = ISO8601DateFormatter().string(from: Date())
                fputs("[\(timestamp)] Transient error (attempt \(attempt)/\(maxRetryAttempts)): \(error.localizedDescription)\n", stdout)
                fputs("[\(timestamp)] Retrying in \(String(format: "%.1f", totalDelay))s...\n", stdout)
                fflush(stdout)

                Thread.sleep(forTimeInterval: totalDelay)
            } else {
                let timestamp = ISO8601DateFormatter().string(from: Date())
                fputs("[\(timestamp)] ERROR: Initial sync failed: \(error.localizedDescription)\n", stderr)
                fflush(stderr)
                return
            }
        }
    }
}

/// Perform auto-export in daemon mode
private func performDaemonAutoExport(mailDatabase: MailDatabase, exportDir: String) {
    let exporter = MailExporter(mailDatabase: mailDatabase)

    do {
        let exportResult = try exporter.exportNewMessages(to: exportDir)

        if exportResult.exported > 0 {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            fputs("[\(timestamp)] Auto-export: \(exportResult.exported) message(s) to Swiftea/Mail/\n", stdout)
            fflush(stdout)
        }

        if !exportResult.errors.isEmpty {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            fputs("[\(timestamp)]   \(exportResult.errors.count) export warning(s)\n", stdout)
            fflush(stdout)
        }
    } catch {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        fputs("[\(timestamp)] ERROR: Auto-export failed: \(error.localizedDescription)\n", stderr)
        fflush(stderr)
    }
}

/// Process pending backward sync actions in daemon mode (archive/delete from SwiftEA to Apple Mail)
private func performDaemonBackwardSync(mailDatabase: MailDatabase) {
    let backwardSync = MailSyncBackward(mailDatabase: mailDatabase)

    do {
        let result = try backwardSync.processPendingActions()

        // Log results if any actions were processed
        if result.archived > 0 || result.deleted > 0 {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            fputs("[\(timestamp)] Backward sync: \(result.archived) archived, \(result.deleted) deleted\n", stdout)
            fflush(stdout)
        }

        // Log warnings for failed actions
        if result.failed > 0 {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            fputs("[\(timestamp)] WARNING: Backward sync failed for \(result.failed) message(s)\n", stdout)
            fflush(stdout)
            for error in result.errors.prefix(3) {
                fputs("[\(timestamp)]   - \(error)\n", stdout)
            }
            if result.errors.count > 3 {
                fputs("[\(timestamp)]   ... and \(result.errors.count - 3) more errors\n", stdout)
            }
            fflush(stdout)
        }
    } catch {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        fputs("[\(timestamp)] ERROR: Backward sync failed: \(error.localizedDescription)\n", stderr)
        fflush(stderr)
    }
}

struct MailSearchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search mail using full-text search with structured filters",
        discussion: """
            Search for mail messages using full-text search and/or structured filters.

            STRUCTURED FILTERS:
              from:email       - Filter by sender email or name
              to:email         - Filter by recipient email or name
              subject:text     - Filter by subject containing text
              mailbox:name     - Filter by mailbox name
              is:read          - Show only read messages
              is:unread        - Show only unread messages
              is:flagged       - Show only flagged messages
              is:unflagged     - Show only unflagged messages
              has:attachments  - Show only messages with attachments
              after:YYYY-MM-DD - Messages received after date
              before:YYYY-MM-DD - Messages received before date
              date:YYYY-MM-DD  - Messages received on specific date

            STATUS FILTER (--status):
              inbox    - Messages in your inbox
              archived - Messages you've archived
              deleted  - Messages you've deleted

            EXAMPLES:
              swea mail search "from:alice@example.com project"
              swea mail search "is:unread is:flagged"
              swea mail search "after:2024-01-01 before:2024-02-01"
              swea mail search "mailbox:INBOX from:support"
              swea mail search --status inbox "from:support"
              swea mail search --status archived ""

            Use quotes around values with spaces: from:"Alice Smith"
            """
    )

    @Argument(help: "Search query with optional structured filters")
    var query: String

    @Option(name: .long, help: "Filter by mailbox status: inbox, archived, deleted")
    var status: String?

    @Option(name: .long, help: "Maximum results to return")
    var limit: Int = 20

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func validate() throws {
        // --limit must be a positive integer
        if limit <= 0 {
            throw MailValidationError.invalidLimit
        }

        // --status must be a valid value if provided
        if let status = status {
            let validStatuses = ["inbox", "archived", "deleted"]
            if !validStatuses.contains(status.lowercased()) {
                throw MailValidationError.invalidStatus(value: status)
            }
        }
    }

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        // Parse the query for structured filters
        var filter = mailDatabase.parseQuery(query)

        // Apply --status option if provided
        if let statusValue = status {
            filter.mailboxStatus = MailboxStatus(rawValue: statusValue.lowercased())
        }

        // Use structured search if we have filters, otherwise fall back to basic FTS
        let results: [MailMessage]
        if filter.hasFilters || filter.hasFreeText {
            results = try mailDatabase.searchMessagesWithFilters(filter, limit: limit)
        } else {
            // Empty query - show recent messages
            results = try mailDatabase.getAllMessages(limit: limit)
        }

        if results.isEmpty {
            printError("No messages found for: \(query)")
            return
        }

        if json {
            // Output as JSON with filter info
            var output: [[String: Any]] = []
            for msg in results {
                let msgDict: [String: Any] = [
                    "id": msg.id,
                    "subject": msg.subject,
                    "sender": msg.senderEmail ?? "",
                    "senderName": msg.senderName ?? "",
                    "date": msg.dateSent?.description ?? "",
                    "mailbox": msg.mailboxName ?? "",
                    "isRead": msg.isRead,
                    "isFlagged": msg.isFlagged,
                    "hasAttachments": msg.hasAttachments
                ]
                output.append(msgDict)
            }
            if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
               let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            // Show filter summary if structured filters were used
            if filter.hasFilters {
                var filterDesc: [String] = []
                if let from = filter.from { filterDesc.append("from:\(from)") }
                if let to = filter.to { filterDesc.append("to:\(to)") }
                if let subject = filter.subject { filterDesc.append("subject:\(subject)") }
                if let mailbox = filter.mailbox { filterDesc.append("mailbox:\(mailbox)") }
                if let mailboxStatus = filter.mailboxStatus { filterDesc.append("status:\(mailboxStatus.rawValue)") }
                if let isRead = filter.isRead { filterDesc.append(isRead ? "is:read" : "is:unread") }
                if let isFlagged = filter.isFlagged { filterDesc.append(isFlagged ? "is:flagged" : "is:unflagged") }
                if filter.hasAttachments == true { filterDesc.append("has:attachments") }
                if filter.dateAfter != nil || filter.dateBefore != nil {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd"
                    if let after = filter.dateAfter { filterDesc.append("after:\(df.string(from: after))") }
                    if let before = filter.dateBefore { filterDesc.append("before:\(df.string(from: before))") }
                }
                print("Filters: \(filterDesc.joined(separator: " "))")
                if let freeText = filter.freeText {
                    print("Search: \(freeText)")
                }
                print("")
            }

            print("Found \(results.count) message(s):\n")
            for msg in results {
                let date = msg.dateSent.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "Unknown"
                let sender = msg.senderName ?? msg.senderEmail ?? "Unknown"
                var flags: [String] = []
                if !msg.isRead { flags.append("UNREAD") }
                if msg.isFlagged { flags.append("FLAGGED") }
                if msg.hasAttachments { flags.append("ATTACH") }
                let flagStr = flags.isEmpty ? "" : " [\(flags.joined(separator: ", "))]"

                print("[\(msg.id)]\(flagStr)")
                print("  Subject: \(msg.subject)")
                print("  From: \(sender)")
                print("  Date: \(date)")
                print("  Mailbox: \(msg.mailboxName ?? "Unknown")")
                print("")
            }
        }
    }
}

struct MailShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Display a single email message"
    )

    @Argument(help: "Message ID to display")
    var id: String

    @Flag(name: .long, help: "Show HTML body instead of plain text")
    var html: Bool = false

    @Flag(name: .long, help: "Show raw .emlx content")
    var raw: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        guard let message = try mailDatabase.getMessage(id: id) else {
            printError("Message not found: \(id)")
            throw ExitCode.failure
        }

        // Handle --raw flag: read original .emlx file
        if raw {
            guard let emlxPath = message.emlxPath else {
                printError("No .emlx path available for this message")
                throw ExitCode.failure
            }

            // Check for EWS (Exchange) mailbox paths which contain "ews:" prefix
            // These are cloud-based mailboxes that don't have local .emlx files
            if emlxPath.contains("ews:") || emlxPath.contains("/ews:/") {
                printError("Raw .emlx viewing is not available for Exchange (EWS) mailboxes.")
                printError("Exchange messages are stored on the server, not as local .emlx files.")
                printError("Use 'mail show \(id)' without --raw to view the message content.")
                throw ExitCode.failure
            }

            guard let content = try? String(contentsOfFile: emlxPath, encoding: .utf8) else {
                printError("Could not read .emlx file: \(emlxPath)")
                throw ExitCode.failure
            }
            print(content)
            return
        }

        // Handle --json flag
        if json {
            let output: [String: Any] = [
                "id": message.id,
                "messageId": message.messageId ?? "",
                "subject": message.subject,
                "from": formatSender(message),
                "date": message.dateSent?.iso8601String ?? "",
                "mailbox": message.mailboxName ?? "",
                "isRead": message.isRead,
                "isFlagged": message.isFlagged,
                "hasAttachments": message.hasAttachments,
                "body": html ? (message.bodyHtml ?? "") : (message.bodyText ?? "")
            ]
            if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
               let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
            return
        }

        // Default: formatted text output
        let date = message.dateSent.map { DateFormatter.localizedString(from: $0, dateStyle: .long, timeStyle: .long) } ?? "Unknown"
        let sender = formatSender(message)

        print("Subject: \(message.subject)")
        print("From: \(sender)")
        print("Date: \(date)")
        print("Mailbox: \(message.mailboxName ?? "Unknown")")
        if message.hasAttachments {
            print("Attachments: Yes")
        }
        print("")
        print(String(repeating: "-", count: 60))
        print("")

        // Show body content
        if html {
            if let htmlBody = message.bodyHtml {
                print(htmlBody)
            } else {
                print("(No HTML body available)")
            }
        } else {
            if let textBody = message.bodyText {
                print(textBody)
            } else if let htmlBody = message.bodyHtml {
                // Fallback: strip HTML tags for plain text display
                print(stripHtml(htmlBody))
            } else {
                print("(No message body available)")
            }
        }
    }

    private func formatSender(_ message: MailMessage) -> String {
        if let name = message.senderName, let email = message.senderEmail {
            return "\(name) <\(email)>"
        } else if let email = message.senderEmail {
            return email
        } else if let name = message.senderName {
            return name
        }
        return "Unknown"
    }

    private func stripHtml(_ html: String) -> String {
        // Simple HTML tag stripping
        var result = html
        // Remove script and style blocks
        result = result.replacingOccurrences(of: "<script[^>]*>.*?</script>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "<style[^>]*>.*?</style>", with: "", options: .regularExpression)
        // Replace common entities
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        // Replace <br> and </p> with newlines
        result = result.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</p>", with: "\n\n")
        // Remove all remaining tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Collapse multiple newlines
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Output format for mail export command.
/// Conforms to ExpressibleByArgument for ArgumentParser integration,
/// enabling type-safe parsing with automatic validation.
public enum OutputFormat: String, CaseIterable, ExpressibleByArgument {
    case markdown
    case md
    case json

    /// All valid format values for help text and error messages
    public static var allValueStrings: [String] {
        allCases.map { $0.rawValue }
    }

    /// Check if this format produces JSON output
    var isJson: Bool {
        self == .json
    }

    /// Check if this format produces Markdown output
    var isMarkdown: Bool {
        self == .markdown || self == .md
    }

    /// File extension for this format
    var fileExtension: String {
        isJson ? "json" : "md"
    }
}

struct MailExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export synced messages to markdown or JSON files",
        discussion: """
            Creates .md or .json files from synced messages. Note: 'swea mail sync'
            now auto-exports new messages, so manual export is usually not needed.

            Default output: Swiftea/Mail/ (same as auto-export)
            Markdown files include YAML frontmatter for Obsidian compatibility.

            EXAMPLES
              swea mail export                              # Export all (up to limit)
              swea mail export --query "from:alice"         # Export matching messages
              swea mail export --output ~/Obsidian/Mail     # Export to custom folder
              swea mail export --format json                # Export as JSON
              swea mail export --include-attachments        # Also save attachments

            Use --include-attachments to also extract and save attachment files.
            Attachments are saved in an 'attachments/<message-id>/' subdirectory.

            THREAD EXPORT
              swea mail export --format json --thread <thread-id>   # Export full thread structure

            Thread exports include a nested messages array with thread_position for each message.
            """
    )

    @Option(name: .long, help: "Export format: \(OutputFormat.allValueStrings.joined(separator: ", "))")
    var format: OutputFormat = .markdown

    @Option(name: .long, help: "Message ID to export (or 'all' for all synced messages)")
    var id: String = "all"

    @Option(name: .shortAndLong, help: "Output directory (default: Swiftea/Mail/)")
    var output: String?

    @Option(name: .long, help: "Search query to filter messages for export")
    var query: String?

    @Option(name: .long, help: "Maximum messages to export (default: 100)")
    var limit: Int = 100

    @Flag(name: .long, help: "Extract and save attachment files")
    var includeAttachments: Bool = false

    @Option(name: .long, help: "Thread ID to export as full thread structure (JSON only)")
    var thread: String?

    func validate() throws {
        // --limit must be a positive integer
        if limit <= 0 {
            throw MailValidationError.invalidLimit
        }
        // --thread requires --format json
        if thread != nil && !format.isJson {
            throw ValidationError("--thread requires --format json")
        }
        // Note: --format validation is handled automatically by ArgumentParser via OutputFormat enum
    }

    func run() throws {
        let vault = try VaultContext.require()

        // Determine output directory (default: Swiftea/Mail/ for Obsidian compatibility)
        let outputDir: String
        if let specifiedOutput = output {
            outputDir = specifiedOutput
        } else {
            outputDir = (vault.dataFolderPath as NSString).appendingPathComponent("Mail")
        }

        // Create output directory if needed
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: outputDir) {
            try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        }

        // Open mail database
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        // Handle thread export mode
        if let threadId = thread {
            try exportThread(threadId: threadId, outputDir: outputDir, database: mailDatabase)
            return
        }

        // Get messages to export
        var messages: [MailMessage] = []

        if id != "all" {
            // Export single message
            if let message = try mailDatabase.getMessage(id: id) {
                messages = [message]
            } else {
                printError("Message not found: \(id)")
                throw ExitCode.failure
            }
        } else if let searchQuery = query {
            // Export messages matching query
            messages = try mailDatabase.searchMessages(query: searchQuery, limit: limit)
        } else {
            // Export all messages (up to limit) - use direct query without FTS
            messages = try mailDatabase.getAllMessages(limit: limit)
        }

        if messages.isEmpty {
            printError("No messages to export")
            return
        }

        print("Exporting \(messages.count) message(s) to \(outputDir)...")

        var exportedCount = 0
        var attachmentCount = 0
        let emlxParser = EmlxParser()

        for message in messages {
            let filename = generateFilename(for: message)
            let filePath = (outputDir as NSString).appendingPathComponent(filename)

            let content: String
            if format.isJson {
                content = formatAsJson(message)
            } else {
                content = formatAsMarkdown(message)
            }

            try content.write(toFile: filePath, atomically: true, encoding: .utf8)

            // Update export path in database
            try mailDatabase.updateExportPath(id: message.id, path: filePath)
            exportedCount += 1

            // Extract attachments if requested
            if includeAttachments, message.hasAttachments, let emlxPath = message.emlxPath {
                // Skip EWS/Exchange messages (no local .emlx file)
                if emlxPath.contains("ews:") || emlxPath.contains("/ews:/") {
                    continue
                }

                let attachmentsDir = (outputDir as NSString).appendingPathComponent("attachments/\(message.id)")

                do {
                    let attachments = try emlxParser.extractAttachments(path: emlxPath)

                    if !attachments.isEmpty {
                        // Create attachments directory
                        if !fileManager.fileExists(atPath: attachmentsDir) {
                            try fileManager.createDirectory(atPath: attachmentsDir, withIntermediateDirectories: true)
                        }

                        for attachment in attachments {
                            let attachmentPath = (attachmentsDir as NSString).appendingPathComponent(attachment.info.filename)
                            try attachment.data.write(to: URL(fileURLWithPath: attachmentPath))
                            attachmentCount += 1
                        }
                    }
                } catch {
                    // Log warning but continue exporting
                    printError("  Warning: Could not extract attachments from \(message.id): \(error.localizedDescription)")
                }
            }
        }

        print("Exported \(exportedCount) message(s) to \(outputDir)")
        if attachmentCount > 0 {
            print("Extracted \(attachmentCount) attachment(s)")
        }
    }

    private func generateFilename(for message: MailMessage) -> String {
        // Flat filename using message ID for uniqueness and idempotent overwrites
        return "\(message.id).\(format.fileExtension)"
    }

    private func formatAsMarkdown(_ message: MailMessage) -> String {
        var lines: [String] = []

        // Minimal YAML frontmatter: id, subject, from, date, aliases
        lines.append("---")
        lines.append("id: \"\(message.id)\"")
        lines.append("subject: \"\(escapeYaml(message.subject))\"")
        lines.append("from: \"\(escapeYaml(formatSender(message)))\"")
        if let date = message.dateSent {
            lines.append("date: \(date.iso8601String)")
        }
        // aliases: use subject as an alias for linking by topic
        lines.append("aliases:")
        lines.append("  - \"\(escapeYaml(message.subject))\"")
        lines.append("---")
        lines.append("")

        // Subject as heading
        lines.append("# \(message.subject)")
        lines.append("")

        // Body content
        if let textBody = message.bodyText, !textBody.isEmpty {
            lines.append(textBody)
        } else if let htmlBody = message.bodyHtml {
            // Fall back to stripped HTML
            lines.append(stripHtml(htmlBody))
        } else {
            lines.append("*(No message body)*")
        }

        return lines.joined(separator: "\n")
    }

    private func formatAsJson(_ message: MailMessage, threadPosition: Int? = nil, threadTotal: Int? = nil) -> String {
        var output: [String: Any] = [
            "id": message.id,
            "messageId": message.messageId ?? "",
            "subject": message.subject,
            "from": [
                "name": message.senderName ?? "",
                "email": message.senderEmail ?? ""
            ],
            "date": message.dateSent?.iso8601String ?? "",
            "mailbox": message.mailboxName ?? "",
            "isRead": message.isRead,
            "isFlagged": message.isFlagged,
            "hasAttachments": message.hasAttachments,
            "bodyText": message.bodyText ?? "",
            "bodyHtml": message.bodyHtml ?? ""
        ]

        // Add thread fields if available
        if let threadId = message.threadId {
            output["thread_id"] = threadId
        }
        if let position = threadPosition {
            output["thread_position"] = position
        }
        if let total = threadTotal {
            output["thread_total"] = total
        }

        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    /// Convert a MailMessage to a dictionary for JSON serialization (used in thread exports)
    private func messageToDict(_ message: MailMessage, threadPosition: Int, threadTotal: Int) -> [String: Any] {
        return [
            "id": message.id,
            "messageId": message.messageId ?? "",
            "subject": message.subject,
            "from": [
                "name": message.senderName ?? "",
                "email": message.senderEmail ?? ""
            ],
            "date": message.dateSent?.iso8601String ?? "",
            "mailbox": message.mailboxName ?? "",
            "isRead": message.isRead,
            "isFlagged": message.isFlagged,
            "hasAttachments": message.hasAttachments,
            "bodyText": message.bodyText ?? "",
            "bodyHtml": message.bodyHtml ?? "",
            "thread_id": message.threadId ?? "",
            "thread_position": threadPosition,
            "thread_total": threadTotal
        ]
    }

    /// Export a thread with full structure including nested messages array
    private func exportThread(threadId: String, outputDir: String, database: MailDatabase) throws {
        // Get thread metadata
        guard let thread = try database.getThread(id: threadId) else {
            printError("Thread not found: \(threadId)")
            throw ExitCode.failure
        }

        // Get all messages in the thread, sorted by date
        let messages = try database.getMessagesInThreadViaJunction(threadId: threadId, limit: 10000)

        if messages.isEmpty {
            printError("Thread has no messages: \(threadId)")
            throw ExitCode.failure
        }

        let threadTotal = messages.count

        // Build nested messages array with thread position
        var messagesArray: [[String: Any]] = []
        for (index, message) in messages.enumerated() {
            let position = index + 1  // 1-indexed position
            messagesArray.append(messageToDict(message, threadPosition: position, threadTotal: threadTotal))
        }

        // Build thread export structure
        let threadExport: [String: Any] = [
            "thread_id": threadId,
            "subject": thread.subject ?? "",
            "participant_count": thread.participantCount,
            "message_count": thread.messageCount,
            "first_date": thread.firstDate?.iso8601String ?? "",
            "last_date": thread.lastDate?.iso8601String ?? "",
            "messages": messagesArray
        ]

        // Write to file
        let filename = "thread-\(threadId).json"
        let filePath = (outputDir as NSString).appendingPathComponent(filename)

        if let data = try? JSONSerialization.data(withJSONObject: threadExport, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: data, encoding: .utf8) {
            try jsonString.write(toFile: filePath, atomically: true, encoding: .utf8)
            print("Exported thread with \(threadTotal) message(s) to \(filePath)")
        } else {
            printError("Failed to serialize thread to JSON")
            throw ExitCode.failure
        }
    }

    private func formatSender(_ message: MailMessage) -> String {
        if let name = message.senderName, let email = message.senderEmail {
            return "\(name) <\(email)>"
        } else if let email = message.senderEmail {
            return email
        } else if let name = message.senderName {
            return name
        }
        return "Unknown"
    }

    private func escapeYaml(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func stripHtml(_ html: String) -> String {
        var result = html
        result = result.replacingOccurrences(of: "<script[^>]*>.*?</script>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "<style[^>]*>.*?</style>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</p>", with: "\n\n")
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Mail Export Threads Command

struct MailExportThreadsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export-threads",
        abstract: "Export entire email threads as single units",
        discussion: """
            Exports complete email threads (conversations) to markdown or JSON files.
            Each thread is exported as a single file containing all messages in the
            conversation, ordered chronologically.

            EXAMPLES
              swea mail export-threads                          # Export all threads (up to limit)
              swea mail export-threads --thread-id abc123       # Export specific thread
              swea mail export-threads --format json            # Export as JSON
              swea mail export-threads --output ~/Threads       # Export to custom folder
              swea mail export-threads --limit 50               # Export up to 50 threads
            """
    )

    @Option(name: .long, help: "Export format: \(OutputFormat.allValueStrings.joined(separator: ", "))")
    var format: OutputFormat = .markdown

    @Option(name: .long, help: "Specific thread ID to export")
    var threadId: String?

    @Option(name: .shortAndLong, help: "Output directory (default: Swiftea/Threads/)")
    var output: String?

    @Option(name: .long, help: "Maximum threads to export (default: 100)")
    var limit: Int = 100

    func validate() throws {
        if limit <= 0 {
            throw MailValidationError.invalidLimit
        }
    }

    func run() throws {
        let vault = try VaultContext.require()

        // Determine output directory (default: Swiftea/Threads/)
        let outputDir: String
        if let specifiedOutput = output {
            outputDir = specifiedOutput
        } else {
            outputDir = (vault.dataFolderPath as NSString).appendingPathComponent("Threads")
        }

        // Create output directory if needed
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: outputDir) {
            try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        }

        // Open mail database
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        // Get threads to export - handle single thread vs all threads differently
        // to avoid type annotation issues with SwiftEAKit.Thread shadowing
        if let specificThreadId = threadId {
            // Export single thread
            guard let thread = try mailDatabase.getThread(id: specificThreadId) else {
                printError("Thread not found: \(specificThreadId)")
                throw ExitCode.failure
            }

            let filename = "thread-\(thread.id).\(format.fileExtension)"
            let filePath = (outputDir as NSString).appendingPathComponent(filename)
            let messages = try mailDatabase.getMessagesInThreadViaJunction(threadId: thread.id, limit: 10000)

            let content: String
            if format.isJson {
                content = formatThreadAsJson(threadId: thread.id, subject: thread.subject, participantCount: thread.participantCount, messageCount: thread.messageCount, firstDate: thread.firstDate, lastDate: thread.lastDate, messages: messages)
            } else {
                content = formatThreadAsMarkdown(threadId: thread.id, subject: thread.subject, participantCount: thread.participantCount, messageCount: thread.messageCount, firstDate: thread.firstDate, lastDate: thread.lastDate, messages: messages)
            }

            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            print("Exported 1 thread to \(outputDir)")
            return
        }

        // Export all threads (up to limit)
        let threads = try mailDatabase.getThreads(limit: limit)

        if threads.isEmpty {
            printError("No threads to export")
            return
        }

        print("Exporting \(threads.count) thread(s) to \(outputDir)...")

        var exportedCount = 0

        for thread in threads {
            let filename = "thread-\(thread.id).\(format.fileExtension)"
            let filePath = (outputDir as NSString).appendingPathComponent(filename)

            // Get all messages in the thread, sorted by date
            let messages = try mailDatabase.getMessagesInThreadViaJunction(threadId: thread.id, limit: 10000)

            let content: String
            if format.isJson {
                content = formatThreadAsJson(threadId: thread.id, subject: thread.subject, participantCount: thread.participantCount, messageCount: thread.messageCount, firstDate: thread.firstDate, lastDate: thread.lastDate, messages: messages)
            } else {
                content = formatThreadAsMarkdown(threadId: thread.id, subject: thread.subject, participantCount: thread.participantCount, messageCount: thread.messageCount, firstDate: thread.firstDate, lastDate: thread.lastDate, messages: messages)
            }

            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            exportedCount += 1
        }

        print("Exported \(exportedCount) thread(s) to \(outputDir)")
    }

    private func formatThreadAsJson(threadId: String, subject: String?, participantCount: Int, messageCount: Int, firstDate: Date?, lastDate: Date?, messages: [MailMessage]) -> String {
        let threadTotal = messages.count

        // Build nested messages array with thread position
        var messagesArray: [[String: Any]] = []
        for (index, message) in messages.enumerated() {
            let position = index + 1  // 1-indexed position
            messagesArray.append(messageToDict(message, threadPosition: position, threadTotal: threadTotal))
        }

        // Build thread export structure
        let threadExport: [String: Any] = [
            "thread_id": threadId,
            "subject": subject ?? "",
            "participant_count": participantCount,
            "message_count": messageCount,
            "first_date": firstDate?.iso8601String ?? "",
            "last_date": lastDate?.iso8601String ?? "",
            "messages": messagesArray
        ]

        if let data = try? JSONSerialization.data(withJSONObject: threadExport, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    private func formatThreadAsMarkdown(threadId: String, subject: String?, participantCount: Int, messageCount: Int, firstDate: Date?, lastDate: Date?, messages: [MailMessage]) -> String {
        var lines: [String] = []
        let threadTotal = messages.count

        // YAML frontmatter with thread metadata
        lines.append("---")
        lines.append("thread_id: \"\(threadId)\"")
        lines.append("subject: \"\(escapeYaml(subject ?? ""))\"")
        lines.append("participant_count: \(participantCount)")
        lines.append("message_count: \(messageCount)")
        if let firstDate = firstDate {
            lines.append("first_date: \(firstDate.iso8601String)")
        }
        if let lastDate = lastDate {
            lines.append("last_date: \(lastDate.iso8601String)")
        }
        lines.append("---")
        lines.append("")

        // Thread heading
        lines.append("# Thread: \(subject ?? "(No Subject)")")
        lines.append("")
        lines.append("**\(threadTotal) message(s) between \(participantCount) participant(s)**")
        lines.append("")

        // Each message in the thread
        for (index, message) in messages.enumerated() {
            let position = index + 1
            lines.append("---")
            lines.append("")
            lines.append("## Message \(position) of \(threadTotal)")
            lines.append("")
            lines.append("**From:** \(formatSender(message))")
            if let date = message.dateSent {
                lines.append("**Date:** \(date.iso8601String)")
            }
            lines.append("**Subject:** \(message.subject)")
            lines.append("")

            // Body content
            if let textBody = message.bodyText, !textBody.isEmpty {
                lines.append(textBody)
            } else if let htmlBody = message.bodyHtml {
                lines.append(stripHtml(htmlBody))
            } else {
                lines.append("*(No message body)*")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func messageToDict(_ message: MailMessage, threadPosition: Int, threadTotal: Int) -> [String: Any] {
        return [
            "id": message.id,
            "messageId": message.messageId ?? "",
            "subject": message.subject,
            "from": [
                "name": message.senderName ?? "",
                "email": message.senderEmail ?? ""
            ],
            "date": message.dateSent?.iso8601String ?? "",
            "mailbox": message.mailboxName ?? "",
            "isRead": message.isRead,
            "isFlagged": message.isFlagged,
            "hasAttachments": message.hasAttachments,
            "bodyText": message.bodyText ?? "",
            "bodyHtml": message.bodyHtml ?? "",
            "thread_id": message.threadId ?? "",
            "thread_position": threadPosition,
            "thread_total": threadTotal
        ]
    }

    private func formatSender(_ message: MailMessage) -> String {
        if let name = message.senderName, let email = message.senderEmail {
            return "\(name) <\(email)>"
        } else if let email = message.senderEmail {
            return email
        } else if let name = message.senderName {
            return name
        }
        return "Unknown"
    }

    private func escapeYaml(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func stripHtml(_ html: String) -> String {
        var result = html
        result = result.replacingOccurrences(of: "<script[^>]*>.*?</script>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "<style[^>]*>.*?</style>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</p>", with: "\n\n")
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Mail Validation Errors

/// Error thrown when CLI input validation fails
public enum MailValidationError: Error, LocalizedError, Equatable {
    case invalidLimit
    case emptyRecipient
    case watchAndStopMutuallyExclusive
    case invalidInterval(minimum: Int)
    case invalidStatus(value: String)

    public var errorDescription: String? {
        switch self {
        case .invalidLimit:
            return "--limit must be a positive integer"
        case .emptyRecipient:
            return "--to requires a non-empty email address"
        case .watchAndStopMutuallyExclusive:
            return "--watch and --stop cannot be used together"
        case .invalidInterval(let minimum):
            return "--interval must be at least \(minimum) seconds"
        case .invalidStatus(let value):
            return "Invalid status '\(value)'. Valid options: inbox, archived, deleted"
        }
    }
}

// MARK: - Mail Action Commands

/// Error thrown when action validation fails
enum MailActionError: Error, LocalizedError {
    case messageNotFound(String)
    case mailboxRequired
    case confirmationRequired(action: String)
    case invalidFlagOperation
    case invalidMarkOperation

    var errorDescription: String? {
        switch self {
        case .messageNotFound(let id):
            return "Message not found: \(id)"
        case .mailboxRequired:
            return "Target mailbox is required. Use --mailbox to specify destination."
        case .confirmationRequired(let action):
            return "Destructive action '\(action)' requires --yes to confirm or --dry-run to preview."
        case .invalidFlagOperation:
            return "Specify either --set or --clear for flag operation."
        case .invalidMarkOperation:
            return "Specify either --read or --unread for mark operation."
        }
    }
}

struct MailArchiveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Archive a mail message",
        discussion: """
            Moves the specified message to the Archive mailbox in Mail.app.

            DESTRUCTIVE ACTION: This command modifies your mailbox.
            Use --dry-run to preview the action without making changes.
            Use --yes to confirm the action.
            """
    )

    @Option(name: .long, help: "Message ID to archive (required)")
    var id: String

    @Flag(name: .long, help: "Confirm the destructive action")
    var yes: Bool = false

    @Flag(name: .long, help: "Preview the action without making changes")
    var dryRun: Bool = false

    func validate() throws {
        // Validate that either --yes or --dry-run is provided
        if !yes && !dryRun {
            throw MailActionError.confirmationRequired(action: "archive")
        }
    }

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        // Resolve message to Mail.app reference
        let resolver = MessageResolver(database: mailDatabase)
        let resolved = try resolver.resolve(id: id)

        if dryRun {
            print("[DRY RUN] Would archive message:")
            print("  ID: \(resolved.swiftEAId)")
            print("  Message-ID: \(resolved.messageId)")
            print("  Subject: \(resolved.message.subject)")
            print("  From: \(resolved.message.senderEmail ?? "Unknown")")
            print("  Current mailbox: \(resolved.message.mailboxName ?? "Unknown")")
            return
        }

        // Use MailSyncBackward for optimistic update pattern
        let backwardSync = MailSyncBackward(mailDatabase: mailDatabase)
        try backwardSync.archiveMessage(id: resolved.swiftEAId)

        print("Archived message: \(resolved.swiftEAId)")
        print("  Subject: \(resolved.message.subject)")
    }
}

struct MailDeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a mail message",
        discussion: """
            Moves the specified message to the Trash mailbox in Mail.app.

            DESTRUCTIVE ACTION: This command modifies your mailbox.
            Use --dry-run to preview the action without making changes.
            Use --yes to confirm the action.
            """
    )

    @Option(name: .long, help: "Message ID to delete (required)")
    var id: String

    @Flag(name: .long, help: "Confirm the destructive action")
    var yes: Bool = false

    @Flag(name: .long, help: "Preview the action without making changes")
    var dryRun: Bool = false

    func validate() throws {
        // Validate that either --yes or --dry-run is provided
        if !yes && !dryRun {
            throw MailActionError.confirmationRequired(action: "delete")
        }
    }

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        // Resolve message to Mail.app reference
        let resolver = MessageResolver(database: mailDatabase)
        let resolved = try resolver.resolve(id: id)

        if dryRun {
            print("[DRY RUN] Would delete message:")
            print("  ID: \(resolved.swiftEAId)")
            print("  Message-ID: \(resolved.messageId)")
            print("  Subject: \(resolved.message.subject)")
            print("  From: \(resolved.message.senderEmail ?? "Unknown")")
            print("  Current mailbox: \(resolved.message.mailboxName ?? "Unknown")")
            return
        }

        // Use MailSyncBackward for optimistic update pattern
        let backwardSync = MailSyncBackward(mailDatabase: mailDatabase)
        try backwardSync.deleteMessage(id: resolved.swiftEAId)

        print("Deleted message: \(resolved.swiftEAId)")
        print("  Subject: \(resolved.message.subject)")
    }
}

struct MailMoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Move a mail message to a different mailbox",
        discussion: """
            Moves the specified message to the target mailbox in Mail.app.

            DESTRUCTIVE ACTION: This command modifies your mailbox.
            Use --dry-run to preview the action without making changes.
            Use --yes to confirm the action.
            """
    )

    @Option(name: .long, help: "Message ID to move (required)")
    var id: String

    @Option(name: .long, help: "Target mailbox name (required)")
    var mailbox: String?

    @Flag(name: .long, help: "Confirm the destructive action")
    var yes: Bool = false

    @Flag(name: .long, help: "Preview the action without making changes")
    var dryRun: Bool = false

    func validate() throws {
        // Validate mailbox is provided
        guard mailbox != nil else {
            throw MailActionError.mailboxRequired
        }

        // Validate that either --yes or --dry-run is provided
        if !yes && !dryRun {
            throw MailActionError.confirmationRequired(action: "move")
        }
    }

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        // Resolve message to Mail.app reference
        let resolver = MessageResolver(database: mailDatabase)
        let resolved = try resolver.resolve(id: id)

        let targetMailbox = mailbox!

        if dryRun {
            print("[DRY RUN] Would move message:")
            print("  ID: \(resolved.swiftEAId)")
            print("  Message-ID: \(resolved.messageId)")
            print("  Subject: \(resolved.message.subject)")
            print("  From: \(resolved.message.senderEmail ?? "Unknown")")
            print("  Current mailbox: \(resolved.message.mailboxName ?? "Unknown")")
            print("  Target mailbox: \(targetMailbox)")
            return
        }

        // Execute move via AppleScript
        // Use the same account as the source message for the target mailbox
        let script = MailActionScripts.moveMessage(byMessageId: resolved.messageId, toMailbox: targetMailbox)

        let appleScriptService = AppleScriptService.shared
        let result = try appleScriptService.executeMailScript(script)

        if result.success {
            print("Moved message: \(resolved.swiftEAId)")
            print("  Subject: \(resolved.message.subject)")
            print("  To mailbox: \(targetMailbox)")
        }
    }
}

struct MailFlagCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flag",
        abstract: "Set or clear the flag on a mail message",
        discussion: """
            Sets or clears the flag (star) on the specified message in Mail.app.

            Use --set to flag the message.
            Use --clear to remove the flag.
            Use --dry-run to preview the action without making changes.
            """
    )

    @Option(name: .long, help: "Message ID to flag/unflag (required)")
    var id: String

    @Flag(name: .long, help: "Set the flag on the message")
    var set: Bool = false

    @Flag(name: .long, help: "Clear the flag from the message")
    var clear: Bool = false

    @Flag(name: .long, help: "Preview the action without making changes")
    var dryRun: Bool = false

    func validate() throws {
        // Exactly one of --set or --clear must be provided
        if set == clear {
            throw MailActionError.invalidFlagOperation
        }
    }

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        // Resolve message to Mail.app reference
        let resolver = MessageResolver(database: mailDatabase)
        let resolved = try resolver.resolve(id: id)

        let willFlag = set
        let action = willFlag ? "flag" : "unflag"

        if dryRun {
            print("[DRY RUN] Would \(action) message:")
            print("  ID: \(resolved.swiftEAId)")
            print("  Message-ID: \(resolved.messageId)")
            print("  Subject: \(resolved.message.subject)")
            print("  Current flag status: \(resolved.message.isFlagged ? "flagged" : "not flagged")")
            return
        }

        // Execute flag via AppleScript
        let script = MailActionScripts.setFlag(byMessageId: resolved.messageId, flagged: willFlag)

        let appleScriptService = AppleScriptService.shared
        let result = try appleScriptService.executeMailScript(script)

        if result.success {
            print("\(willFlag ? "Flagged" : "Unflagged") message: \(resolved.swiftEAId)")
            print("  Subject: \(resolved.message.subject)")
        }
    }
}

struct MailMarkCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mark",
        abstract: "Mark a mail message as read or unread",
        discussion: """
            Marks the specified message as read or unread in Mail.app.

            Use --read to mark the message as read.
            Use --unread to mark the message as unread.
            Use --dry-run to preview the action without making changes.
            """
    )

    @Option(name: .long, help: "Message ID to mark (required)")
    var id: String

    @Flag(name: .long, help: "Mark the message as read")
    var read: Bool = false

    @Flag(name: .long, help: "Mark the message as unread")
    var unread: Bool = false

    @Flag(name: .long, help: "Preview the action without making changes")
    var dryRun: Bool = false

    func validate() throws {
        // Exactly one of --read or --unread must be provided
        if read == unread {
            throw MailActionError.invalidMarkOperation
        }
    }

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        // Resolve message to Mail.app reference
        let resolver = MessageResolver(database: mailDatabase)
        let resolved = try resolver.resolve(id: id)

        let markAsRead = read
        let action = markAsRead ? "mark as read" : "mark as unread"

        if dryRun {
            print("[DRY RUN] Would \(action) message:")
            print("  ID: \(resolved.swiftEAId)")
            print("  Message-ID: \(resolved.messageId)")
            print("  Subject: \(resolved.message.subject)")
            print("  Current status: \(resolved.message.isRead ? "read" : "unread")")
            return
        }

        // Execute mark via AppleScript
        let script = MailActionScripts.setReadStatus(byMessageId: resolved.messageId, read: markAsRead)

        let appleScriptService = AppleScriptService.shared
        let result = try appleScriptService.executeMailScript(script)

        if result.success {
            print("Marked message as \(markAsRead ? "read" : "unread"): \(resolved.swiftEAId)")
            print("  Subject: \(resolved.message.subject)")
        }
    }
}

struct MailReplyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reply",
        abstract: "Create a reply to a mail message",
        discussion: """
            Creates a reply draft for the specified message in Mail.app.

            By default, opens the reply in Mail.app for editing.
            Use --send to send the reply immediately (requires --body).
            Use --dry-run to preview the action without making changes.

            The reply will be addressed to the original sender and include
            the original message as quoted text.
            """
    )

    @Option(name: .long, help: "Message ID to reply to (required)")
    var id: String

    @Option(name: .long, help: "Reply body text (required if using --send)")
    var body: String?

    @Flag(name: .long, help: "Reply to all recipients")
    var all: Bool = false

    @Flag(name: .long, help: "Send the reply immediately instead of opening a draft")
    var send: Bool = false

    @Flag(name: .long, help: "Preview the action without making changes")
    var dryRun: Bool = false

    func validate() throws {
        // If --send is specified, --body is required
        if send && body == nil {
            throw ValidationError("--body is required when using --send")
        }
    }

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        // Resolve message to Mail.app reference
        let resolver = MessageResolver(database: mailDatabase)
        let resolved = try resolver.resolve(id: id)

        let replyType = all ? "reply all" : "reply"

        if dryRun {
            print("[DRY RUN] Would create \(replyType) to message:")
            print("  ID: \(resolved.swiftEAId)")
            print("  Message-ID: \(resolved.messageId)")
            print("  Subject: \(resolved.message.subject)")
            print("  Original sender: \(resolved.message.senderEmail ?? "Unknown")")
            if let replyBody = body {
                let preview = replyBody.prefix(100)
                print("  Body: \(preview)\(replyBody.count > 100 ? "..." : "")")
            }
            print("  Mode: \(send ? "Send immediately" : "Open draft in Mail.app")")
            return
        }

        // Execute reply via AppleScript
        let script = MailActionScripts.createReply(
            byMessageId: resolved.messageId,
            replyToAll: all,
            body: body,
            send: send
        )

        let appleScriptService = AppleScriptService.shared
        let result = try appleScriptService.executeMailScript(script)

        if result.success {
            if send {
                print("Sent \(replyType) to: \(resolved.message.senderEmail ?? "Unknown")")
            } else {
                print("Created \(replyType) draft in Mail.app")
            }
            print("  Original subject: \(resolved.message.subject)")
        }
    }
}

struct MailComposeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compose",
        abstract: "Compose a new mail message",
        discussion: """
            Creates a new email draft in Mail.app.

            By default, opens the compose window in Mail.app for editing.
            Use --send to send the message immediately.
            Use --dry-run to preview the action without making changes.
            """
    )

    @Option(name: .long, help: "Recipient email address (required)")
    var to: String

    @Option(name: .long, help: "Email subject (required)")
    var subject: String

    @Option(name: .long, help: "Email body text")
    var body: String?

    @Option(name: .long, help: "CC recipients (comma-separated)")
    var cc: String?

    @Option(name: .long, help: "BCC recipients (comma-separated)")
    var bcc: String?

    @Flag(name: .long, help: "Send the message immediately instead of opening a draft")
    var send: Bool = false

    @Flag(name: .long, help: "Preview the action without making changes")
    var dryRun: Bool = false

    func validate() throws {
        // --to requires a non-empty email address
        if to.trimmingCharacters(in: .whitespaces).isEmpty {
            throw MailValidationError.emptyRecipient
        }
    }

    func run() throws {
        _ = try VaultContext.require()

        if dryRun {
            print("[DRY RUN] Would compose new message:")
            print("  To: \(to)")
            print("  Subject: \(subject)")
            if let ccRecipients = cc {
                print("  CC: \(ccRecipients)")
            }
            if let bccRecipients = bcc {
                print("  BCC: \(bccRecipients)")
            }
            if let messageBody = body {
                let preview = messageBody.prefix(100)
                print("  Body: \(preview)\(messageBody.count > 100 ? "..." : "")")
            }
            print("  Mode: \(send ? "Send immediately" : "Open draft in Mail.app")")
            return
        }

        // Execute compose via AppleScript
        let script = MailActionScripts.compose(
            to: to,
            subject: subject,
            body: body,
            cc: cc,
            bcc: bcc,
            send: send
        )

        let appleScriptService = AppleScriptService.shared
        let result = try appleScriptService.executeMailScript(script)

        if result.success {
            if send {
                print("Sent message to: \(to)")
            } else {
                print("Created draft in Mail.app")
            }
            print("  Subject: \(subject)")
        }
    }
}
