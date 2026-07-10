import AppKit
import Foundation

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
            lines.append("echo \(singleQuoted("==> \(job.label)"))")
            lines.append(job.command)
            lines.append("echo")
        }
        lines.append("echo \(singleQuoted("[UpdateBar] Finished — press any key to close."))")
        lines.append("read -k1 -s")
        lines.append(#"rm -f "$0""#)

        openScript(lines.joined(separator: "\n"))
    }

    // MARK: Helpers

    /// Wraps `s` in single quotes, escaping embedded single quotes (`'` → `'\''`).
    private static func singleQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func openScript(_ contents: String) {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("updatebar-\(UUID().uuidString).command")
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)

            let choice = AppPreferences.shared.terminalApp
            if choice.isEmpty || choice == "Default" {
                NSWorkspace.shared.open(url)
            } else {
                // open -a <App> <script>: launch a specific terminal (Warp, iTerm, …).
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                proc.arguments = ["-a", choice, url.path]
                try proc.run()
            }
        } catch {
            NSLog("UpdateBar: failed to launch upgrade terminal: \(error)")
            // Fall back to the default handler so the user still gets a terminal.
            NSWorkspace.shared.open(url)
        }
    }
}

/// Detects which terminal apps are installed, for the Settings picker.
@MainActor
enum TerminalApps {
    /// Returns "Default" plus any installed terminals we recognise.
    static func available() -> [String] {
        var found = ["Default"]
        let candidates: [(name: String, path: String)] = [
            ("Terminal", "/System/Applications/Utilities/Terminal.app"),
            ("Warp", "/Applications/Warp.app"),
            ("iTerm", "/Applications/iTerm.app"),
            ("Ghostty", "/Applications/Ghostty.app"),
            ("kitty", "/Applications/kitty.app"),
            ("Alacritty", "/Applications/Alacritty.app")
        ]
        for c in candidates where FileManager.default.fileExists(atPath: c.path) {
            found.append(c.name)
        }
        return found
    }
}
