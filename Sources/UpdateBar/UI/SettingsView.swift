import SwiftUI

struct SettingsView: View {
    @Bindable var coordinator: UpdateCoordinator
    private var prefs: AppPreferences { AppPreferences.shared }

    @State private var launchAtLogin = LoginItemManager.isRegistered
    @State private var loginError: String?

    @State private var adminPassword = ""
    @State private var passwordSaved = SudoCredential.hasPassword
    /// Read once when the window appears rather than on every redraw: it is a
    /// file read, and the answer does not change while a settings window is open.
    @State private var touchIDEnabled = SudoAuthentication.isTouchIDEnabled

    private let intervals: [(label: String, hours: Int)] = [
        ("Manual only", 0),
        ("Every hour", 1),
        ("Every 6 hours", 6),
        ("Every 12 hours", 12),
        ("Daily", 24)
    ]

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            sources.tabItem { Label("Sources", systemImage: "shippingbox") }
            admin.tabItem { Label("Admin access", systemImage: "lock") }
        }
        .frame(width: 460, height: 420)
    }

    private var general: some View {
        Form {
            Section("Updates") {
                Picker("Check for updates", selection: Binding(
                    get: { prefs.refreshIntervalHours },
                    set: { prefs.refreshIntervalHours = $0; coordinator.scheduleAutoRefresh() }
                )) {
                    ForEach(intervals, id: \.hours) { Text($0.label).tag($0.hours) }
                }

                Toggle("Also check when the menu opens", isOn: Binding(
                    get: { prefs.refreshOnOpen },
                    set: { prefs.refreshOnOpen = $0 }
                ))
                .help("Re-check when you open the menu, unless the last check was less than five minutes ago.")

                Toggle("Notify me about new updates", isOn: Binding(
                    get: { prefs.notifyOnNewUpdates },
                    set: { prefs.notifyOnNewUpdates = $0 }
                ))
            }

            Section("App") {
                Picker("Run upgrades in", selection: Binding(
                    get: { prefs.terminalApp },
                    set: { prefs.terminalApp = $0 }
                )) {
                    ForEach(TerminalApps.available(), id: \.self) { Text($0).tag($0) }
                }

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            let achieved = try LoginItemManager.setEnabled(newValue)
                            launchAtLogin = achieved
                            prefs.launchAtLogin = achieved
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LoginItemManager.isRegistered
                        }
                    }

                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var sources: some View {
        Form {
            Section {
                if coordinator.states.isEmpty {
                    Text("Detecting installed package managers…")
                        .foregroundStyle(.secondary)
                }
                ForEach(coordinator.states) { state in
                    Toggle(isOn: Binding(
                        get: { prefs.isEnabled(state.id) },
                        set: { newValue in
                            prefs.setEnabled(newValue, for: state.id)
                            if newValue { Task { await coordinator.refreshAll() } }
                        }
                    )) {
                        HStack(spacing: Space.s) {
                            SourceIconTile(systemName: state.iconSystemName)
                            Text(state.displayName)
                            if state.requiresAdmin {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if !state.isManageable { SystemBadge() }
                        }
                    }
                }
            } footer: {
                Text("Switched-off sources aren't checked or shown in the menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var admin: some View {
        Form {
            Section {
                if touchIDEnabled {
                    // Touch ID already covers `sudo`, so a stored password buys
                    // nothing here — and an unneeded credential is strictly a
                    // liability. Offering the field anyway would be inviting one.
                    Label(
                        "Touch ID is enabled for sudo — admin updates will ask for "
                            + "your fingerprint.",
                        systemImage: "touchid"
                    )
                    .foregroundStyle(.green)

                    if passwordSaved {
                        // Someone who turned Touch ID on after storing a password
                        // should be told the stored copy is now dead weight.
                        HStack {
                            Text("A stored admin password is no longer needed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            removePasswordButton
                        }
                    }
                } else if passwordSaved {
                    HStack {
                        Label("Admin password saved", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        removePasswordButton
                    }
                } else {
                    HStack {
                        SecureField("Admin password", text: $adminPassword)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                        Button("Save") {
                            if SudoCredential.store(adminPassword) {
                                adminPassword = ""
                                passwordSaved = true
                            }
                        }
                        .disabled(adminPassword.isEmpty)
                    }
                }
            } footer: {
                if touchIDEnabled {
                    Text("Nothing to store. `sudo` authenticates with Touch ID, so "
                        + "updates that need administrator access (macOS, Mac App "
                        + "Store, gem) will ask for your fingerprint in the terminal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Stored securely in your Keychain and used for updates that "
                        + "require administrator access (macOS, Mac App Store, gem), so "
                        + "you won't be prompted in Terminal. Leave empty to be prompted "
                        + "each time — or enable Touch ID for sudo, which needs no "
                        + "stored password at all.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var removePasswordButton: some View {
        Button("Remove") {
            SudoCredential.clear()
            adminPassword = ""
            passwordSaved = false
        }
    }
}
