import XCTest

@testable import UpdateBar

private struct FakeSource: UpdateSource {
    let id: String
    let displayName: String
    let iconSystemName = "circle"
    let items: [OutdatedItem]

    func isAvailable() async -> Bool { true }
    func checkOutdated() async throws -> [OutdatedItem] { items }
    func upgradeCommand(_ items: [OutdatedItem]) -> String { "echo \(id)" }
}

private func item(_ name: String) -> OutdatedItem {
    OutdatedItem(identifier: name, name: name, currentVersion: "1", latestVersion: "2")
}

@MainActor
private final class RecordingNotifier: UpdateNotifier {
    var posted: [(count: Int, sample: [String])] = []
    func requestAuthorization() {}
    func notifyNewUpdates(count: Int, sample: [String]) { posted.append((count, sample)) }
}

@MainActor
private final class FakePreferences: SourcePreferences {
    var disabled: Set<String> = []
    var refreshIntervalHours = 0  // no timer in tests
    var refreshOnOpen = true
    var notifyOnNewUpdates = true
    func isEnabled(_ sourceID: String) -> Bool { !disabled.contains(sourceID) }
}

private struct FakeCredential: PrivilegedCredential {
    let hasPassword: Bool
    var shellRetrieval: String { "echo stub-password" }
}

@MainActor
final class CoordinatorTests: XCTestCase {

    private func coordinator(
        _ sources: [any UpdateSource],
        prefs: FakePreferences = FakePreferences(),
        notifier: RecordingNotifier = RecordingNotifier(),
        credential: FakeCredential = FakeCredential(hasPassword: false)
    ) -> UpdateCoordinator {
        UpdateCoordinator(
            sources: sources, preferences: prefs, notifier: notifier, credential: credential
        )
    }

    /// The admin path builds the sharpest command in the app and previously
    /// could not be tested at all, because reaching it meant touching the real
    /// Keychain.
    func testAdminUpgradePipesTheStoredPasswordIntoSudo() async {
        let subject = coordinator(
            [AdminSource(id: "mas")], credential: FakeCredential(hasPassword: true)
        )
        await subject.bootstrap()
        let command = subject.previewUpgradeCommand(sourceID: "mas")

        XCTAssertEqual(command, "sudo -S -p '' mas upgrade <<< \"$(echo stub-password)\"")
    }

    /// Without a stored password `sudo` must prompt in the terminal — which is
    /// also the path Touch ID takes over.
    func testAdminUpgradeWithoutAPasswordJustUsesSudo() async {
        let subject = coordinator(
            [AdminSource(id: "mas")], credential: FakeCredential(hasPassword: false)
        )
        await subject.bootstrap()
        XCTAssertEqual(subject.previewUpgradeCommand(sourceID: "mas"), "sudo mas upgrade")
    }

    func testNonAdminUpgradeIsNotElevated() async {
        let subject = coordinator([FakeSource(id: "a", displayName: "A", items: [])])
        await subject.bootstrap()
        XCTAssertEqual(subject.previewUpgradeCommand(sourceID: "a"), "echo a")
    }

    func testConstructibleWithFakeSources() async {
        let subject = coordinator([FakeSource(id: "a", displayName: "A", items: [item("one")])])
        await subject.bootstrap()
        XCTAssertEqual(subject.totalCount, 1)
    }

    /// The rule the code already intends and nothing held it to: a first
    /// population is not "new updates", or every launch would notify.
    func testFirstPopulationIsSilent() async {
        let notifier = RecordingNotifier()
        let subject = coordinator(
            [FakeSource(id: "a", displayName: "A", items: [item("one"), item("two")])],
            notifier: notifier
        )
        await subject.bootstrap()
        XCTAssertTrue(notifier.posted.isEmpty)
    }

    func testAPackageAppearingLaterNotifiesOnce() async {
        let notifier = RecordingNotifier()
        let source = MutableSource(id: "a", items: [item("one")])
        let subject = coordinator([source], notifier: notifier)
        await subject.bootstrap()

        source.items = [item("one"), item("two")]
        await subject.refreshAll()

        XCTAssertEqual(notifier.posted.count, 1)
        XCTAssertEqual(notifier.posted.first?.count, 1)
        XCTAssertEqual(notifier.posted.first?.sample, ["two"])
    }

    func testUnchangedPackagesNotifyNothing() async {
        let notifier = RecordingNotifier()
        let source = MutableSource(id: "a", items: [item("one")])
        let subject = coordinator([source], notifier: notifier)
        await subject.bootstrap()
        await subject.refreshAll()
        XCTAssertTrue(notifier.posted.isEmpty)
    }

    /// Two sources can legitimately offer a package of the same name; the diff
    /// is keyed per source, so one appearing must not mask the other.
    func testSameNameInTwoSourcesCountsTwice() async {
        let notifier = RecordingNotifier()
        let a = MutableSource(id: "a", items: [])
        let b = MutableSource(id: "b", items: [])
        let subject = coordinator([a, b], notifier: notifier)
        await subject.bootstrap()

        a.items = [item("shared")]
        b.items = [item("shared")]
        await subject.refreshAll()
        XCTAssertEqual(notifier.posted.first?.count, 2)
    }

    /// Regression: a machine that is fully up to date on launch produces an
    /// empty first refresh. Inferring "first population" from the seen-set being
    /// empty meant the next refresh looked like another first, and the first real
    /// update after a clean start was never announced.
    func testAnEmptyFirstRefreshStillNotifiesOnTheNextOne() async {
        let notifier = RecordingNotifier()
        let source = MutableSource(id: "a", items: [])
        let subject = coordinator([source], notifier: notifier)
        await subject.bootstrap()
        XCTAssertTrue(notifier.posted.isEmpty, "nothing outstanding, nothing to say")

        source.items = [item("one")]
        await subject.refreshAll()
        XCTAssertEqual(notifier.posted.count, 1, "the first real update must be announced")
    }

