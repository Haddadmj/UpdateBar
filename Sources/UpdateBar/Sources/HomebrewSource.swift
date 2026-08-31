import Foundation

/// Homebrew formulae + casks via `brew outdated --json=v2`.
struct HomebrewSource: UpdateSource {
    let id = "homebrew"
    let displayName = "Homebrew"
    let iconSystemName = "mug.fill"
    let runner: any CommandRunner

    func isAvailable() async -> Bool { await toolExists("brew", runner: runner) }

    func checkOutdated() async throws -> [OutdatedItem] {
        // `brew update` refreshes metadata; keep it quiet and don't fail the check if
        // the network hiccups — `outdated` still reports against cached metadata.
        _ = try? await runner.runShell("brew update --quiet", timeout: 90)
        let result = try await runner.runShell("brew outdated --json=v2", timeout: 90)
        guard let items = Self.parse(result.stdout) else {
            throw SourceError.parse(displayName, result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return items
    }

    /// Decodes `brew outdated --json=v2`. Nil means the output was not a payload
    /// this can read; an empty list means everything is current, which is what a
    /// healthy machine reports and is not a failure.
    static func parse(_ output: String) -> [OutdatedItem]? {
        guard let json = JSONExtractor.extract(output), let data = json.data(using: .utf8),
            let payload = try? JSONDecoder().decode(BrewOutdated.self, from: data)
        else { return nil }
        return (payload.formulae + payload.casks).map {
            OutdatedItem(
                identifier: $0.name,
                name: $0.name,
                currentVersion: $0.installedVersions.first,
                latestVersion: $0.currentVersion
            )
        }
    }

    func upgradeCommand(_ items: [OutdatedItem]) -> String {
        let names = ShellQuoting.arguments(items.map(\.identifier))
        return names.isEmpty ? "brew upgrade" : "brew upgrade \(names)"
    }

    // MARK: JSON

    struct BrewOutdated: Decodable {
        let formulae: [Entry]
        let casks: [Entry]
    }
    struct Entry: Decodable {
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
