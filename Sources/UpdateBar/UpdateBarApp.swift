import AppKit

@main
@MainActor
enum UpdateBarApp {
    /// Held here because `NSApplication.delegate` is a weak reference.
    private static let appDelegate = AppDelegate()

    /// A plain AppKit entry point rather than a SwiftUI `App`. The UI lives entirely
    /// in the AppDelegate's NSStatusItem (menu bar), so an `App` would need a scene
    /// only to satisfy the protocol — and SwiftUI opens a placeholder `Settings` scene
    /// as a blank window at launch when the binary is stamped with SDK 14, which is
    /// what `swift build` produces for this package.
    static func main() {
        // Headless self-check: `UpdateBar --check` runs detection + checks against the
        // live system and prints a report, without launching the menu-bar UI. Useful
        // for CI smoke tests and manual verification.
        if CommandLine.arguments.contains("--check") {
            HeadlessCheck.runAndExit()
        }

        let app = NSApplication.shared
        app.delegate = appDelegate
        app.run()
    }
}
