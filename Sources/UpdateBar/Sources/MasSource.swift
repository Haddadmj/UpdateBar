import Foundation

/// Mac App Store apps via the `mas` CLI.
/// `mas outdated` prints lines like:
///   1352778147  Bitwarden    (2026.5.0 -> 2026.6.1)
struct MasSource: UpdateSource {
    let id = "mas"
    let displayName = "Mac App Store"
    let iconSystemName = "bag.fill"
    // mas 7+ requires root to install/upgrade apps, so we hand upgrades to Terminal.
    let requiresAdmin = true
    let runner: ProcessRunner

    func isAvailable() async -> Bool { await toolExists("mas", runner: runner) }

    func checkOutdated() async throws -> [OutdatedItem] {
        let result = try await runner.runShell("mas outdated", timeout: 60)
        guard result.succeeded else { throw SourceError.parse(displayName, result.stderr) }
        return Self.parse(result.stdout)
    }

    static func parse(_ output: String) -> [OutdatedItem] {
        output.split(separator: "\n").compactMap { line -> OutdatedItem? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let idEnd = trimmed.firstIndex(of: " ") else { return nil }
            let appID = String(trimmed[..<idEnd])
            guard appID.allSatisfy(\.isNumber) else { return nil }
            var rest = String(trimmed[idEnd...]).trimmingCharacters(in: .whitespaces)

            var current: String?
            var latest: String?
            if let open = rest.firstIndex(of: "("), let close = rest.lastIndex(of: ")") {
                let versions = String(rest[rest.index(after: open)..<close])
                let parts = versions.components(separatedBy: "->")
                if parts.count == 2 {
                    current = parts[0].trimmingCharacters(in: .whitespaces)
                    latest = parts[1].trimmingCharacters(in: .whitespaces)
                }
                rest = String(rest[..<open])
            }
            let name = rest.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return OutdatedItem(identifier: appID, name: name, currentVersion: current, latestVersion: latest)
        }
    }

    func upgradeCommand(_ items: [OutdatedItem]) -> String {
        let ids = items.map(\.identifier).joined(separator: " ")
        return ids.isEmpty ? "mas upgrade" : "mas upgrade \(ids)"
    }
}
