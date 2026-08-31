import Foundation

/// RubyGems via `gem outdated`.
/// Lines: "addressable (2.8.7 < 2.9.0)"
struct GemSource: UpdateSource {
    let id = "gem"
    let displayName = "RubyGems"
    let iconSystemName = "diamond.fill"
    let requiresAdmin = true // system gem often needs sudo
    let runner: any CommandRunner

    func isAvailable() async -> Bool { await toolExists("gem", runner: runner) }

    /// Apple's system Ruby (/usr/bin/gem, Ruby 2.6) is frozen and deprecated: modern gems
    /// require Ruby >= 3.2, so its gems can never be upgraded. We surface it as a disabled
    /// row rather than silently hiding it, and it re-enables if a real Ruby is installed.
    func managementNote() async -> String? {
        await RubyEnvironment.isSystemGem(runner: runner)
            ? "Apple system Ruby — install Homebrew or rbenv Ruby to manage gems"
            : nil
    }

    func checkOutdated() async throws -> [OutdatedItem] {
        let result = try await runner.runShell("gem outdated", timeout: 180)
        guard result.succeeded else { throw SourceError.parse(displayName, result.stderr) }
        return Self.parse(result.stdout)
    }

    static func parse(_ output: String) -> [OutdatedItem] {
        output.split(separator: "\n").compactMap { raw -> OutdatedItem? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")") else { return nil }
            let name = line[..<open].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let versions = String(line[line.index(after: open)..<close]).components(separatedBy: "<")
            let current = versions.first?.trimmingCharacters(in: .whitespaces)
            let latest = versions.count > 1 ? versions[1].trimmingCharacters(in: .whitespaces) : nil
            return OutdatedItem(identifier: name, name: name, currentVersion: current, latestVersion: latest)
        }
    }

    func upgradeCommand(_ items: [OutdatedItem]) -> String {
        let names = ShellQuoting.arguments(items.map(\.identifier))
        return names.isEmpty ? "gem update" : "gem update \(names)"
    }
}

/// Helpers for reasoning about which Ruby a `gem` command targets.
enum RubyEnvironment {
    /// True when `gem` resolves to Apple's system Ruby (under `/usr/bin` or `/System`),
    /// which is locked to Ruby 2.6 and must not be managed.
    static func isSystemGem(runner: any CommandRunner) async -> Bool {
        guard let result = try? await runner.runShell("command -v gem", timeout: 20),
              result.succeeded else { return false }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/usr/bin") || path.hasPrefix("/System/")
    }
}
