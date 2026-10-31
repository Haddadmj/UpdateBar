import XCTest

@testable import UpdateBar

/// Offering to update a tool macOS or Homebrew owns is how a user's install gets
/// damaged, and the app gives no sign of it until something else breaks later.
final class ToolOwnershipTests: XCTestCase {

    private func result(_ stdout: String) -> Result<ProcessResult, Error> {
        .success(ProcessResult(stdout: stdout, stderr: "", exitCode: 0))
    }

    /// A runner where gem resolves to `gemPath`, with a user-writable gem home and a
    /// newer RubyGems published.
    private func gemRunner(gemPath: String) -> StubRunner {
        StubRunner([
            ("readlink -f \"$(command -v gem)\"", result(gemPath + "\n")),
            ("readlink -f \"$(command -v npm)\"", result("")),
            ("gem environment gemdir", result(NSTemporaryDirectory())),
            ("gem --version", result("4.0.22\n")),
            ("gem search", result("rubygems-update (4.0.23)\n"))
        ])
    }

    func testClassifiesWhoOwnsATool() {
        XCTAssertEqual(ToolOwner.classify(path: "/usr/bin/gem"), .system)
        XCTAssertEqual(ToolOwner.classify(path: "/System/Library/Frameworks/Ruby/gem"), .system)
        XCTAssertEqual(ToolOwner.classify(path: "/Library/Developer/CommandLineTools/usr/bin/gem"), .system)
        XCTAssertEqual(ToolOwner.classify(path: "/opt/homebrew/Cellar/ruby/3.4/bin/gem"), .homebrew)
        XCTAssertEqual(ToolOwner.classify(path: "/usr/local/Cellar/ruby/3.4/bin/gem"), .homebrew)
        XCTAssertEqual(ToolOwner.classify(path: "/Users/me/.rbenv/versions/3.4/bin/gem"), .user)
        XCTAssertEqual(ToolOwner.classify(path: "/Users/me/.nvm/versions/node/v26/bin/npm"), .user)
    }

    func testAnUnresolvableToolHasNoOwner() async {
        let runner = StubRunner([("readlink", result("gem\n"))])
        let owner = await ToolOwner.of("gem", runner: runner)
        XCTAssertNil(owner, "an alias or function is not a path, so nothing is known about it")
    }

    func testHomebrewRubyGemsIsNotOffered() async throws {
        let source = SelfUpdateSource(runner: gemRunner(gemPath: "/opt/homebrew/Cellar/ruby/3.4/bin/gem"))
        let items = try await source.checkOutdated()
        XCTAssertFalse(items.contains { $0.identifier == "rubygems" })
    }

    func testSystemRubyGemsIsNotOffered() async throws {
        let source = SelfUpdateSource(runner: gemRunner(gemPath: "/usr/bin/gem"))
        let items = try await source.checkOutdated()
        XCTAssertFalse(items.contains { $0.identifier == "rubygems" })
    }

    func testTheUsersOwnRubyGemsIsOfferedAndNeverWithSudo() async throws {
        let source = SelfUpdateSource(runner: gemRunner(gemPath: "/Users/me/.rbenv/versions/3.4/bin/gem"))
        let items = try await source.checkOutdated()
        XCTAssertEqual(items.map(\.identifier), ["rubygems"])
        XCTAssertEqual(source.upgradeCommand(items), "gem update --system")
    }

    func testRubyGemsIsNotOfferedWhenItWouldTakeRoot() async throws {
        let runner = StubRunner([
            ("readlink -f \"$(command -v gem)\"", result("/usr/local/ruby/bin/gem\n")),
            ("readlink -f \"$(command -v npm)\"", result("")),
            ("gem environment gemdir", result("/System/Library/Ruby/Gems/2.6.0")),
            ("gem --version", result("4.0.22\n")),
            ("gem search", result("rubygems-update (4.0.23)\n"))
        ])
        let items = try await SelfUpdateSource(runner: runner).checkOutdated()
        XCTAssertTrue(items.isEmpty)
    }

    func testHeadlineNeverClaimsUpToDateWhenASourceFailed() {
        func headline(total: Int = 0, failed: Int = 0, enabled: Int = 3, checked: Bool = true) -> String {
            MenuHeadline.text(total: total, failed: failed, enabledSources: enabled, hasChecked: checked)
        }
        XCTAssertEqual(headline(), "All up to date")
        XCTAssertEqual(headline(failed: 1), "No updates found")
        XCTAssertEqual(headline(total: 1), "1 update")
        XCTAssertEqual(headline(total: 19, failed: 1), "19 updates")
        XCTAssertEqual(headline(checked: false), "Checking…")
        XCTAssertEqual(headline(enabled: 0), "No sources enabled")
    }
}
