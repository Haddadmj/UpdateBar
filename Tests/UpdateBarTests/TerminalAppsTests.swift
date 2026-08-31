import XCTest

@testable import UpdateBar

/// The picker's list is built from LaunchServices, which differs per machine, so
/// the machine-dependent query is separated from the naming rule and only the
/// rule is tested here.
final class TerminalAppsTests: XCTestCase {

    /// The bug this suite exists for: WezTerm is installed and never appeared,
    /// because the old implementation matched a hardcoded list of
    /// `/Applications` paths.
    func testIncludesTerminalsOutsideApplications() {
        let handlers = [
            URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            URL(fileURLWithPath: "/Applications/WezTerm.app"),
            URL(fileURLWithPath: "/Users/someone/Applications/Ghostty.app")
        ]
        let names = TerminalApps.names(for: handlers)

        XCTAssertTrue(names.contains("WezTerm"))
        XCTAssertTrue(names.contains("Ghostty"), "a terminal in ~/Applications counts")
        XCTAssertTrue(names.contains("Terminal"))
    }

    /// "Default" means the system handler, which is a different choice from
    /// naming that same app explicitly — so it leads, and it leads only once.
    func testDefaultLeadsAndIsNotDuplicated() {
        let names = TerminalApps.names(for: [
            URL(fileURLWithPath: "/Applications/WezTerm.app"),
            URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        ])
        XCTAssertEqual(names.first, "Default")
        XCTAssertEqual(names.filter { $0 == "Default" }.count, 1)
    }

    func testRemainderIsSortedForAStableMenu() {
        let names = TerminalApps.names(for: [
            URL(fileURLWithPath: "/Applications/WezTerm.app"),
            URL(fileURLWithPath: "/Applications/Alacritty.app"),
            URL(fileURLWithPath: "/Applications/iTerm.app")
        ])
        XCTAssertEqual(names, ["Default", "Alacritty", "WezTerm", "iTerm"])
    }

    func testDuplicateBundleNamesAppearOnce() {
        let names = TerminalApps.names(for: [
            URL(fileURLWithPath: "/Applications/WezTerm.app"),
            URL(fileURLWithPath: "/Users/someone/Applications/WezTerm.app")
        ])
        XCTAssertEqual(names, ["Default", "WezTerm"])
    }

    // MARK: Which handlers count as terminals

    /// LaunchServices answers "who can open this file", which includes TextEdit,
    /// Numbers and Notes — apps that will display a `.command` script and never
    /// run it. The `Shell` document role is the app declaring that it *executes*
    /// the document, which is the actual question the setting asks.
    func testShellRoleIdentifiesATerminal() {
        // Captured from /System/Applications/Utilities/Terminal.app.
        let terminal: [[String: Any]] = [
            ["CFBundleTypeRole": "Shell", "LSItemContentTypes": ["com.apple.terminal.shell-script"]],
            ["CFBundleTypeRole": "Shell", "LSItemContentTypes": ["public.unix-executable"]]
        ]
        XCTAssertTrue(TerminalApps.declaresShellRole(documentTypes: terminal))
    }

    /// WezTerm declares Editor for the shell-script type and Shell only for
    /// unix-executable — so requiring the role on one specific type would have
    /// excluded the very app this ticket exists for.
    func testShellRoleOnAnyTypeIsEnough() {
        let wezterm: [[String: Any]] = [
            ["CFBundleTypeRole": "Editor", "CFBundleTypeName": "Terminal shell script"],
            ["CFBundleTypeRole": "Shell", "LSItemContentTypes": ["public.unix-executable"]]
        ]
        XCTAssertTrue(TerminalApps.declaresShellRole(documentTypes: wezterm))
    }

    func testEditorsAndViewersAreNotTerminals() {
        let textEdit: [[String: Any]] = [
            ["CFBundleTypeRole": "Editor", "LSItemContentTypes": ["public.plain-text"]],
            ["CFBundleTypeRole": "Viewer", "LSItemContentTypes": ["public.html"]]
        ]
        XCTAssertFalse(TerminalApps.declaresShellRole(documentTypes: textEdit))
        XCTAssertFalse(TerminalApps.declaresShellRole(documentTypes: []))
    }

    /// Why the rule is not "declares any script type in any role": Instruments
    /// declares `public.unix-executable` and is not a terminal. Widening to
    /// admit an Editor-role terminal would admit that too, which is why the
    /// `Shell` role stays the discriminator.
    func testViewerOfExecutablesIsNotATerminal() {
        let instrumentsShaped: [[String: Any]] = [
            ["CFBundleTypeRole": "Viewer", "LSItemContentTypes": ["public.unix-executable"]]
        ]
        XCTAssertFalse(TerminalApps.declaresShellRole(documentTypes: instrumentsShaped))
    }

    /// A stored preference outlives the app it names. Resolving must fail
    /// cleanly so the caller can fall back to the system handler, rather than
    /// opening nothing at all.
    func testResolvingAnUninstalledAppYieldsNil() {
        let handlers = [URL(fileURLWithPath: "/Applications/WezTerm.app")]
        XCTAssertEqual(TerminalApps.resolve("WezTerm", in: handlers)?.lastPathComponent, "WezTerm.app")
        XCTAssertNil(TerminalApps.resolve("Ghostty", in: handlers))
        XCTAssertNil(TerminalApps.resolve("Default", in: handlers), "Default is the system handler, not an app")
        XCTAssertNil(TerminalApps.resolve("", in: handlers))
    }
}
