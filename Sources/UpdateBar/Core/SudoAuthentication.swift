import Foundation

/// Whether `sudo` on this machine authenticates with Touch ID.
///
/// Worth knowing because it makes the stored admin password pointless. Touch ID
/// needs no support from UpdateBar — the no-password path already emits a plain
/// `sudo`, and `sudo` is what raises the prompt — so the only thing to change is
/// that the app should stop *offering* to store a credential that buys nothing
/// and leaves a readable copy of the login password in the Keychain.
enum SudoAuthentication {
    /// Apple's `/etc/pam.d/sudo` includes this file first, specifically so the
    /// setting survives a system update. World-readable, so no privilege is
    /// needed to see whether it is on.
    static let localConfigurationPath = "/etc/pam.d/sudo_local"

    static var isTouchIDEnabled: Bool { isEnabled(at: localConfigurationPath) }

    static func isEnabled(at path: String) -> Bool {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            // No file is the ordinary case: macOS ships only the template, and
            // nothing has been configured.
            return false
        }
        return enablesTouchID(pamConfiguration: contents)
    }

    /// The rule itself, over text.
    ///
    /// A live `auth` line naming `pam_tid.so`. The distinctions all come from
    /// what the file actually looks like in the wild: Apple ships the line
    /// commented out, people add a `pam_reattach` line above it for tmux, and a
    /// module in a `session` stack is not what authenticates.
    static func enablesTouchID(pamConfiguration: String) -> Bool {
        pamConfiguration.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { return false }
            // A trailing comment does not disable the directive before it.
            let directive = trimmed.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
            // PAM separates fields by any whitespace, and snippets are pasted
            // with tabs as often as spaces.
            let fields = directive.split(whereSeparator: \.isWhitespace)
            guard fields.first == "auth" else { return false }
            return fields.contains { $0.hasSuffix("pam_tid.so") }
        }
    }
}
