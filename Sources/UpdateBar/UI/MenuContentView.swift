import SwiftUI

struct MenuContentView: View {
    @Bindable var coordinator: UpdateCoordinator
    var onOpenSettings: (() -> Void)?

    private var failedCount: Int {
        coordinator.visibleStates.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
    }

    /// Sources with something to act on come first; the rest keep registry order. A
    /// long list of ticks should not push the one source with updates off the screen.
    private var orderedStates: [SourceState] {
        let states = coordinator.visibleStates
        return states.filter(\.needsAttention) + states.filter { !$0.needsAttention }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if coordinator.states.isEmpty {
                emptyState
            } else if coordinator.visibleStates.isEmpty {
                noSourcesState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(orderedStates) { state in
                            SourceRow(state: state, coordinator: coordinator)
                        }
                    }
                    .padding(Space.s)
                }
                .frame(maxHeight: 420)
            }

            Divider()
            footer
        }
        .frame(width: 360)
        .task { await coordinator.bootstrap() }
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(MenuHeadline.text(
                    total: coordinator.totalCount,
                    failed: failedCount,
                    enabledSources: coordinator.visibleStates.count,
                    isChecking: coordinator.isRefreshing || coordinator.lastRefresh == nil
                ))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())

                subtitle
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await coordinator.refreshAll() }
            } label: {
                // Says what just happened, not only how many updates there are.
                // A check that runs on open is otherwise invisible: the counts
                // rarely change, so without this the menu looks identical whether
                // it re-checked or not.
                if coordinator.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .frame(width: 24, height: 24)
            .disabled(coordinator.isRefreshing)
            .help("Refresh")
            .accessibilityLabel("Refresh")
        }
        .padding(Space.l)
    }

    @ViewBuilder
    private var subtitle: some View {
        if coordinator.states.isEmpty {
            Text("Detecting package managers…")
        } else if coordinator.isRefreshing {
            // The headline already says "Checking…" unless it is showing a count.
            Text(coordinator.totalCount > 0 ? "Checking…" : "This can take a minute")
        } else if let last = coordinator.lastRefresh {
            // On a timeline because the popover stays alive between opens: a plain
            // Text would keep saying "now" until something else redrew it.
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text("Checked \(last.formatted(.relative(presentation: .named)))"
                    + (failedCount > 0 ? " · \(failedCount) failed" : ""))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Space.s) {
            ProgressView()
            Text("Detecting package managers…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.l * 2)
    }

    private var noSourcesState: some View {
        Text("Turn a source on in Settings to check it for updates.")
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(Space.l * 2)
    }

    private var footer: some View {
        HStack(spacing: Space.m) {
            Button {
                onOpenSettings?()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            .accessibilityLabel("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit UpdateBar")
            .accessibilityLabel("Quit UpdateBar")

            Spacer()

            // The one primary action, kept well away from Quit.
            Button {
                Task { await coordinator.upgradeEverything() }
            } label: {
                Label("Upgrade All", systemImage: "arrow.up.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(coordinator.totalCount == 0)
        }
        .buttonStyle(.borderless)
        .padding(Space.m)
    }
}

private extension SourceState {
    var hasFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    var needsAttention: Bool { count > 0 || hasFailed }

    /// A row only opens if there is something to show inside it.
    var canExpand: Bool { isManageable && needsAttention }
}

struct SourceRow: View {
    let state: SourceState
    @Bindable var coordinator: UpdateCoordinator
    @State var expanded = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                SourceIconTile(systemName: state.iconSystemName)
                Text(state.displayName)
                    .fontWeight(state.needsAttention ? .medium : .regular)
                    .foregroundStyle(state.needsAttention ? .primary : .secondary)
                if state.requiresAdmin {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("Upgrades require admin rights")
                        .accessibilityLabel("Upgrades require admin rights")
                }
                if !state.isManageable { SystemBadge() }
                Spacer()
                statusAccessory
                if state.canExpand {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs + 2)
            .background(
                hovering && state.canExpand ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: Radius.row)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture {
                guard state.canExpand else { return }
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            }
            .contextMenu { rowMenu }

            // Non-manageable sources (e.g. Apple system Ruby) show an explanatory note
            // and offer no upgrade actions.
            if let note = state.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, detailInset)
                    .padding(.trailing, Space.s)
                    .padding(.bottom, Space.xs)
            } else if expanded && state.canExpand {
                details
            }
        }
    }

    /// Lines details up under the source's name: row padding + tile + gap.
    private var detailInset: CGFloat { Space.s + 24 + Space.s }

    private var details: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(state.items) { item in
                HStack(spacing: Space.s) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.name)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(item.versionSummary)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Update…") {
                        Task { await coordinator.upgrade(sourceID: state.id, items: [item]) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(state.requiresAdmin
                          ? "Runs in Terminal — needs your admin password"
                          : "Runs in Terminal")
                }
            }
            if state.count > 0 {
                Button("Upgrade all \(state.displayName)…") {
                    Task { await coordinator.upgrade(sourceID: state.id, items: []) }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            if case let .failed(message) = state.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.leading, detailInset)
        .padding(.trailing, Space.s)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.m)
    }

    /// Right-click actions for a source, so the two things worth doing to a
    /// whole package manager don't need the row expanded (upgrade) or the
    /// Settings window open (disable).
    @ViewBuilder
    private var rowMenu: some View {
        Button("Upgrade all \(state.displayName)…") {
            Task { await coordinator.upgrade(sourceID: state.id, items: []) }
        }
        .disabled(!state.isManageable || state.count == 0)

        Divider()

        Button("Disable \(state.displayName)") {
            coordinator.setEnabled(false, for: state.id)
        }
    }

    @ViewBuilder
    private var statusAccessory: some View {
        if !state.isManageable {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Not managed by UpdateBar")
        } else {
            switch state.status {
            case .checking, .upgrading:
                ProgressView().controlSize(.small)
            case .failed:
                Label("Failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .ok, .idle:
                if state.count > 0 {
                    Text("\(state.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, Space.s - 1)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                        .accessibilityLabel(state.count == 1 ? "1 update" : "\(state.count) updates")
                } else {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .accessibilityLabel("Up to date")
                }
            }
        }
    }
}
