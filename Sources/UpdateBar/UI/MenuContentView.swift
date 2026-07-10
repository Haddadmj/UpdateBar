import SwiftUI

struct MenuContentView: View {
    @Bindable var coordinator: UpdateCoordinator
    var onOpenSettings: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if coordinator.states.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(coordinator.visibleStates) { state in
                            SourceSectionView(state: state, coordinator: coordinator)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 420)
            }

            Divider()
            footer
        }
        .frame(width: 340)
        .task { await coordinator.bootstrap() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill")
            Text("UpdateBar")
                .font(.headline)
            Spacer()
            if coordinator.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Text("\(coordinator.totalCount) updates")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Detecting package managers…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            HStack {
                Button {
                    Task { await coordinator.refreshAll() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(coordinator.isRefreshing)

                Spacer()

                Button {
                    Task { await coordinator.upgradeEverything() }
                } label: {
                    Label("Upgrade All", systemImage: "arrow.up.circle")
                }
                .disabled(coordinator.totalCount == 0)

                Button {
                    onOpenSettings?()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit UpdateBar")
            }
            .buttonStyle(.borderless)

            if let last = coordinator.lastRefresh {
                Text("Last checked \(last.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
    }
}

struct SourceSectionView: View {
    let state: SourceState
    @Bindable var coordinator: UpdateCoordinator
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: state.iconSystemName)
                    .frame(width: 18)
                Text(state.displayName)
                    .font(.subheadline.weight(.medium))
                if state.requiresAdmin {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Upgrades require admin rights")
                }
                Spacer()
                statusAccessory
            }
            .contentShape(Rectangle())
            .opacity(state.isManageable ? 1 : 0.55)
            .onTapGesture { withAnimation { expanded.toggle() } }

            // Non-manageable sources (e.g. Apple system Ruby) show an explanatory note
            // and offer no upgrade actions.
            if let note = state.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 26)
                    .padding(.trailing, 10)
            } else if expanded {
                ForEach(state.items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name).font(.callout)
                            Text(item.versionSummary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Update…") {
                            Task { await coordinator.upgrade(sourceID: state.id, items: [item]) }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help(state.requiresAdmin
                              ? "Runs in Terminal — needs your admin password"
                              : "Runs in Terminal")
                    }
                    .padding(.leading, 26)
                    .padding(.vertical, 1)
                }
                if state.count > 0 {
                    Button("Upgrade all \(state.displayName)…") {
                        Task { await coordinator.upgrade(sourceID: state.id, items: []) }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .padding(.leading, 26)
                }
                if case let .failed(message) = state.status {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.leading, 26)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusAccessory: some View {
        if !state.isManageable {
            return AnyView(Image(systemName: "info.circle").foregroundStyle(.secondary).font(.caption))
        }
        return AnyView(managedAccessory)
    }

    @ViewBuilder
    private var managedAccessory: some View {
        switch state.status {
        case .checking:
            ProgressView().controlSize(.small)
        case .upgrading:
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .ok, .idle:
            if state.count > 0 {
                Text("\(state.count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.tint.opacity(0.2)))
            } else {
                Image(systemName: "checkmark").foregroundStyle(.green).font(.caption)
            }
        }
    }
}
