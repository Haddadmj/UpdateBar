import Foundation

/// Rust toolchains via `rustup check`.
/// Lines: "stable-aarch64-apple-darwin - update available: 1.96.0 (...) -> 1.97.0 (...)"
struct RustupSource: UpdateSource {
    let id = "rustup"
    let displayName = "rustup"
    let iconSystemName = "gearshape.2.fill"
    let runner: any CommandRunner

    func isAvailable() async -> Bool { await toolExists("rustup", runner: runner) }

    func checkOutdated() async throws -> [OutdatedItem] {
        // `rustup check` exits with code 100 when updates are available, so we parse
        // stdout regardless of exit status and only treat empty+nonzero as an error.
        let result = try await runner.runShell("rustup check", timeout: 120)
        if result.stdout.isEmpty && !result.succeeded {
            throw SourceError.parse(displayName, result.stderr)
        }
        return Self.parse(result.stdout)
    }

    static func parse(_ output: String) -> [OutdatedItem] {
        output.split(separator: "\n").compactMap { raw -> OutdatedItem? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.lowercased().contains("update available") else { return nil }
            let parts = line.components(separatedBy: " - ")
            guard let toolchain = parts.first else { return nil }
            let versions = line.components(separatedBy: "->")
            let current = parts.count > 1
                ? parts[1].replacingOccurrences(of: "update available:", with: "")
                    .components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces)
                : nil
            let latest = versions.count > 1
                ? versions[1].components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces)
                : nil
            return OutdatedItem(identifier: toolchain, name: toolchain, currentVersion: current, latestVersion: latest)
        }
    }

    func upgradeCommand(_ items: [OutdatedItem]) -> String {
        "rustup update"
    }
}
