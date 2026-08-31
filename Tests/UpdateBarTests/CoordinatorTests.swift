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
    var notifyOnNewUpdates = true
    func isEnabled(_ sourceID: String) -> Bool { !disabled.contains(sourceID) }
}

@MainActor
final class CoordinatorTests: XCTestCase {

    private func coordinator(
        _ sources: [any UpdateSource],
        prefs: FakePreferences = FakePreferences(),
        notifier: RecordingNotifier = RecordingNotifier()
    ) -> UpdateCoordinator {
        UpdateCoordinator(sources: sources, preferences: prefs, notifier: notifier)
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