    func testDisabledSourceCountsForNothing() async {
        let notifier = RecordingNotifier()
        let prefs = FakePreferences()
        prefs.disabled = ["b"]
        let subject = coordinator(
            [
                FakeSource(id: "a", displayName: "A", items: [item("one")]),
                FakeSource(id: "b", displayName: "B", items: [item("two"), item("three")])
            ],
            prefs: prefs, notifier: notifier
        )
        await subject.bootstrap()
        XCTAssertEqual(subject.totalCount, 1, "the disabled source is not in the badge")
        XCTAssertEqual(subject.visibleStates.map(\.id), ["a"])
    }

    func testNotificationsOffStaysSilent() async {
        let notifier = RecordingNotifier()
        let prefs = FakePreferences()
        prefs.notifyOnNewUpdates = false
        let source = MutableSource(id: "a", items: [])
        let subject = coordinator([source], prefs: prefs, notifier: notifier)
        await subject.bootstrap()
        source.items = [item("one")]
        await subject.refreshAll()
        XCTAssertTrue(notifier.posted.isEmpty)
    }

    // MARK: Refresh when the menu opens

    /// Opening the menu is the only moment the counts are read, so a stale list
    /// must not be what the user is shown.
    func testOpeningTheMenuRefreshesWhenTheCountsAreStale() async {
        let source = CountingSource()
        let subject = UpdateCoordinator(
            sources: [source], preferences: FakePreferences(),
            notifier: RecordingNotifier(), credential: FakeCredential(hasPassword: false),
            stalenessWindow: 0
        )
        await subject.bootstrap()
        XCTAssertEqual(source.checks, 1, "bootstrap does the first check")

        await subject.refreshIfStale()

        XCTAssertEqual(source.checks, 2)
    }

    /// The checks shell out and are slow, so toggling the menu a few times in a
    /// row must not start one each time.
    func testOpeningTheMenuAgainStraightAwayDoesNotRefresh() async {
        let source = CountingSource()
        let subject = UpdateCoordinator(
            sources: [source], preferences: FakePreferences(),
            notifier: RecordingNotifier(), credential: FakeCredential(hasPassword: false)
        )
        await subject.bootstrap()

        await subject.refreshIfStale()
        await subject.refreshIfStale()

        XCTAssertEqual(source.checks, 1, "still just the bootstrap check")
    }

    /// The setting exists for people on metered or slow machines, so switching
    /// it off has to actually stop the check — not just widen the window.
    func testOpeningTheMenuDoesNotRefreshWhenTheSettingIsOff() async {
        let source = CountingSource()
        let prefs = FakePreferences()
        prefs.refreshOnOpen = false
        let subject = UpdateCoordinator(
            sources: [source], preferences: prefs,
            notifier: RecordingNotifier(), credential: FakeCredential(hasPassword: false),
            stalenessWindow: 0
        )
        await subject.bootstrap()

        await subject.refreshIfStale()

        XCTAssertEqual(source.checks, 1, "still just the bootstrap check")
    }

    /// Opening the menu while launch is still probing would otherwise stamp
    /// `lastRefresh` against an empty source list and suppress the real first
    /// refresh.
    func testOpeningTheMenuBeforeBootstrapDoesNothing() async {
        let source = CountingSource()
        let subject = UpdateCoordinator(
            sources: [source], preferences: FakePreferences(),
            notifier: RecordingNotifier(), credential: FakeCredential(hasPassword: false),
            stalenessWindow: 0
        )

        await subject.refreshIfStale()

        XCTAssertEqual(source.checks, 0)
        XCTAssertNil(subject.lastRefresh)
    }

}

/// A source whose answer can change between refreshes.
private final class MutableSource: UpdateSource, @unchecked Sendable {
    let id: String
    var items: [OutdatedItem]
    var displayName: String { id.uppercased() }
    let iconSystemName = "circle"

    init(id: String, items: [OutdatedItem]) {
        self.id = id
        self.items = items
    }

    func isAvailable() async -> Bool { true }
    func checkOutdated() async throws -> [OutdatedItem] { items }
    func upgradeCommand(_ items: [OutdatedItem]) -> String { "echo \(id)" }
}

/// Counts how often it was actually checked, so "did opening the menu start a
/// refresh?" can be asserted rather than inferred from a timestamp.
private final class CountingSource: UpdateSource, @unchecked Sendable {
    let id = "counting"
    let displayName = "Counting"
    let iconSystemName = "circle"
    private let lock = NSLock()
    private var value = 0

    var checks: Int { lock.withLock { value } }

    func isAvailable() async -> Bool { true }
    func checkOutdated() async throws -> [OutdatedItem] {
        lock.withLock { value += 1 }
        return []
    }
    func upgradeCommand(_ items: [OutdatedItem]) -> String { "echo counting" }
}

/// A source that needs admin rights, so the coordinator wraps it in `sudo`.
private struct AdminSource: UpdateSource {
    let id: String
    var displayName: String { id.uppercased() }
    let iconSystemName = "circle"
    func requiresAdmin() async -> Bool { true }

    func isAvailable() async -> Bool { true }
    func checkOutdated() async throws -> [OutdatedItem] { [] }
    func upgradeCommand(_ items: [OutdatedItem]) -> String { "\(id) upgrade" }
}
