import Foundation

/// Checks whether the package-manager *tools themselves* are outdated (npm the program,
/// RubyGems), as opposed to the packages they manage. Shown as its own "Package Managers"
/// section.
///
/// Only managers with a clean, reliable self-version check are included:
/// - **npm**: `npm -v` vs `npm view npm version`; upgrade `npm install -g npm@latest`.
/// - **RubyGems**: `gem --version` vs latest `rubygems-update`; upgrade `sudo gem update --system`.
///
/// (Homebrew and rustup self-update as a side effect of `brew update` / `rustup update`,
/// and Homebrew's pip is externally managed, so those are intentionally omitted.)
struct SelfUpdateSource: UpdateSource {
    let id = "managers"
    let displayName = "Package Managers"
    let iconSystemName = "shippingbox.circle.fill"
    let runner: any CommandRunner

    func isAvailable() async -> Bool { true }

    func checkOutdated() async throws -> [OutdatedItem] {
        async let npm = checkNpm()
        async let gems = checkRubyGems()
        return await [npm, gems].compactMap { $0 }
    }

    func upgradeCommand(_ items: [OutdatedItem]) -> String {
        items.compactMap { item -> String? in
            switch item.identifier {
            case "npm": return "npm install -g npm@latest"
            case "rubygems": return "sudo gem update --system"   // system gem needs root
            default: return nil
            }
        }.joined(separator: " && ")
    }

    // MARK: Individual checks

    /// Reads the version out of `gem search -r -e rubygems-update`, which prints
    /// `rubygems-update (4.0.16)` — or several, newest first, when a gem has more
    /// than one published release.
    ///
    /// This source has no single list to decode the way the others do, so its
    /// seam is the one line that is actually parsing rather than an invented
    /// `parse` with the wrong shape.
    static func parseGemSearchVersion(_ output: String) -> String? {
        guard let open = output.firstIndex(of: "("), let close = output.firstIndex(of: ")"),
            open < close
        else { return nil }
        let inside = output[output.index(after: open)..<close]
        let first = inside.split(separator: ",").first.map(String.init) ?? String(inside)
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func checkNpm() async -> OutdatedItem? {
        guard await toolExists("npm", runner: runner),
              let cur = try? await runner.runShell("npm -v", timeout: 40), cur.succeeded,
              let lat = try? await runner.runShell("npm view npm version", timeout: 40), lat.succeeded
        else { return nil }
        let current = cur.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let latest = lat.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Version.isNewer(latest, than: current) else { return nil }
        return OutdatedItem(identifier: "npm", name: "npm", currentVersion: current, latestVersion: latest)
    }

    private func checkRubyGems() async -> OutdatedItem? {
        // Never offer `gem update --system` on Apple's system Ruby — it's locked to
        // Ruby 2.6 and the newer RubyGems requires Ruby >= 3.2, so it always fails.
        guard await toolExists("gem", runner: runner),
              await !RubyEnvironment.isSystemGem(runner: runner),
              let cur = try? await runner.runShell("gem --version", timeout: 40), cur.succeeded,
              let lat = try? await runner.runShell("gem search -r -e rubygems-update", timeout: 60), lat.succeeded
        else { return nil }
        let current = cur.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let latest = Self.parseGemSearchVersion(lat.stdout),
              Version.isNewer(latest, than: current) else { return nil }
        return OutdatedItem(identifier: "rubygems", name: "RubyGems", currentVersion: current, latestVersion: latest)
    }
}

/// Minimal numeric version comparison for "is `a` newer than `b`".
enum Version {
    static func isNewer(_ a: String, than b: String) -> Bool {
        let lhs = components(a), rhs = components(b)
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        for i in 0..<max(lhs.count, rhs.count) {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func components(_ s: String) -> [Int] {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}
