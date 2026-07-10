import SwiftUI

struct SettingsView: View {
    @Bindable var coordinator: UpdateCoordinator
    private var prefs: AppPreferences { AppPreferences.shared }

    @State private var launchAtLogin = LoginItemManager.isRegistered
    @State private var loginError: String?

    private let intervals: [(label: String, hours: Int)] = [
        ("Manual only", 0),
        ("Every hour", 1),
        ("Every 6 hours", 6),
        ("Every 12 hours", 12),
        ("Daily", 24)
    ]

    var body: some View {
        Form {
            Section("General") {
                Picker("Check for updates", selection: Binding(
                    get: { prefs.refreshIntervalHours },
                    set: { prefs.refreshIntervalHours = $0; coordinator.scheduleAutoRefresh() }
                )) {
                    ForEach(intervals, id: \.hours) { Text($0.label).tag($0.hours) }
                }

                Toggle("Notify me about new updates", isOn: Binding(
                    get: { prefs.notifyOnNewUpdates },
                    set: { prefs.notifyOnNewUpdates = $0 }
                ))

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

            Section("Sources") {
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
                        HStack {
                            Image(systemName: state.iconSystemName)
                            Text(state.displayName)
                            if state.requiresAdmin {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 420)
    }
}
