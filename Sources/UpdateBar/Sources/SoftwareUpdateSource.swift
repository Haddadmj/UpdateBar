import Foundation

/// macOS system + delivered updates via `softwareupdate --list`.
/// Output contains blocks like:
///   * Label: macOS Sequoia 15.6-24G...
///      Title: macOS Sequoia, Version: 15.6, Size: 700000KiB, Recommended: YES, Action: restart,
struct SoftwareUpdateSource: UpdateSource {
    let id = "softwareupdate"
    let displayName = "macOS Updates"
    let iconSystemName = "apple.logo"
    func requiresAdmin() async -> Bool { true }
    let runner: any CommandRunner

    func isAvailable() async -> Bool { true } // always present on macOS

    func checkOutdated() async throws -> [OutdatedItem] {
        // `--list` scans network; use it (no --no-scan) for accurate results.
        let result = try await runner.runShell("softwareupdate --list", timeout: 180)
        // softwareupdate prints to stderr; combine both streams for parsing.
        return Self.parse(result.stdout + "\n" + result.stderr)
    }

    static func parse(_ output: String) -> [OutdatedItem] {
        var items: [OutdatedItem] = []
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var pendingLabel: String?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("* Label:") {
                pendingLabel = trimmed
                    .replacingOccurrences(of: "* Label:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Title:"), let label = pendingLabel {
                // Extract "Title: X, Version: Y, ..."
                let fields = trimmed.components(separatedBy: ",")
                let title = fields.first?
                    .replacingOccurrences(of: "Title:", with: "")
                    .trimmingCharacters(in: .whitespaces) ?? label
                let version = fields
                    .first(where: { $0.contains("Version:") })?
                    .components(separatedBy: "Version:").last?
                    .trimmingCharacters(in: .whitespaces)
                items.append(OutdatedItem(
                    identifier: label,
                    name: title,
                    currentVersion: nil,
                    latestVersion: version
                ))
                pendingLabel = nil
            }
        }
        return items
    }

    func upgradeCommand(_ items: [OutdatedItem]) -> String {
        let labels = items.isEmpty ? "--all" : ShellQuoting.arguments(items.map(\.identifier))
        return "softwareupdate --install \(labels)"
    }
}
