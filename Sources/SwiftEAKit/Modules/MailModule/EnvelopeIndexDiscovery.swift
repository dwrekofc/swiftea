// EnvelopeIndexDiscovery - Auto-detect Apple Mail database paths

import Foundation

/// Errors that can occur during envelope index discovery
public enum EnvelopeDiscoveryError: Error, LocalizedError {
    case mailDirectoryNotFound
    case noVersionDirectory
    case envelopeIndexNotFound
    case permissionDenied(path: String)

    public var errorDescription: String? {
        switch self {
        case .mailDirectoryNotFound:
            return "Apple Mail directory not found at ~/Library/Mail"
        case .noVersionDirectory:
            return "No V[x] version directory found in ~/Library/Mail"
        case .envelopeIndexNotFound:
            return "Envelope Index database not found"
        case .permissionDenied(let path):
            return """
                Permission denied accessing: \(path)

                swea requires Full Disk Access to read Apple Mail data.

                To grant access:
                1. Open System Settings > Privacy & Security > Full Disk Access
                2. Click the + button
                3. Add Terminal (or the app running swea)
                4. Restart the terminal/app
                """
        }
    }
}

/// Result of envelope index discovery
public struct EnvelopeIndexInfo: Sendable {
    /// Path to the Envelope Index SQLite database
    public let envelopeIndexPath: String
    /// The version directory (e.g., "V10")
    public let versionDirectory: String
    /// Base Mail directory path
    public let mailBasePath: String
    /// Path to the MailData directory
    public let mailDataPath: String

    public init(envelopeIndexPath: String, versionDirectory: String, mailBasePath: String, mailDataPath: String) {
        self.envelopeIndexPath = envelopeIndexPath
        self.versionDirectory = versionDirectory
        self.mailBasePath = mailBasePath
        self.mailDataPath = mailDataPath
    }
}

