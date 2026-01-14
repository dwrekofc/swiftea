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

public struct Mail: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "mail",
        abstract: "Mail operations (sync, search, show, export, actions)",
        discussion: """
            SwiftEA mail commands interact with Apple Mail.app to sync, search,
            and perform actions on your email.

            AUTOMATION PERMISSION
            Action commands (archive, delete, move, flag, mark, reply, compose)
            require macOS Automation permission for Mail.app. On first run, macOS
            will prompt you to grant permission. To grant permission manually:

              1. Open System Settings > Privacy & Security > Automation
              2. Find SwiftEA (or Terminal if running from terminal)
              3. Enable the toggle for Mail.app

            SAFETY FLAGS
            Destructive actions (archive, delete, move) require explicit confirmation:

              --dry-run    Preview what would happen without making changes
              --yes        Confirm the action and execute it

            Running a destructive action without --yes or --dry-run will show an
            error explaining the requirement.

            EXAMPLES
              # Sync mail from Apple Mail
              swiftea mail sync

              # Search for emails from a specific sender
              swiftea mail search "from:alice@example.com"

              # Preview archiving a message (no changes made)
              swiftea mail archive --id mail-abc123 --dry-run

              # Archive a message (requires confirmation)
              swiftea mail archive --id mail-abc123 --yes

              # Flag a message
              swiftea mail flag --id mail-abc123 --set

              # Compose a new email draft
              swiftea mail compose --to bob@example.com --subject "Hello"
            """,
        subcommands: [
            MailSyncCommand.self,
            MailSearchCommand.self,
            MailShowCommand.self,
            MailExportCommand.self,
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
        abstract: "Sync mail data from Apple Mail"
    )

    @Flag(name: .long, help: "Install and start watch daemon for continuous sync")
    var watch: Bool = false

    @Flag(name: .long, help: "Stop the watch daemon")
    var stop: Bool = false

    @Flag(name: .long, help: "Show sync status and watch daemon state")
    var status: Bool = false

    @Flag(name: .long, help: "Only sync messages changed since last sync")
    var incremental: Bool = false

    @Flag(name: .long, help: "Show detailed progress")
    var verbose: Bool = false

    @Flag(name: .long, help: "Run as persistent daemon with sleep/wake detection (internal use)")
    var daemon: Bool = false

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
            try runPersistentDaemon(mailDatabase: mailDatabase)
            return
        }

        // Create sync engine
        let sync = MailSync(mailDatabase: mailDatabase)

        log("Syncing mail from Apple Mail...")

        do {
            let result = try sync.sync(incremental: incremental)

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
        } catch let error as MailSyncError {
            logError("Sync failed: \(error.localizedDescription)")
            throw ExitCode.failure
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
            print("Last Error: \(error)")
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
    private static let syncIntervalSeconds = 300 // 5 minutes

    private func getLaunchAgentPath() -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDir)/Library/LaunchAgents/\(Self.launchAgentLabel).plist"
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

        // Check if we have any messages - if not, do a full sync; otherwise incremental
        let existingMessages = try mailDatabase.getAllMessages(limit: 1)
        let isFirstSync = existingMessages.isEmpty

        let sync = MailSync(mailDatabase: mailDatabase)

        do {
            let result = try sync.sync(incremental: !isFirstSync)
            print("Initial sync complete:")
            print("  Messages: +\(result.messagesAdded) ~\(result.messagesUpdated)")
            print("  Duration: \(String(format: "%.2f", result.duration))s")
            if !result.errors.isEmpty {
                print("  Warnings: \(result.errors.count)")
            }
        } catch {
            print("Warning: Initial sync failed: \(error.localizedDescription)")
            print("The daemon will retry on its first run.")
        }

        mailDatabase.close()

        // Generate plist content
        // Uses --daemon mode for a persistent process with sleep/wake detection.
        // KeepAlive ensures the daemon is restarted if it exits.
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
            print("Failed to load LaunchAgent: \(errorOutput)")
            throw ExitCode.failure
        }

        print("Watch daemon installed and started")
        print("  Mode: Persistent daemon with sleep/wake detection")
        print("  Syncing every \(Self.syncIntervalSeconds / 60) minutes + on wake")
        print("  Logs: \(logDir)/mail-sync.log")
        print("")
        print("Use 'swiftea mail sync --status' to check status")
        print("Use 'swiftea mail sync --stop' to stop the daemon")
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
                print("Warning: \(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
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
    private func runPersistentDaemon(mailDatabase: MailDatabase) throws {
        log("Starting persistent mail sync daemon (pid=\(ProcessInfo.processInfo.processIdentifier))")

        // Run initial incremental sync on startup
        log("Running initial sync...")
        performDaemonSync(mailDatabase: mailDatabase)

        // Create a daemon controller to handle sleep/wake events
        let controller = MailSyncDaemonController(mailDatabase: mailDatabase, logger: log)

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
    private let logger: (String) -> Void
    private var isSyncing = false
    private let syncQueue = DispatchQueue(label: "com.swiftea.mail.sync.daemon")
    private var syncTimer: Timer?

    /// Interval between scheduled syncs (5 minutes)
    private static let syncIntervalSeconds: TimeInterval = 300

    /// Minimum interval between syncs to prevent rapid-fire syncing
    private static let minSyncIntervalSeconds: TimeInterval = 30

    /// Track last sync time to debounce wake events
    private var lastSyncTime: Date?

    init(mailDatabase: MailDatabase, logger: @escaping (String) -> Void) {
        self.mailDatabase = mailDatabase
        self.logger = logger
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
        syncTimer = Timer.scheduledTimer(withTimeInterval: Self.syncIntervalSeconds, repeats: true) { [weak self] _ in
            self?.triggerSync(reason: "scheduled")
        }

        logger("Scheduled sync timer (every \(Int(Self.syncIntervalSeconds))s)")
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
                let result = try sync.sync(incremental: true)

                logger("Sync complete: +\(result.messagesAdded) ~\(result.messagesUpdated) (\(String(format: "%.2f", result.duration))s)")

                if !result.errors.isEmpty {
                    logger("  \(result.errors.count) warning(s)")
                }
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
}

/// Perform a sync in daemon mode with retry logic.
/// This is a standalone function for use during daemon startup.
private func performDaemonSync(mailDatabase: MailDatabase) {
    let maxRetryAttempts = 5
    let baseRetryDelay: TimeInterval = 2.0
    let maxRetryDelay: TimeInterval = 60.0

    var attempt = 0

    while attempt < maxRetryAttempts {
        do {
            let sync = MailSync(mailDatabase: mailDatabase)
            let result = try sync.sync(incremental: true)

            let timestamp = ISO8601DateFormatter().string(from: Date())
            fputs("[\(timestamp)] Sync complete: +\(result.messagesAdded) ~\(result.messagesUpdated) (\(String(format: "%.2f", result.duration))s)\n", stdout)
            fflush(stdout)
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

            EXAMPLES:
              swiftea mail search "from:alice@example.com project"
              swiftea mail search "is:unread is:flagged"
              swiftea mail search "after:2024-01-01 before:2024-02-01"
              swiftea mail search "mailbox:INBOX from:support"

            Use quotes around values with spaces: from:"Alice Smith"
            """
    )

    @Argument(help: "Search query with optional structured filters")
    var query: String

    @Option(name: .long, help: "Maximum results to return")
    var limit: Int = 20

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let vault = try VaultContext.require()

        // Open mail database
        let mailDbPath = (vault.dataFolderPath as NSString).appendingPathComponent("mail.db")
        let mailDatabase = MailDatabase(databasePath: mailDbPath)
        try mailDatabase.initialize()
        defer { mailDatabase.close() }

        // Parse the query for structured filters
        let filter = mailDatabase.parseQuery(query)

        // Use structured search if we have filters, otherwise fall back to basic FTS
        let results: [MailMessage]
        if filter.hasFilters || filter.hasFreeText {
            results = try mailDatabase.searchMessagesWithFilters(filter, limit: limit)
        } else {
            // Empty query - show recent messages
            results = try mailDatabase.getAllMessages(limit: limit)
        }

        if results.isEmpty {
            print("No messages found for: \(query)")
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
            print("Message not found: \(id)")
            throw ExitCode.failure
        }

        // Handle --raw flag: read original .emlx file
        if raw {
            guard let emlxPath = message.emlxPath else {
                print("No .emlx path available for this message")
                throw ExitCode.failure
            }

            // Check for EWS (Exchange) mailbox paths which contain "ews:" prefix
            // These are cloud-based mailboxes that don't have local .emlx files
            if emlxPath.contains("ews:") || emlxPath.contains("/ews:/") {
                print("Raw .emlx viewing is not available for Exchange (EWS) mailboxes.")
                print("Exchange messages are stored on the server, not as local .emlx files.")
                print("Use 'mail show \(id)' without --raw to view the message content.")
                throw ExitCode.failure
            }

            guard let content = try? String(contentsOfFile: emlxPath, encoding: .utf8) else {
                print("Could not read .emlx file: \(emlxPath)")
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

struct MailExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export mail messages to markdown or JSON",
        discussion: """
            Export mail messages in markdown or JSON format.

            Use --include-attachments to also extract and save attachment files.
            Attachments are saved in an 'attachments/<message-id>/' subdirectory.
            """
    )

    @Option(name: .long, help: "Export format (markdown, json)")
    var format: String = "markdown"

    @Option(name: .long, help: "Message ID to export (or 'all' for all synced messages)")
    var id: String = "all"

    @Option(name: .shortAndLong, help: "Output directory (default: vault exports folder)")
    var output: String?

    @Option(name: .long, help: "Search query to filter messages for export")
    var query: String?

    @Option(name: .long, help: "Maximum messages to export (default: 100)")
    var limit: Int = 100

    @Flag(name: .long, help: "Extract and save attachment files")
    var includeAttachments: Bool = false

    func run() throws {
        let vault = try VaultContext.require()

        // Determine output directory
        let outputDir: String
        if let specifiedOutput = output {
            outputDir = specifiedOutput
        } else {
            outputDir = (vault.rootPath as NSString).appendingPathComponent("exports/mail")
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

        // Get messages to export
        var messages: [MailMessage] = []

        if id != "all" {
            // Export single message
            if let message = try mailDatabase.getMessage(id: id) {
                messages = [message]
            } else {
                print("Message not found: \(id)")
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
            print("No messages to export")
            return
        }

        print("Exporting \(messages.count) message(s) to \(outputDir)...")

        var exportedCount = 0
        var attachmentCount = 0
        let emlxParser = EmlxParser()

        for message in messages {
            let filename = generateFilename(for: message, format: format)
            let filePath = (outputDir as NSString).appendingPathComponent(filename)

            let content: String
            switch format.lowercased() {
            case "json":
                content = formatAsJson(message)
            case "markdown", "md":
                content = formatAsMarkdown(message)
            default:
                print("Unknown format: \(format). Use 'markdown' or 'json'.")
                throw ExitCode.failure
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
                    print("  Warning: Could not extract attachments from \(message.id): \(error.localizedDescription)")
                }
            }
        }

        print("Exported \(exportedCount) message(s) to \(outputDir)")
        if attachmentCount > 0 {
            print("Extracted \(attachmentCount) attachment(s)")
        }
    }

    private func generateFilename(for message: MailMessage, format: String) -> String {
        // Flat filename using message ID for uniqueness and idempotent overwrites
        let ext = format.lowercased() == "json" ? "json" : "md"
        return "\(message.id).\(ext)"
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

    private func formatAsJson(_ message: MailMessage) -> String {
        let output: [String: Any] = [
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

        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return "{}"
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

        // Execute archive via AppleScript
        // Archive in Mail.app moves to the account's Archive mailbox
        let script = """
            set targetMessages to (every message whose message id is "\(escapeAppleScript(resolved.messageId))")
            if (count of targetMessages) = 0 then
                error "Message not found" number -1728
            end if
            set theMessage to item 1 of targetMessages
            set theAccount to account of mailbox of theMessage
            set archiveMailbox to mailbox "Archive" of theAccount
            move theMessage to archiveMailbox
            return "archived"
            """

        let appleScriptService = AppleScriptService.shared
        let result = try appleScriptService.executeMailScript(script)

        if result.success {
            print("Archived message: \(resolved.swiftEAId)")
            print("  Subject: \(resolved.message.subject)")
        }
    }

    private func escapeAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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

        // Execute delete via AppleScript
        let script = MailActionScripts.deleteMessage(byMessageId: resolved.messageId)

        let appleScriptService = AppleScriptService.shared
        let result = try appleScriptService.executeMailScript(script)

        if result.success {
            print("Deleted message: \(resolved.swiftEAId)")
            print("  Subject: \(resolved.message.subject)")
        }
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
