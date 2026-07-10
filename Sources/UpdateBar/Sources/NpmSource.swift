import Foundation

/// Global npm packages via `npm outdated -g --json`.
/// Output is a JSON object keyed by package name: { "pkg": { "current": ..., "latest": ... } }
/// Empty output means everything is up to date.
struct NpmSource: UpdateSource {
    let id = "npm"
    let displayName = "npm (global)"
    let iconSystemName = "shippingbox.fill"
    let runner: ProcessRunner

    func isAvailable() async -> Bool { await toolExists("npm", runner: runner) }

    func checkOutdated() async throws -> [OutdatedItem] {
        // `npm outdated` exits non-zero when packages are outdated — that's expected.
        let result = try await runner.runShell("npm outdated -g --json", timeout: 120)
        guard let json = JSONExtractor.extract(result.stdout), json != "{}",
              let data = json.data(using: .utf8) else {
            return []
        }
        let decoded = try JSONDecoder().decode([String: Entry].self, from: data)
        return decoded.map { name, entry in
            OutdatedItem(
                identifier: name,
                name: name,
                currentVersion: entry.current,
                latestVersion: entry.latest
            )
        }.sorted { $0.name < $1.name }
    }

    func upgradeCommand(_ items: [OutdatedItem]) -> String {
        let names = items.map(\.identifier).joined(separator: " ")
        return names.isEmpty ? "npm update -g" : "npm install -g \(names)@latest"
    }

    private struct Entry: Decodable {
        let current: String?
        let latest: String?
    }
}
