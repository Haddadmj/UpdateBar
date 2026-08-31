import XCTest

@testable import UpdateBar

/// Replays canned CLI output and records what was asked for.
///
/// The point of the seam: a source's real path — the command it builds, the JSON
/// it extracts, the decode, the error mapping — runs here with no `brew`, no
/// network and no machine state.
final actor StubRunner: CommandRunner {
    private var responses: [(match: String, result: Result<ProcessResult, Error>)]
    private(set) var commands: [String] = []

    init(_ responses: [(String, Result<ProcessResult, Error>)]) {
        self.responses = responses.map { (match: $0.0, result: $0.1) }
    }

    /// Convenience: one successful stdout for anything asked.
    static func succeeding(_ stdout: String) -> StubRunner {
        StubRunner([("", .success(ProcessResult(stdout: stdout, stderr: "", exitCode: 0)))])
    }

    func runShell(_ command: String, timeout: TimeInterval) async throws -> ProcessResult {
        commands.append(command)
        // An empty pattern means "anything": `"abc".contains("")` is false in
        // Swift, so matching on it alone silently fell through to the default
        // below — which returned a *successful* empty result, and quietly made
        // every stub built that way a no-op.
        guard let match = responses.first(where: { $0.match.isEmpty || command.contains($0.match) })
        else {
            return ProcessResult(stdout: "", stderr: "", exitCode: 0)
        }
        return try match.result.get()
    }
}

private let brewJSON = """
{"formulae":[{"name":"ripgrep","installed_versions":["14.1.0"],"current_version":"14.1.1"}],
 "casks":[{"name":"wezterm","installed_versions":["20240203"],"current_version":"20260101"}]}
"""

final class SourcePipelineTests: XCTestCase {

    func testHomebrewRunsItsWholePathWithoutBrewInstalled() async throws {
        let runner = StubRunner([("outdated", .success(ProcessResult(stdout: brewJSON, stderr: "", exitCode: 0)))])
        let items = try await HomebrewSource(runner: runner).checkOutdated()

        XCTAssertEqual(items.count, 2, "formulae and casks both land")
        let rg = items.first { $0.identifier == "ripgrep" }
        XCTAssertEqual(rg?.currentVersion, "14.1.0")
        XCTAssertEqual(rg?.latestVersion, "14.1.1")
        XCTAssertNotNil(items.first { $0.identifier == "wezterm" }, "casks are not dropped")
    }

    /// The command a source builds was previously unassertable.
    func testHomebrewAsksForMachineReadableOutput() async throws {
        let runner = StubRunner([("outdated", .success(ProcessResult(stdout: brewJSON, stderr: "", exitCode: 0)))])
        _ = try await HomebrewSource(runner: runner).checkOutdated()

        let commands = await runner.commands
        XCTAssertTrue(commands.contains { $0.contains("brew outdated --json=v2") })
        XCTAssertTrue(commands.contains { $0.contains("brew update --quiet") }, "metadata refreshed first")
    }

    /// A network hiccup during `brew update` must not fail the check — the
    /// comment in the source says so, and nothing held it to that.
    func testFailingUpdateStillReportsOutdated() async throws {
        let runner = StubRunner([
            ("update", .failure(ProcessRunnerError.timedOut(command: "brew update"))),
            ("outdated", .success(ProcessResult(stdout: brewJSON, stderr: "", exitCode: 0)))
        ])
        let items = try await HomebrewSource(runner: runner).checkOutdated()
        XCTAssertEqual(items.count, 2)
    }

    func testMalformedJSONSurfacesAsAParseError() async {
        let runner = StubRunner([("outdated", .success(ProcessResult(stdout: "not json", stderr: "brew: broken", exitCode: 1)))])
        do {
            _ = try await HomebrewSource(runner: runner).checkOutdated()
            XCTFail("expected a parse error")
        } catch let error as SourceError {
            guard case let .parse(name, detail) = error else { return XCTFail("wrong case") }
            XCTAssertEqual(name, "Homebrew")
            XCTAssertTrue(detail.contains("broken"), "stderr explains it, not the empty stdout")
        } catch {
            XCTFail("expected SourceError, got \(error)")
        }
    }

    func testTimeoutPropagatesRatherThanReportingNoUpdates() async {
        let runner = StubRunner([("outdated", .failure(ProcessRunnerError.timedOut(command: "brew outdated")))])
        do {
            _ = try await HomebrewSource(runner: runner).checkOutdated()
            XCTFail("a timeout is not an empty update list")
        } catch is ProcessRunnerError {
            // expected
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    /// This previously fired an unawaited Task and asserted nothing, so it could
    /// not fail. It now checks the probe actually runs and what it asks.
    func testAvailabilityProbeUsesCommandV() async {
        let runner = StubRunner.succeeding("/opt/homebrew/bin/brew")
        let available = await HomebrewSource(runner: runner).isAvailable()

        XCTAssertTrue(available)
        let commands = await runner.commands
        XCTAssertEqual(commands, ["command -v brew"], "the exact command, not a substring")
    }

    func testAvailabilityIsFalseWhenTheToolIsAbsent() async {
        let runner = StubRunner([("", .success(ProcessResult(stdout: "", stderr: "", exitCode: 1)))])
        let available = await HomebrewSource(runner: runner).isAvailable()
        XCTAssertFalse(available)
    }
}
