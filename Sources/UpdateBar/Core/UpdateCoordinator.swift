import Foundation
import Observation

/// Builds the list of sources available on this machine.
enum SourceRegistry {
    static func allSources(runner: ProcessRunner) -> [any UpdateSource] {
        [
            HomebrewSource(runner: runner),
            MasSource(runner: runner),
            SoftwareUpdateSource(runner: runner),
            NpmSource(runner: runner),
            PipxSource(runner: runner),
            CargoSource(runner: runner),
            RustupSource(runner: runner),
            GemSource(runner: runner),
            SelfUpdateSource(runner: runner)
        ]
    }
}

/// Owns the aggregated state and orchestrates concurrent checks/upgrades.
@MainActor
@Observable
final class UpdateCoordinator {
    private(set) var states: [SourceState] = []
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?

    private let runner = ProcessRunner()
    private var sources: [String: any UpdateSource] = [:]
    private let prefs = AppPreferences.shared

    /// Identifiers seen on the previous refresh, for new-update notifications.
    private var previouslySeen: Set<String> = []
    private var refreshTimer: Timer?
    private var hasBootstrapped = false

    var totalCount: Int {
        states.filter { prefs.isEnabled($0.id) }.reduce(0) { $0 + $1.count }
    }

    /// Sources the user has enabled, in registry order.
    var visibleStates: [SourceState] {
        states.filter { prefs.isEnabled($0.id) }
    }

    /// Probe which sources exist, then do a first refresh and start the timer.
    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        NotificationManager.requestAuthorization()
        let all = SourceRegistry.allSources(runner: runner)
        var available: [any UpdateSource] = []
        var notes: [String: String] = [:]
        for source in all where await source.isAvailable() {
            available.append(source)
            if let note = await source.managementNote() { notes[source.id] = note }
        }
        sources = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        states = available.map {
            SourceState(
                id: $0.id,
                displayName: $0.displayName,
                iconSystemName: $0.iconSystemName,
                requiresAdmin: $0.requiresAdmin,
                note: notes[$0.id]
            )
        }
        await refreshAll()
        scheduleAutoRefresh()
    }

    /// (Re)arm the periodic refresh according to the user's interval preference.
    func scheduleAutoRefresh() {
        refreshTimer?.invalidate()
        let hours = prefs.refreshIntervalHours
        guard hours > 0 else { refreshTimer = nil; return }
        let interval = TimeInterval(hours) * 3600
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refreshAll() }
        }
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Only check enabled, manageable sources; mark them as checking.
        let manageableIDs = Set(states.filter { $0.isManageable }.map(\.id))
        let active = sources.values.filter { prefs.isEnabled($0.id) && manageableIDs.contains($0.id) }
        for index in states.indices
        where prefs.isEnabled(states[index].id) && states[index].isManageable {
            states[index].status = .checking
        }

        await withTaskGroup(of: (String, Result<[OutdatedItem], Error>).self) { group in
            for source in active {
                group.addTask {
                    do { return (source.id, .success(try await source.checkOutdated())) }
                    catch { return (source.id, .failure(error)) }
                }
            }
            for await (id, result) in group {
                guard let idx = states.firstIndex(where: { $0.id == id }) else { continue }
                states[idx].lastChecked = Date()
                switch result {
                case .success(let items):
                    states[idx].items = items
                    states[idx].status = .ok
                case .failure(let error):
                    states[idx].items = []
                    states[idx].status = .failed(error.localizedDescription)
                }
            }
        }
        lastRefresh = Date()
        notifyIfNewUpdates()
    }

    /// Diff current updates against the last refresh and notify about newcomers.
    private func notifyIfNewUpdates() {
        let current = visibleStates.flatMap { state in
            state.items.map { "\(state.id):\($0.identifier)" }
        }
        let currentSet = Set(current)
        let newlyAppeared = currentSet.subtracting(previouslySeen)

        // Don't fire on the very first population (previouslySeen empty).
        if prefs.notifyOnNewUpdates && !previouslySeen.isEmpty && !newlyAppeared.isEmpty {
            let names = visibleStates
                .flatMap { $0.items }
                .filter { item in newlyAppeared.contains { $0.hasSuffix(":\(item.identifier)") } }
                .map(\.name)
            NotificationManager.notifyNewUpdates(count: newlyAppeared.count, sample: names)
        }
        previouslySeen = currentSet
    }

    /// Build the (possibly `sudo`-prefixed) command for a source's upgrade.
    private func job(for state: SourceState, items: [OutdatedItem]) -> UpgradeHandoff.Job? {
        guard let source = sources[state.id] else { return nil }
        let base = source.upgradeCommand(items)
        let command: String
        if state.requiresAdmin {
            if SudoCredential.hasPassword {
                // Feed the Keychain-stored password straight into `sudo -S` via a
                // here-string; `-p ''` silences sudo's own prompt. The plaintext
                // is fetched at runtime and never written into the script.
                command = "sudo -S -p '' \(base) <<< \"$(\(SudoCredential.shellRetrieval))\""
            } else {
                command = "sudo \(base)"
            }
        } else {
            command = base
        }
        return UpgradeHandoff.Job(label: state.displayName, command: command)
    }

    /// Run a single source's upgrade in Terminal. Upgrades always run in a real Terminal
    /// so output is visible and `sudo` can prompt for a password — spawning CLIs
    /// in-process gives them no TTY, so admin upgrades (mas, gem, macOS) silently fail.
    func upgrade(sourceID: String, items: [OutdatedItem]) async {
        guard let state = states.first(where: { $0.id == sourceID }),
              state.isManageable,
              let job = job(for: state, items: items) else { return }
        UpgradeHandoff.run([job])
    }

    /// Upgrade everything with pending updates, chained into one Terminal window.
    func upgradeEverything() async {
        let jobs = visibleStates
            .filter { $0.count > 0 }
            .compactMap { job(for: $0, items: []) }
        UpgradeHandoff.run(jobs)
    }
}
