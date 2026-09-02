import Foundation
import Observation
import os

/// Builds the list of sources available on this machine.
enum SourceRegistry {
    static func allSources(runner: any CommandRunner) -> [any UpdateSource] {
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

    private let runner: any CommandRunner
    private var sources: [String: any UpdateSource] = [:]
    private let prefs: any SourcePreferences
    private let notifier: any UpdateNotifier
    private let credential: any PrivilegedCredential
    /// A menu-bar app refreshes with no window to report into, so when checks
    /// quietly stop — a timer that never re-armed, a source failing every time —
    /// there is nothing to look at afterwards.
    ///
    /// Outcomes only. Nothing here logs a command body or its output:
    /// `SudoCredential.shellRetrieval` composes a line that prints a password,
    /// and it must never reach the log.
    private let log = Logger(subsystem: "com.updatebar.app", category: "refresh")

    /// Supplied by a test; nil means "probe this machine".
    private let providedSources: [any UpdateSource]?

    /// Defaults reproduce the previous behaviour exactly, so the app builds one
    /// the same way it always did and only a test passes anything.
    init(
        sources: [any UpdateSource]? = nil,
        runner: any CommandRunner = ProcessRunner(),
        preferences: any SourcePreferences = AppPreferences.shared,
        notifier: any UpdateNotifier = SystemNotifier(),
        credential: any PrivilegedCredential = KeychainCredential(),
        stalenessWindow: TimeInterval = 5 * 60,
        minimumVisibleRefresh: TimeInterval = 0.6
    ) {
        self.providedSources = sources
        self.runner = runner
        self.prefs = preferences
        self.notifier = notifier
        self.credential = credential
        self.stalenessWindow = stalenessWindow
        self.minimumVisibleRefresh = minimumVisibleRefresh
    }

    /// How recent a refresh has to be for opening the menu not to redo it.
    ///
    /// The checks shell out — `softwareupdate -l` alone can take tens of
    /// seconds — so opening and closing the menu a few times in a row must not
    /// start a check each time.
    private let stalenessWindow: TimeInterval

    /// How long the refreshing indicator stays up even if the work finishes
    /// sooner.
    ///
    /// A check against warm caches can return in milliseconds, and a spinner
    /// that appears and vanishes within one frame reads as nothing having
    /// happened at all — which is exactly how a working refresh gets reported
    /// as broken. Tests pass 0.
    private let minimumVisibleRefresh: TimeInterval

    /// Identifiers seen on the previous refresh, for new-update notifications.
    private var previouslySeen: Set<String> = []
    /// Whether a refresh has completed at all.
    ///
    /// Tracked rather than inferred from `previouslySeen` being empty. A machine
    /// that is fully up to date on launch produces an empty first refresh, and
    /// inferring would treat the *next* one as another first population — so the
    /// first real update after a clean start went unannounced.
    private var hasPopulated = false
    private var refreshTimer: Timer?
    private var hasBootstrapped = false
    /// Whether the menu has been opened since launch, for the first-open exemption.
    private var hasOpenedSinceLaunch = false

    var totalCount: Int {
        states.filter { prefs.isEnabled($0.id) }.reduce(0) { $0 + $1.count }
    }

    /// Sources the user has enabled, in registry order.
    var visibleStates: [SourceState] {
        states.filter { prefs.isEnabled($0.id) }
    }

    func isEnabled(_ sourceID: String) -> Bool { prefs.isEnabled(sourceID) }

    /// Turn a source on or off.
    ///
    /// Re-enabling re-checks, because a source that was off has no counts and
    /// would otherwise reappear reading zero until the next scheduled refresh.
    func setEnabled(_ enabled: Bool, for sourceID: String) {
        prefs.setEnabled(enabled, for: sourceID)
        if enabled { Task { await refreshAll() } }
    }

    /// Probe which sources exist, then do a first refresh and start the timer.
    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        notifier.requestAuthorization()
        let all = providedSources ?? SourceRegistry.allSources(runner: runner)
        var available: [any UpdateSource] = []
        var notes: [String: String] = [:]
        var elevated: Set<String> = []
        for source in all where await source.isAvailable() {
            available.append(source)
            if let note = await source.managementNote() { notes[source.id] = note }
            if await source.requiresAdmin() { elevated.insert(source.id) }
        }
        sources = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        states = available.map {
            SourceState(
                id: $0.id,
                displayName: $0.displayName,
                iconSystemName: $0.iconSystemName,
                requiresAdmin: elevated.contains($0.id),
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
        guard hours > 0 else {
            refreshTimer = nil
            log.debug("auto-refresh off — manual only")
            return
        }
        let interval = TimeInterval(hours) * 3600
        log.debug("auto-refresh armed: every \(hours, privacy: .public)h")
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refreshAll() }
        }
    }

