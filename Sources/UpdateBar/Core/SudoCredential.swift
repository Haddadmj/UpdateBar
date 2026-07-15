import Foundation
import Security

/// Stores the user's admin (sudo) password in the login Keychain so admin
/// upgrades (macOS `softwareupdate`, `mas`, `gem`) can run without an
/// interactive Terminal prompt.
///
/// The plaintext never touches disk: it lives encrypted in the Keychain, and
/// the generated upgrade script retrieves it at runtime with the `security`
/// CLI (see `shellRetrieval`), piping it straight into `sudo -S`.
enum SudoCredential {
    /// Keychain generic-password service; also used by the `security` CLI lookup.
    static let service = "updatebar-sudo"
    /// Account is the current user, matching what `sudo` authenticates.
    static var account: String { NSUserName() }

    /// True when a password is currently saved.
    static var hasPassword: Bool { retrieve() != nil }

    /// Save (or replace) the admin password. Empty string clears it.
    @discardableResult
    static func store(_ password: String) -> Bool {
        guard !password.isEmpty else { return clear() }
        clear() // ensure a clean insert (avoids duplicate-item errors)
        guard let data = password.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Available whenever the user is logged in; kept on this device only.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Fetch the stored password, if any.
    static func retrieve() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    /// Remove the stored password.
    @discardableResult
    static func clear() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// A shell fragment that prints the stored password to stdout, for use in a
    /// `sudo -S` here-string. Reads from the Keychain at runtime — no plaintext
    /// is written into the upgrade script.
    static var shellRetrieval: String {
        "security find-generic-password -s \(service) -a \"$USER\" -w"
    }
}
