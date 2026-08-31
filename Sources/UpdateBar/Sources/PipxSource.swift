import Foundation

/// Python CLI tools managed by pipx. We detect outdated tools with a dry-run of
/// `pipx upgrade-all`, which lists what would change without mutating anything.
struct PipxSource: UpdateSource {
    let id = "pipx"
    let displayName = "pipx"
    let iconSystemName = "cube.box.fill"
    let runner: any CommandRunner

    func isAvailable() async -> Bool { await toolExists("pipx", runner: runner) }

    func checkOutdated() async throws -> [OutdatedItem] {
        // pipx has no stable cross-version "outdated" command. First cheaply check
        // whether any tools are even managed by pipx; if none, we're trivially done.
        let list = try await runner.runShell("pipx list --json", timeout: 60)
        if let data = list.stdout.data(using: .utf8),
           let payload = try? JSONDecoder().decode(PipxList.self, from: data),
           payload.venvs.isEmpty {
            return []
        }
        // Some pipx versions support `--dry-run`; use it when available, otherwise
        // report nothing rather than erroring (upgrade-all is still offered manually).
        let help = try? await runner.runShell("pipx upgrade-all --help", timeout: 30)
        guard help?.stdout.contains("--dry-run") == true else { return [] }
        let result = try await runner.runShell("pipx upgrade-all --dry-run", timeout: 180)
        return Self.parse(result.stdout + "\n" + result.stderr)
    }

    private struct PipxList: Decodable {
        let venvs: [String: AnyCodable]
    }
    /// Minimal placeholder so we can decode `venvs` keys without their full schema.
    private struct AnyCodable: Decodable {}

    /// Lines look like: "upgraded package foo from 1.2.0 to 1.3.0"
    /// or "Would upgrade foo (1.2.0 -> 1.3.0)" depending on pipx version.
    static func parse(_ output: String) -> [OutdatedItem] {
        var items: [OutdatedItem] = []
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            guard lower.contains("upgrade"), lower.contains("would") || lower.contains("from") else { continue }
            // Heuristic extraction of "name (a -> b)" or "name from a to b".
            if let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")") {
                let name = line[..<open]
                    .replacingOccurrences(of: "Would upgrade", with: "")
                    .trimmingCharacters(in: .whitespaces)
                let versions = String(line[line.index(after: open)..<close]).components(separatedBy: "->")
                items.append(OutdatedItem(
                    identifier: name,
                    name: name,
                    currentVersion: versions.first?.trimmingCharacters(in: .whitespaces),
                    latestVersion: versions.count > 1 ? versions[1].trimmingCharacters(in: .whitespaces) : nil
                ))
            }
        }
        return items
    }

    func upgradeCommand(_ items: [OutdatedItem]) -> String {
        if items.isEmpty { return "pipx upgrade-all" }
        return items.map { "pipx upgrade \(ShellQuoting.singleQuoted($0.identifier))" }.joined(separator: " && ")
    }
}