/// Discovers and validates Apple Mail database paths
/// Note: FileManager.default is thread-safe for the operations used here
public final class EnvelopeIndexDiscovery: Sendable {
    private nonisolated(unsafe) let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Auto-detect the latest Apple Mail Envelope Index path
    /// - Parameter customPath: Optional custom path to use instead of auto-detection
    /// - Returns: Information about the discovered envelope index
    public func discover(customPath: String? = nil) throws -> EnvelopeIndexInfo {
        // If custom path provided, validate it
        if let custom = customPath {
            let expandedPath = (custom as NSString).expandingTildeInPath
            guard fileManager.fileExists(atPath: expandedPath) else {
                throw EnvelopeDiscoveryError.envelopeIndexNotFound
            }
            guard fileManager.isReadableFile(atPath: expandedPath) else {
                throw EnvelopeDiscoveryError.permissionDenied(path: expandedPath)
            }

            // Extract version directory from path
            let components = expandedPath.components(separatedBy: "/")
            var versionDir = "V10"
            for component in components {
                if component.hasPrefix("V") && component.dropFirst().allSatisfy({ $0.isNumber }) {
                    versionDir = component
                    break
                }
            }

            let mailBasePath = (expandedPath as NSString).deletingLastPathComponent
            let mailDataPath = (mailBasePath as NSString).deletingLastPathComponent

            return EnvelopeIndexInfo(
                envelopeIndexPath: expandedPath,
                versionDirectory: versionDir,
                mailBasePath: ((mailDataPath as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent,
                mailDataPath: mailDataPath
            )
        }

        // Auto-detect: find ~/Library/Mail
        let homeDir = fileManager.homeDirectoryForCurrentUser.path
        let mailBasePath = (homeDir as NSString).appendingPathComponent("Library/Mail")

        guard fileManager.fileExists(atPath: mailBasePath) else {
            throw EnvelopeDiscoveryError.mailDirectoryNotFound
        }

        guard fileManager.isReadableFile(atPath: mailBasePath) else {
            throw EnvelopeDiscoveryError.permissionDenied(path: mailBasePath)
        }

        // Find the latest V[x] directory
        let versionDir = try findLatestVersionDirectory(in: mailBasePath)
        let versionPath = (mailBasePath as NSString).appendingPathComponent(versionDir)
        let mailDataPath = (versionPath as NSString).appendingPathComponent("MailData")
        let envelopeIndexPath = (mailDataPath as NSString).appendingPathComponent("Envelope Index")

        // Validate envelope index exists
        guard fileManager.fileExists(atPath: envelopeIndexPath) else {
            throw EnvelopeDiscoveryError.envelopeIndexNotFound
        }

        guard fileManager.isReadableFile(atPath: envelopeIndexPath) else {
            throw EnvelopeDiscoveryError.permissionDenied(path: envelopeIndexPath)
        }

        return EnvelopeIndexInfo(
            envelopeIndexPath: envelopeIndexPath,
            versionDirectory: versionDir,
            mailBasePath: mailBasePath,
            mailDataPath: mailDataPath
        )
    }

    /// Find the latest V[x] version directory in the Mail folder
    private func findLatestVersionDirectory(in mailPath: String) throws -> String {
        let contents: [String]
        do {
            contents = try fileManager.contentsOfDirectory(atPath: mailPath)
        } catch {
            throw EnvelopeDiscoveryError.permissionDenied(path: mailPath)
        }

        // Filter to V[x] directories and sort by version number descending
        let versionDirs = contents
            .filter { $0.hasPrefix("V") && $0.dropFirst().allSatisfy { $0.isNumber } }
            .sorted { dir1, dir2 in
                let v1 = Int(dir1.dropFirst()) ?? 0
                let v2 = Int(dir2.dropFirst()) ?? 0
                return v1 > v2
            }

        guard let latestVersion = versionDirs.first else {
            throw EnvelopeDiscoveryError.noVersionDirectory
        }

        return latestVersion
    }

    /// Check if Full Disk Access is likely available
    public func checkPermissions() -> Bool {
        let homeDir = fileManager.homeDirectoryForCurrentUser.path
        let mailBasePath = (homeDir as NSString).appendingPathComponent("Library/Mail")

        // Try to read the Mail directory
        guard fileManager.isReadableFile(atPath: mailBasePath) else {
            return false
        }

        // Try to list contents
        do {
            _ = try fileManager.contentsOfDirectory(atPath: mailBasePath)
            return true
        } catch {
            return false
        }
    }

    /// Get the .emlx file path for a message
    /// - Parameters:
    ///   - messageId: The message row ID from Apple Mail
    ///   - mailboxPath: The mailbox path within the Mail directory (e.g., /path/to/Inbox.mbox)
    ///   - mailBasePath: The base Mail directory path
    /// - Returns: The full path to the .emlx file, or nil if not found
    public func emlxPath(forMessageId messageId: Int, mailboxPath: String, mailBasePath: String) -> String? {
        // Apple Mail V10+ uses a complex path structure:
        // {mailbox}.mbox/{UUID}/Data/[partitions/]Messages/{rowid}.emlx
        //
        // Partition schemes:
        // - id < 1000: Data/Messages/{id}.emlx (no partition)
        // - 1000 <= id < 10000: Data/{p1}/Messages/{id}.emlx (single partition)
        // - id >= 10000: Data/{p1}/{p2}/Messages/{id}.emlx (double partition)
        // where p1 = (id / 1000) % 10, p2 = id / 10000

        // First, find the UUID subdirectory in the mailbox
        guard let uuid = findUuidSubdirectory(in: mailboxPath) else {
            // Fallback to legacy path structure
            let messagesDir = (mailboxPath as NSString).appendingPathComponent("Messages")
            return checkEmlxVariants(in: messagesDir, messageId: messageId)
        }

        let dataDir = (mailboxPath as NSString)
            .appendingPathComponent(uuid)
            .appending("/Data")

        // Calculate partition directories
        let p1 = (messageId / 1000) % 10
        let p2 = messageId / 10000

        // Build possible paths in order of specificity
        var pathsToTry: [String] = []

        // Double partition path (for id >= 10000)
        if p2 > 0 {
            pathsToTry.append("\(dataDir)/\(p1)/\(p2)/Messages")
        }

        // Single partition path (for id >= 1000)
        if p1 > 0 {
            pathsToTry.append("\(dataDir)/\(p1)/Messages")
        }

        // Non-partitioned path (for id < 1000, or as fallback)
        pathsToTry.append("\(dataDir)/Messages")

        // Try each path with both .emlx and .partial.emlx variants
        for messagesDir in pathsToTry {
            if let found = checkEmlxVariants(in: messagesDir, messageId: messageId) {
                return found
            }
        }

        return nil
    }

    /// Check for .emlx and .partial.emlx variants in a directory
    private func checkEmlxVariants(in messagesDir: String, messageId: Int) -> String? {
        let emlxPath = "\(messagesDir)/\(messageId).emlx"
        if fileManager.fileExists(atPath: emlxPath) {
            return emlxPath
        }

        let partialPath = "\(messagesDir)/\(messageId).partial.emlx"
        if fileManager.fileExists(atPath: partialPath) {
            return partialPath
        }

        return nil
    }

    /// Find the UUID subdirectory in a mailbox folder
    /// Apple Mail V10+ stores messages in a UUID-named subdirectory
    private func findUuidSubdirectory(in mailboxPath: String) -> String? {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: mailboxPath) else {
            return nil
        }

        // UUID pattern: 8 chars - 4 chars - 4 chars - 4 chars - 12 chars
        let uuidPattern = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/

        for item in contents {
            if item.uppercased().contains(uuidPattern) {
                let itemPath = (mailboxPath as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: itemPath, isDirectory: &isDir), isDir.boolValue {
                    return item
                }
            }
        }

        return nil
    }
}
