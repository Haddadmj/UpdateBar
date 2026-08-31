import Foundation

/// `cargo install`ed binaries via the `cargo-update` helper (`cargo install-update -l`).
/// Requires: `cargo install cargo-update`.
struct CargoSource: UpdateSource {
    let id = "cargo"
    let displayName = "cargo"
    let iconSystemName = "wrench.and.screwdriver.fill"
    let runner: any CommandRunner

    func isAvailable() async -> Bool {
        // Needs both cargo and the install-update subcommand.
        guard await toolExists("cargo", runner: runner) else { return false }
        let help = try? await runner.runShell("cargo install-update --version", timeout: 30)
        return help?.succeeded ?? false
    }

    func checkOutdated() async throws -> [OutdatedItem] {
        // -l lists status without applying updates.
        let result = try await runner.runShell("cargo install-update -l", timeout: 180)
        guard result.succeeded else { throw SourceError.parse(displayName, result.stderr) }
        return Self.parse(result.stdout)
    }

    /// Table rows: "Package  Installed  Latest  Needs update"
    /// A trailing "Yes" marks an available update.
    static func parse(_ output: String) -> [OutdatedItem] {
        output.split(separator: "\n").compactMap { raw -> OutdatedItem? in
            let cols = raw.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
                .filter { !$0.isEmpty }
            guard cols.count >= 4 else { return nil }
            guard cols.last?.lowercased() == "yes" else { return nil }
            // cols: [name, installed, latest, "Yes"]
            return OutdatedItem(
                identifier: cols[0],
                name: cols[0],
                currentVersion: cols[1],
                latestVersion: cols[2]
            )
        }
    }

    func upgradeCommand(_ items: [OutdatedItem]) -> String {
        let names = items.map(\.identifier).joined(separator: " ")
        return names.isEmpty ? "cargo install-update -a" : "cargo install-update \(names)"
    }
}
