<h1 align="center">UpdateBar</h1>

<p align="center">
  <em>Every pending update on your Mac, in one menu-bar badge.</em>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-orange?logo=swift">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
</p>

UpdateBar is a lightweight macOS menu-bar app that aggregates outstanding updates from
**every package manager and app store on your Mac** — Homebrew, the Mac App Store, npm,
pipx, cargo, rustup, RubyGems, and macOS itself — into a single badge. Click for a
breakdown, then upgrade individual items, a whole source, or everything at once.

No polling servers, no telemetry, no Electron. It's a native SwiftUI + AppKit agent that
just shells out to the CLIs you already have.

---

## Why

Keeping a developer Mac current means remembering to run `brew outdated`, `npm outdated -g`,
`mas outdated`, `softwareupdate --list`, `rustup check`, `pipx`, `gem outdated`… every one
with its own flags and output format. UpdateBar runs them for you in the background and
surfaces a single number in the menu bar. When it's `✓`, you're fully patched.

## Features

- **One badge, every source** — a running total of pending updates across all detected managers.
- **Auto-detection** — only shows sources whose CLI is actually installed; add a manager, it appears.
- **Granular upgrades** — per-item, per-source, or **Upgrade All** in one action.
- **Right-click menu** — Check for Updates · Upgrade All · Settings · Quit.
- **Right-click a source** — upgrade that whole package manager, or switch it off, without
  expanding the row or opening Settings. Re-enabling re-checks it immediately.
- **Package-manager self-updates** — flags when `npm`, `brew`, RubyGems etc. themselves have a newer version.
- **Privileged handoff** — admin-gated upgrades (`softwareupdate`, system `gem`) open in your
  terminal so you can authenticate normally. Works with Terminal, **Warp**, iTerm, and more.
- **Settings** — refresh interval, an optional re-check when the menu opens, new-update
  notifications, the terminal upgrades are handed to, launch-at-login (`SMAppService`),
  and per-source enable/disable.
- **Runs deterministically** — CLIs execute through a fixed, non-interactive shell prelude, so
  your `.zshrc` / powerlevel10k doesn't leak noise into the output.

## Supported sources

| Source | CLI | Detection | Upgrade needs admin? |
|--------|-----|-----------|----------------------|
| Homebrew | `brew` | `brew outdated --json=v2` | no |
| Mac App Store | `mas` | `mas outdated` | no |
| macOS system | `softwareupdate` | `softwareupdate --list` | **yes** |
| npm (global) | `npm` | `npm outdated -g --json` | no |
| pipx | `pipx` | `pipx upgrade-all --dry-run` | no |
| cargo | `cargo-update` | `cargo install-update -l` | no |
| rustup | `rustup` | `rustup check` | no |
| RubyGems | `gem` | `gem outdated` | **yes** (system gem) |

## Requirements

- macOS 14+ (developed and tested on macOS 26, Apple Silicon)
- Swift 6 toolchain / Xcode 26 (to build)
- Optional CLIs for their respective sources:
  - `brew install mas` — Mac App Store
  - `cargo install cargo-update` — cargo outdated detection

## Install

### From a release DMG

Download the latest `UpdateBar.dmg`, open it, and drag **UpdateBar** into **Applications**.
Because local builds are ad-hoc signed (not notarized), the first launch needs a
right-click → **Open** to get past Gatekeeper.

### Build from source

```bash
git clone https://github.com/Haddadmj/UpdateBar.git
cd UpdateBar

# Compile and assemble a menu-bar .app bundle
./scripts/build-app.sh release
open .build/UpdateBar.app
```

Look for the ⤓ / ✓ icon in the menu bar. During development you can also:

```bash
swift build
swift test          # parsers, sources, coordinator, quoting, terminal + PAM detection
```

## Usage

- **Left-click** the menu-bar icon → the update breakdown popover.
- **Right-click** → context menu (Check for Updates · Upgrade All · Settings · Quit).
- **Right-click a package-manager row** → upgrade that source, or disable it.
- The badge shows the total pending count; a checkmark means you're fully up to date.

## Architecture

```
Sources/UpdateBar/
├── Core/
│   ├── ProcessRunner.swift      # runs CLIs via a deterministic non-interactive shell
│   ├── UpdateSource.swift       # the plugin protocol — add a manager = add one file
│   ├── UpdateCoordinator.swift  # @MainActor @Observable state; concurrent checks via TaskGroup
│   ├── UpgradeHandoff.swift     # writes .command scripts, opens them in your terminal
│   ├── ShellQuoting.swift       # quoting for values that enter a generated command
│   ├── SudoCredential.swift     # the admin password, behind a protocol
│   └── SudoAuthentication.swift # whether sudo authenticates with Touch ID
├── Sources/*Source.swift        # one plugin per package manager (parsers unit-tested)
├── Models/OutdatedItem.swift    # per-item / per-source state
└── UI/
    ├── AppDelegate.swift         # owns the NSStatusItem: popover + right-click menu
    ├── MenuContentView.swift     # the SwiftUI popover
    └── SettingsView.swift        # preferences window
```

Sources depend on `CommandRunner`, not on `ProcessRunner`, so a source's whole
path — the command it builds, the decode, the error mapping, the timeout — runs
in tests against canned output with no package manager installed.

If `sudo` on your Mac authenticates with Touch ID (one line in
`/etc/pam.d/sudo_local`, see Apple's `sudo_local.template`), admin updates ask
for a fingerprint and UpdateBar stores no password at all — which is the
recommended setup, since a stored password is readable by anything running as
you.

Design principles:

- **Pluggable sources.** Each manager conforms to `UpdateSource`; adding one is a single file.
- **Isolated failures.** One source erroring never blocks the others (per-source `TaskGroup`).
- **Deterministic shell.** CLIs run under a fixed PATH + explicit tool activation — never an
  interactive login shell — so prompt frameworks can't corrupt parsed output.
- **No automation permissions.** Privileged upgrades are handed off by writing a `.command`
  file and opening it via LaunchServices, avoiding AppleScript/TCC prompts.

## Packaging & distribution

```bash
# Local ad-hoc DMG (recipients right-click → Open the first time):
./scripts/release.sh

# Fully shippable, notarized DMG — needs an Apple Developer account:
export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
export AC_KEYCHAIN_PROFILE="notary"   # see release.sh header for setup
./scripts/release.sh                             # → .build/dist/UpdateBar.dmg
```

`release.sh` generates the icon, builds the app, signs (Developer ID + hardened runtime when
`DEVELOPER_ID` is set), builds a DMG, and notarizes + staples when notary credentials are
present. The app icon is rendered from an SF Symbol by `scripts/make-icon.swift`.

A Homebrew cask template lives in [`Casks/updatebar.rb`](Casks/updatebar.rb) — fill in the
release URL and sha256 after publishing, then `brew install --cask` from your tap.

> **Sandbox note:** UpdateBar ships **un-sandboxed** on purpose — a sandboxed app can't spawn
> `brew` / `mas` / etc. It relies on Developer ID + notarization (not the Mac App Store) for trust.

## Notes & limitations

- Admin-gated sources run their upgrade in the terminal (not in-process); **Upgrade All** covers
  only the non-privileged sources.
- Apple's **system Ruby** (`/usr/bin/gem`, Ruby 2.6) is shown as a dimmed, non-actionable row —
  its gems can't be upgraded. Install a Homebrew or rbenv Ruby to manage gems.
- Launch-at-login and notifications require running from the built `.app` bundle (not the raw
  SwiftPM binary).

## License

[MIT](LICENSE) © Mohammad Al-Haddad
