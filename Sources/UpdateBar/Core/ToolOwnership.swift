import Foundation

/// Who is responsible for updating a tool's own files.
///
/// Decides whether UpdateBar may touch a tool at all. Replacing a tool that macOS or
/// Homebrew installed goes behind the owner's back: Apple's copy may be load-bearing
/// and sealed, and Homebrew's copy gets clobbered or conflicts on the next `brew upgrade`.
enum ToolOwner: Equatable, Sendable {
    /// Shipped by Apple, with macOS or the developer tools.
    case system
    /// Installed as a Homebrew formula, which reports its own updates.
    case homebrew
    /// Anywhere else: rbenv, nvm, asdf, a hand-rolled prefix.
    case user

    static func classify(path: String) -> ToolOwner {
        let systemPrefixes = [
            "/usr/bin/", "/bin/", "/usr/sbin/", "/sbin/", "/System/",
            "/Library/Developer/", "/Applications/Xcode"
        ]
        let homebrewPrefixes = ["/opt/homebrew/", "/usr/local/Cellar/", "/usr/local/Homebrew/"]
        if systemPrefixes.contains(where: path.hasPrefix) { return .system }
        if homebrewPrefixes.contains(where: path.hasPrefix) { return .homebrew }
        return .user
    }

    /// The owner of `tool` as this user's shell resolves it, or nil if that can't be
    /// told — which callers must treat as "not ours to update".
    ///
    /// Follows symlinks because Intel Homebrew's `/usr/local/bin/gem` only reveals
    /// itself as Homebrew's once resolved into the Cellar.
    static func of(_ tool: String, runner: any CommandRunner) async -> ToolOwner? {
        guard let result = try? await runner.runShell("readlink -f \"$(command -v \(tool))\"", timeout: 20),
              result.succeeded,
              // The last line, because an interactive shell may print a banner first.
              let path = result.stdout.split(whereSeparator: \.isNewline).last.map(String.init),
              path.hasPrefix("/")
        else { return nil }
        return classify(path: path)
    }
}
