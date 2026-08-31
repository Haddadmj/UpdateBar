import AppKit
import Foundation
import UniformTypeIdentifiers
import os

/// Runs upgrade commands in a terminal by writing a temporary `.command` script and
/// opening it with LaunchServices (`open`).
///
/// Why not AppleScript (`tell app "Terminal" to do script`)? That uses Apple Events,
/// which require the user to grant Automation (TCC) permission to control Terminal.
/// For an ad-hoc-signed app whose signature changes each build, that permission never
/// sticks — the result is a terminal window that opens but never runs the command (and
/// never prompts for a password). Opening a `.command` file needs no such permission.
///
/// The script applies the same `ProcessRunner.shellPrelude` used for detection, so tools
/// resolve identically and no interactive-shell prompt noise (p10k/gitstatus) appears.
@MainActor
enum UpgradeHandoff {

    /// A single labelled command to run, e.g. ("Homebrew", "brew upgrade").
    struct Job: Sendable {
        let label: String
        let command: String
    }

    static func run(_ jobs: [Job]) {
        guard !jobs.isEmpty else { return }

        var lines = ["#!/bin/zsh", ProcessRunner.shellPrelude]
        for job in jobs {
            lines.append("echo \(ShellQuoting.singleQuoted("==> \(job.label)"))")
            lines.append(job.command)
            lines.append("echo")
        }
        lines.append("echo \(ShellQuoting.singleQuoted("[UpdateBar] Finished — press any key to close."))")
        lines.append("read -k1 -s")
        lines.append(#"rm -f "$0""#)

        openScript(lines.joined(separator: "\n"))
    }

    // MARK: Helpers

    private static func openScript(_ contents: String) {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("updatebar-\(UUID().uuidString).command")
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)

            // Resolved to a bundle URL rather than passed to `open -a` by name:
            // `-a` matches on name, so two installed apps sharing one are
            // ambiguous, and it puts the path through a shell for no reason.
            // An unresolvable preference falls back to the system handler
            // instead of opening nothing.
            guard let app = TerminalApps.resolve(AppPreferences.shared.terminalApp) else {
                NSWorkspace.shared.open(url)
                return
            }
            NSWorkspace.shared.open(
                [url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()
            )
        } catch {
            Logger(subsystem: "com.updatebar.app", category: "upgrade")
                .error("could not write upgrade script: \(error.localizedDescription, privacy: .private)")
        }
    }
}

@MainActor
enum TerminalApps {
    /// The system handler for `.command` files — a real choice, and not the same
    /// as naming that app explicitly, because it follows the user's own default
    /// if they change it later.
    nonisolated static let systemDefault = "Default"

    /// Installed terminals — apps that will actually *run* a `.command` file.
    ///
    /// Asked rather than listed. A whitelist of `/Applications` paths could only
    /// ever be a worse copy of an answer the system already has: it missed
    /// WezTerm, `~/Applications`, Setapp, and every terminal installed after the
    /// array was written.
    ///
    /// LaunchServices alone is too generous, though — it answers "who can open
    /// this file", which includes TextEdit, Notes and Numbers, all of which will
    /// happily display an upgrade script and never execute it. The `Shell`
    /// document role is the app declaring that it *runs* the document, and that
    /// is the question this setting is really asking.
    static func handlers() -> [URL] {
        let types = [UTType("com.apple.terminal.shell-script"), .shellScript, .unixExecutable]
            .compactMap { $0 }
        var seen = Set<URL>()
        var found: [URL] = []
        for type in types {
            for url in NSWorkspace.shared.urlsForApplications(toOpen: type)
            where seen.insert(url).inserted && runsShellScripts(url) {
                found.append(url)
            }
        }
        return found
    }

    static func runsShellScripts(_ appURL: URL) -> Bool {
        guard let info = Bundle(url: appURL)?.infoDictionary,
            let documentTypes = info["CFBundleDocumentTypes"] as? [[String: Any]]
        else { return false }
        return declaresShellRole(documentTypes: documentTypes)
    }

    /// The rule itself, split from the bundle read so it can be tested against
    /// captured `Info.plist` fragments rather than whatever is installed.
    ///
    /// Not widened to "declares a script type in any role": Instruments declares
    /// `public.unix-executable` and is not a terminal.
    ///
    /// Any `Shell` role counts, not one on a specific type: Terminal declares it
    /// for `com.apple.terminal.shell-script`, while WezTerm declares only
    /// `Editor` there and takes `Shell` on `public.unix-executable`. Requiring a
    /// particular type would have excluded the app this whole change exists for.
    nonisolated static func declaresShellRole(documentTypes: [[String: Any]]) -> Bool {
        documentTypes.contains { ($0["CFBundleTypeRole"] as? String) == "Shell" }
    }

    /// Menu entries for the picker: the system default first, then each handler
    /// by name.
    static func available() -> [String] { names(for: handlers()) }

    /// The naming rule, split from the machine-dependent query above so it can
    /// be tested without depending on what happens to be installed.
    nonisolated static func names(for handlers: [URL]) -> [String] {
        var seen = Set<String>()
        let apps = handlers
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { !$0.isEmpty && $0 != systemDefault && seen.insert($0).inserted }
            .sorted()
        return [systemDefault] + apps
    }

    /// The bundle a stored preference names, or nil to mean "use the system
    /// handler" — which covers both `Default` and an app that has since been
    /// uninstalled. A preference outlives the app it names.
    nonisolated static func resolve(_ name: String, in handlers: [URL]) -> URL? {
        guard !name.isEmpty, name != systemDefault else { return nil }
        return handlers.first { $0.deletingPathExtension().lastPathComponent == name }
    }

    static func resolve(_ name: String) -> URL? { resolve(name, in: handlers()) }
}
