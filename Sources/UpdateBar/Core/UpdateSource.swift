import Foundation

/// A pluggable update source (Homebrew, Mac App Store, npm, …).
///
/// Adding a new package manager is just conforming a new type to this protocol and
/// registering it in `SourceRegistry`.
protocol UpdateSource: Sendable {
    /// Stable machine id, e.g. "homebrew".
    var id: String { get }
    /// Human-facing name, e.g. "Homebrew".
    var displayName: String { get }
    /// SF Symbol used in the menu.
    var iconSystemName: String { get }

    /// Whether the underlying CLI exists on this machine.
    func isAvailable() async -> Bool

    /// Non-nil when the source is present but shouldn't be managed — the string explains
    /// why (shown as a dimmed, non-actionable row). Default: manageable (nil).
    func managementNote() async -> String?

    /// Whether upgrades need admin rights. Such upgrades are run in Terminal.app so the
    /// user can authenticate, rather than in-process (which has no TTY for a password).
    ///
    /// Asked rather than declared, and resolved once at bootstrap like
    /// `managementNote()`, because for some sources the answer depends on where
    /// the tool's files actually live rather than on which tool it is.
    func requiresAdmin() async -> Bool

    /// Read-only check for outdated packages.
    func checkOutdated() async throws -> [OutdatedItem]

    /// The shell command that upgrades `items` (empty = everything). No `sudo` prefix —
    /// the coordinator adds it for admin-gated sources.
    func upgradeCommand(_ items: [OutdatedItem]) -> String
}

extension UpdateSource {
    func requiresAdmin() async -> Bool { false }

    func managementNote() async -> String? { nil }

    /// Default availability probe: `command -v <tool>` succeeds.
    func toolExists(_ tool: String, runner: any CommandRunner) async -> Bool {
        let result = try? await runner.runShell("command -v \(tool)", timeout: 20)
        return result?.succeeded ?? false
    }
}

/// Extracts the first balanced JSON value from possibly-noisy shell output.
/// Interactive shells (`-ilc`) may emit banner text before a command's JSON; this
/// trims to the outermost `{...}` or `[...]` so decoding stays robust.
enum JSONExtractor {
    static func extract(_ raw: String) -> String? {
        let opens: [Character] = ["{", "["]
        let closes: [Character: Character] = ["{": "}", "[": "]"]
        guard let startIdx = raw.firstIndex(where: { opens.contains($0) }) else { return nil }
        let opener = raw[startIdx]
        guard let closer = closes[opener], let endIdx = raw.lastIndex(of: closer),
              startIdx < endIdx else { return nil }
        return String(raw[startIdx...endIdx])
    }
}

/// Shared error type for sources.
enum SourceError: Error, LocalizedError {
    case parse(String, String)

    var errorDescription: String? {
        switch self {
        case let .parse(name, detail):
            return "\(name): couldn't read updates — \(detail.prefix(200))"
        }
    }
}
