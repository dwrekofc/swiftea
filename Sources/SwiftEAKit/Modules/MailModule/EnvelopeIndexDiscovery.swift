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

                SwiftEA requires Full Disk Access to read Apple Mail data.

                To grant access:
                1. Open System Settings > Privacy & Security > Full Disk Access
                2. Click the + button
                3. Add Terminal (or the app running SwiftEA)
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
    ///   - mailboxPath: The mailbox path within the Mail directory
    ///   - mailBasePath: The base Mail directory path
    /// - Returns: The full path to the .emlx file
    public func emlxPath(forMessageId messageId: Int, mailboxPath: String, mailBasePath: String) -> String {
        // Apple Mail stores .emlx files in the Messages subdirectory
        // Format: mailbox/Messages/<rowid>.emlx
        let messagesDir = (mailboxPath as NSString).appendingPathComponent("Messages")
        return (messagesDir as NSString).appendingPathComponent("\(messageId).emlx")
    }
}
