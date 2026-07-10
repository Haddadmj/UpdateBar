import Foundation

/// Homebrew formulae + casks via `brew outdated --json=v2`.
struct HomebrewSource: UpdateSource {
    let id = "homebrew"
    let displayName = "Homebrew"
    let iconSystemName = "mug.fill"
    let runner: ProcessRunner

    func isAvailable() async -> Bool { await toolExists("brew", runner: runner) }

    func checkOutdated() async throws -> [OutdatedItem] {
        // `brew update` refreshes metadata; keep it quiet and don't fail the check if
        // the network hiccups — `outdated` still reports against cached metadata.
        _ = try? await runner.runShell("brew update --quiet", timeout: 90)
        let result = try await runner.runShell("brew outdated --json=v2", timeout: 90)
        guard let json = JSONExtractor.extract(result.stdout), let data = json.data(using: .utf8) else {
            throw SourceError.parse(displayName, result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        let payload = try JSONDecoder().decode(BrewOutdated.self, from: data)
        let formulae = payload.formulae.map {
            OutdatedItem(
                identifier: $0.name,
                name: $0.name,
                currentVersion: $0.installedVersions.first,
                latestVersion: $0.currentVersion
            )
        }
        let casks = payload.casks.map {
            OutdatedItem(
                identifier: $0.name,
                name: $0.name,
                currentVersion: $0.installedVersions.first,
                latestVersion: $0.currentVersion
            )
        }
        return formulae + casks
    }

    func upgradeCommand(_ items: [OutdatedItem]) -> String {
        let names = items.map(\.identifier).joined(separator: " ")
        return names.isEmpty ? "brew upgrade" : "brew upgrade \(names)"
    }

    // MARK: JSON

    private struct BrewOutdated: Decodable {
        let formulae: [Entry]
        let casks: [Entry]
    }
    private struct Entry: Decodable {
        let name: String
        let installedVersions: [String]
        let currentVersion: String
        enum CodingKeys: String, CodingKey {
            case name
            case installedVersions = "installed_versions"
            case currentVersion = "current_version"
        }
    }
}
