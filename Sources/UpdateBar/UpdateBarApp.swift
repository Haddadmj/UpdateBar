import SwiftUI

@main
struct UpdateBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Headless self-check: `UpdateBar --check` runs detection + checks against the
        // live system and prints a report, without launching the menu-bar UI. Useful
        // for CI smoke tests and manual verification.
        if CommandLine.arguments.contains("--check") {
            HeadlessCheck.runAndExit()
        }
    }

    var body: some Scene {
        // The UI lives entirely in the AppDelegate's NSStatusItem (menu bar). This empty
        // Settings scene just satisfies the App protocol's need for at least one scene;
        // the real settings window is presented by the delegate.
        Settings { EmptyView() }
    }
}
