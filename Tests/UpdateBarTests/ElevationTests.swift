import XCTest

@testable import UpdateBar

/// `sudo gem update` against a Homebrew or rbenv prefix writes root-owned files
/// into a user-owned tree. Nothing fails at the time; what fails is every later
/// user-level gem install, and `brew doctor` starts reporting files that have to
/// be chowned back by hand.
final class ElevationTests: XCTestCase {

    private func runner(gemdir: String, succeeds: Bool = true) -> StubRunner {
        StubRunner([
            ("gem environment gemdir",
             .success(ProcessResult(
                stdout: gemdir, stderr: "", exitCode: succeeds ? 0 : 1)))
        ])
    }

    func testAUserWritableGemHomeNeedsNoSudo() async {
        // The temporary directory stands in for /opt/homebrew — what matters is
        // that this user can write to it.
        let writable = NSTemporaryDirectory()
        let needsSudo = await RubyEnvironment.requiresSudo(runner: runner(gemdir: writable))
        XCTAssertFalse(needsSudo)
    }

    func testAnUnwritableGemHomeStillNeedsSudo() async {
        let needsSudo = await RubyEnvironment.requiresSudo(
            runner: runner(gemdir: "/System/Library/Ruby/Gems/2.6.0")
        )
        XCTAssertTrue(needsSudo)
    }

    /// Unknown means sudo. Guessing "no root needed" and being wrong makes the
    /// upgrade fail; guessing "root needed" and being wrong asks for a password
    /// that was not required. Only one of those is recoverable.
    func testAnUndeterminableGemHomeFallsBackToSudo() async {
        let failing = await RubyEnvironment.requiresSudo(
            runner: runner(gemdir: "", succeeds: false)
        )
        XCTAssertTrue(failing)

        let empty = await RubyEnvironment.requiresSudo(runner: runner(gemdir: "  \n"))
        XCTAssertTrue(empty)
    }

    func testGemSourceFollowsTheGemHome() async {
        let homebrewish = await GemSource(runner: runner(gemdir: NSTemporaryDirectory()))
            .requiresAdmin()
        XCTAssertFalse(homebrewish)

        let systemish = await GemSource(runner: runner(gemdir: "/System/Library/Ruby/Gems/2.6.0"))
            .requiresAdmin()
        XCTAssertTrue(systemish)
    }

    /// These two are root's business whatever else is installed.
    func testMasAndSoftwareUpdateAlwaysElevate() async {
        let runner = StubRunner.succeeding("")
        let mas = await MasSource(runner: runner).requiresAdmin()
        let softwareUpdate = await SoftwareUpdateSource(runner: runner).requiresAdmin()
        XCTAssertTrue(mas)
        XCTAssertTrue(softwareUpdate)
    }

    func testOrdinarySourcesDoNotElevate() async {
        let runner = StubRunner.succeeding("")
        let brew = await HomebrewSource(runner: runner).requiresAdmin()
        let npm = await NpmSource(runner: runner).requiresAdmin()
        let cargo = await CargoSource(runner: runner).requiresAdmin()
        XCTAssertFalse(brew)
        XCTAssertFalse(npm)
        XCTAssertFalse(cargo)
    }
}