    /// Refresh because the user just opened the menu, unless the numbers on it
    /// are already recent.
    ///
    /// Opening the menu is the only moment the counts are actually read, and
    /// with the default six-hour interval they can easily be hours stale by
    /// then — so that is the moment to re-check.
    func refreshIfStale() async {
        guard prefs.refreshOnOpen else { return }
        // Before bootstrap there are no sources to check, and refreshing anyway
        // would stamp `lastRefresh` and suppress the real first refresh.
        guard hasBootstrapped, !isRefreshing else { return }

        // The first open always re-checks. The bootstrap refresh ran before
        // anyone was looking, so from the user's side the app has not checked
        // anything yet — and a launch-then-open, which is the obvious way to
        // try this, would otherwise land inside the window and do nothing.
        let isFirstOpen = !hasOpenedSinceLaunch
        hasOpenedSinceLaunch = true

        if !isFirstOpen, let last = lastRefresh,
           Date().timeIntervalSince(last) < stalenessWindow { return }
        await refreshAll()
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let startedAt = Date()
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
        report()
        notifyIfNewUpdates()

        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < minimumVisibleRefresh {
            try? await Task.sleep(for: .seconds(minimumVisibleRefresh - elapsed))
        }
    }

    /// One line per refresh, so "why does the badge say nothing" is answerable
    /// after the fact rather than only while it is happening.
    ///
    /// Source names and counts are public; a failure's *text* is not. That text
    /// is `error.localizedDescription`, and a source builds it from raw stderr —
    /// an `npm outdated` that fails on registry auth can echo a `_authToken`,
    /// and the unified log is readable by anything that can run `log show`.
    /// Truncating it was not redaction. Which source failed is the part worth
    /// seeing without a fuss; the detail is there under `--info` for whoever is
    /// actually debugging.
    private func report() {
        let outcomes = states.map { state -> String in
            switch state.status {
            case .failed: return "\(state.id): failed"
            case .checking: return "\(state.id): still checking"
            default: return "\(state.id): \(state.count)"
            }
        }.joined(separator: ", ")
        log.notice("refresh: \(outcomes, privacy: .public)")

        for state in states {
            guard case let .failed(message) = state.status else { continue }
            log.info("\(state.id, privacy: .public) failed: \(message, privacy: .private)")
        }
    }

    /// Diff current updates against the last refresh and notify about newcomers.
    private func notifyIfNewUpdates() {
        let current = visibleStates.flatMap { state in
            state.items.map { "\(state.id):\($0.identifier)" }
        }
        let currentSet = Set(current)
        let newlyAppeared = currentSet.subtracting(previouslySeen)

        // Silent on the first population — otherwise every launch would announce
        // everything already outstanding.
        if prefs.notifyOnNewUpdates && hasPopulated && !newlyAppeared.isEmpty {
            let names = visibleStates
                .flatMap { $0.items }
                .filter { item in newlyAppeared.contains { $0.hasSuffix(":\(item.identifier)") } }
                .map(\.name)
            notifier.notifyNewUpdates(count: newlyAppeared.count, sample: names)
        }
        previouslySeen = currentSet
        hasPopulated = true
    }

    /// Build the (possibly `sudo`-prefixed) command for a source's upgrade.
    private func job(for state: SourceState, items: [OutdatedItem]) -> UpgradeHandoff.Job? {
        guard let source = sources[state.id] else { return nil }
        let base = source.upgradeCommand(items)
        let command: String
        if state.requiresAdmin {
            if credential.hasPassword {
                // Feed the Keychain-stored password straight into `sudo -S` via a
                // here-string; `-p ''` silences sudo's own prompt. The plaintext
                // is fetched at runtime and never written into the script.
                command = "sudo -S -p '' \(base) <<< \"$(\(credential.shellRetrieval))\""
            } else {
                command = "sudo \(base)"
            }
        } else {
            command = base
        }
        return UpgradeHandoff.Job(label: state.displayName, command: command)
    }

    /// The command a source's upgrade would run, without running it.
    ///
    /// Exists so the elevation decision — which is the sharpest string this app
    /// composes — can be asserted rather than eyeballed in a terminal window.
    func previewUpgradeCommand(sourceID: String, items: [OutdatedItem] = []) -> String? {
        guard let state = states.first(where: { $0.id == sourceID }) else { return nil }
        return job(for: state, items: items)?.command
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
