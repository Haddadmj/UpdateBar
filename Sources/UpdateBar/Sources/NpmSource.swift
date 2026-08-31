import Foundation

/// Global npm packages via `npm outdated -g --json`.
/// Output is a JSON object keyed by package name: { "pkg": { "current": ..., "latest": ... } }
/// Empty output means everything is up to date.
struct NpmSource: UpdateSource {
    let id = "npm"
    let displayName = "npm (global)"
    let iconSystemName = "shippingbox.fill"
    let runner: any CommandRunner

    func isAvailable() async -> Bool { await toolExists("npm", runner: runner) }

    func checkOutdated() async throws -> [OutdatedItem] {
        // `npm outdated` exits non-zero when packages are outdated — that's expected.
        let result = try await runner.runShell("npm outdated -g --json", timeout: 120)
        guard let items = Self.parse(result.stdout) else {
            throw SourceError.parse(displayName, result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return items
    }

    /// Decodes `npm outdated -g --json`, an object keyed by package name.
    ///
    /// Empty output and `{}` are an empty list — everything is current. Nil is
    /// reserved for output that could not be read at all, which must not be
    /// reported as "no updates": that is the worst possible answer, because it
    /// looks like good news.
    static func parse(_ output: String) -> [OutdatedItem]? {
        // No output at all is npm's way of saying nothing is outdated. Output
        // that exists but holds no JSON is a failure — `npm ERR! code E401` is
        // not an empty update list.
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let json = JSONExtractor.extract(trimmed) else { return nil }
        guard json != "{}" else { return [] }
        guard let data = json.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return nil }
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
        let names = items.map { ShellQuoting.singleQuoted("\($0.identifier)@latest") }.joined(separator: " ")
        return names.isEmpty ? "npm update -g" : "npm install -g \(names)"
    }

    struct Entry: Decodable {
        let current: String?
        let latest: String?
    }
}
