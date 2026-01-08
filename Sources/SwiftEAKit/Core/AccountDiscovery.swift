// AccountDiscovery - Reads available Mail and Calendar accounts from macOS

import Foundation

/// Represents a discovered macOS account
public struct DiscoveredAccount: Codable, Hashable {
    public let id: String
    public let name: String
    public let email: String?
    public let type: AccountType

    public init(id: String, name: String, email: String?, type: AccountType) {
        self.id = id
        self.name = name
        self.email = email
        self.type = type
    }
}

/// Errors that can occur during account discovery
public enum AccountDiscoveryError: Error, LocalizedError {
    case scriptExecutionFailed(underlying: Error)
    case noAccountsFound
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .scriptExecutionFailed(let underlying):
            return "Failed to discover accounts: \(underlying.localizedDescription)"
        case .noAccountsFound:
            return "No Mail or Calendar accounts found on this system"
        case .parseError(let message):
            return "Failed to parse account data: \(message)"
        }
    }
}

/// Discovers Mail and Calendar accounts on macOS using AppleScript
public final class AccountDiscovery {
    public init() {}

    /// Discover all available Mail accounts
    public func discoverMailAccounts() throws -> [DiscoveredAccount] {
        let script = """
        tell application "Mail"
            set accountList to {}
            repeat with acct in accounts
                set acctId to id of acct
                set acctName to name of acct
                set acctEmail to email addresses of acct
                if (count of acctEmail) > 0 then
                    set firstEmail to item 1 of acctEmail
                else
                    set firstEmail to ""
                end if
                set end of accountList to acctId & "|||" & acctName & "|||" & firstEmail
            end repeat
            return accountList
        end tell
        """

        let result = try executeAppleScript(script)
        return parseAccountList(result, type: .mail)
    }

    /// Discover all available Calendar accounts
    public func discoverCalendarAccounts() throws -> [DiscoveredAccount] {
        let script = """
        tell application "Calendar"
            set accountList to {}
            repeat with acct in accounts
                set acctId to uid of acct
                set acctName to name of acct
                set end of accountList to acctId & "|||" & acctName & "|||"
            end repeat
            return accountList
        end tell
        """

        let result = try executeAppleScript(script)
        return parseAccountList(result, type: .calendar)
    }

    /// Discover all available accounts (Mail + Calendar)
    public func discoverAllAccounts() throws -> [DiscoveredAccount] {
        var accounts: [DiscoveredAccount] = []

        // Try Mail accounts (may fail if Mail is not configured)
        do {
            accounts.append(contentsOf: try discoverMailAccounts())
        } catch {
            // Ignore - Mail may not be configured
        }

        // Try Calendar accounts (may fail if Calendar is not configured)
        do {
            accounts.append(contentsOf: try discoverCalendarAccounts())
        } catch {
            // Ignore - Calendar may not be configured
        }

        return accounts
    }

    /// Execute an AppleScript and return the result
    private func executeAppleScript(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw AccountDiscoveryError.scriptExecutionFailed(
                underlying: NSError(domain: "AccountDiscovery", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create AppleScript"
                ])
            )
        }

        let result = script.executeAndReturnError(&error)

        if let error = error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw AccountDiscoveryError.scriptExecutionFailed(
                underlying: NSError(domain: "AccountDiscovery", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: message
                ])
            )
        }

        return result.stringValue ?? ""
    }

    /// Parse the AppleScript result into DiscoveredAccount objects
    private func parseAccountList(_ result: String, type: AccountType) -> [DiscoveredAccount] {
        // AppleScript returns comma-separated list like: "id|||name|||email, id|||name|||email"
        let items = result.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        return items.compactMap { item in
            let parts = item.split(separator: "|||", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { return nil }

            let id = parts[0].trimmingCharacters(in: .whitespaces)
            let name = parts[1].trimmingCharacters(in: .whitespaces)
            let email = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : nil

            guard !id.isEmpty, !name.isEmpty else { return nil }

            return DiscoveredAccount(
                id: id,
                name: name,
                email: email?.isEmpty == true ? nil : email,
                type: type
            )
        }
    }
}
