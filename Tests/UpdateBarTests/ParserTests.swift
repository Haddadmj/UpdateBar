import XCTest
@testable import UpdateBar

/// Parser tests driven by real CLI output captured on the dev machine.
final class ParserTests: XCTestCase {

    func testMasOutdatedParsing() {
        let sample = """
        1352778147  Bitwarden    (2026.5.0 -> 2026.6.1)
         361304891  Numbers      (15.2.1   -> 15.3)
         310633997  WhatsApp     (26.22.77 -> 26.26.73)
        1295203466  Windows App  (11.3.5   -> 11.3.7)
         497799835  Xcode        (26.5     -> 26.6)
        """
        let items = MasSource.parse(sample)
        XCTAssertEqual(items.count, 5)
        let bitwarden = items.first { $0.identifier == "1352778147" }
        XCTAssertEqual(bitwarden?.name, "Bitwarden")
        XCTAssertEqual(bitwarden?.currentVersion, "2026.5.0")
        XCTAssertEqual(bitwarden?.latestVersion, "2026.6.1")
        // Multi-word app name preserved.
        XCTAssertEqual(items.first { $0.identifier == "1295203466" }?.name, "Windows App")
    }

    func testGemOutdatedParsing() {
        let sample = """
        CFPropertyList (2.3.6 < 4.0.0)
        addressable (2.8.7 < 2.9.0)
        atomos (0.1.3 < 1.0.0)
        """
        let items = GemSource.parse(sample)
        XCTAssertEqual(items.count, 3)
        let addressable = items.first { $0.name == "addressable" }
        XCTAssertEqual(addressable?.currentVersion, "2.8.7")
        XCTAssertEqual(addressable?.latestVersion, "2.9.0")
    }

    func testRustupCheckParsing() {
        let sample = """
        stable-aarch64-apple-darwin - update available: 1.96.0 (ac68faa20 2026-05-25) -> 1.97.0 (2d8144b78 2026-07-07)
        1.90-aarch64-apple-darwin - up to date: 1.90.0 (1159e78c4 2025-09-14)
        """
        let items = RustupSource.parse(sample)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.identifier, "stable-aarch64-apple-darwin")
        XCTAssertEqual(items.first?.currentVersion, "1.96.0")
        XCTAssertEqual(items.first?.latestVersion, "1.97.0")
    }

    func testCargoInstallUpdateParsing() {
        let sample = """
        Package        Installed  Latest   Needs update
        cargo-update   v14.0.0    v14.1.0  Yes
        ripgrep        v14.1.1    v14.1.1  No
        """
        let items = CargoSource.parse(sample)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "cargo-update")
        XCTAssertEqual(items.first?.latestVersion, "v14.1.0")
    }

    func testUpgradeCommands() async {
        let runner = ProcessRunner()
        let label = OutdatedItem(identifier: "macOS Sequoia 15.6-24G84", name: "macOS Sequoia", currentVersion: nil, latestVersion: "15.6")

        // softwareupdate: specific label quoted; empty -> --all. Marked admin.
        let su = SoftwareUpdateSource(runner: runner)
        let suElevates = await su.requiresAdmin()
        XCTAssertTrue(suElevates)
        XCTAssertEqual(su.upgradeCommand([label]), "softwareupdate --install 'macOS Sequoia 15.6-24G84'")
        XCTAssertEqual(su.upgradeCommand([]), "softwareupdate --install --all")

        // gem: names quoted. Whether it elevates is an environment question now,
        // covered in ElevationTests.
        let gem = GemSource(runner: runner)
        XCTAssertEqual(
            gem.upgradeCommand([OutdatedItem(identifier: "bundler", name: "bundler", currentVersion: "1", latestVersion: "4")]),
            "gem update 'bundler'",
            "identifiers are quoted uniformly now, including the ordinary ones"
        )

        // mas: now admin (mas 7 needs root).
        let masElevates = await MasSource(runner: runner).requiresAdmin()
        XCTAssertTrue(masElevates)

        // homebrew: not admin; command has no sudo.
        let brew = HomebrewSource(runner: runner)
        let brewElevates = await brew.requiresAdmin()
        XCTAssertFalse(brewElevates)
        XCTAssertEqual(brew.upgradeCommand([]), "brew upgrade")
    }

    func testVersionComparison() {
        XCTAssertTrue(Version.isNewer("12.0.0", than: "10.8.2"))   // npm self-update
        XCTAssertTrue(Version.isNewer("4.0.16", than: "3.0.3.1"))  // rubygems self-update
        XCTAssertTrue(Version.isNewer("1.2.10", than: "1.2.9"))    // numeric, not lexical
        XCTAssertFalse(Version.isNewer("1.2.3", than: "1.2.3"))    // equal = no update
        XCTAssertFalse(Version.isNewer("1.0.0", than: "2.0.0"))    // older
    }

    func testJSONExtractorTolerheatesNoise() {
        // Interactive shell banner before the JSON payload must be stripped.
        let noisy = "Welcome to zsh!\nnvm loaded\n{\"formulae\":[],\"casks\":[]}\n"
        XCTAssertEqual(JSONExtractor.extract(noisy), "{\"formulae\":[],\"casks\":[]}")
        XCTAssertEqual(JSONExtractor.extract("garbage [1,2,3] trailing"), "[1,2,3]")
        XCTAssertNil(JSONExtractor.extract("no json here"))
    }

    func testSoftwareUpdateParsing() {
        let sample = """
        Software Update Tool

        Finding available software
        Software Update found the following new or updated software:
        * Label: macOS Sequoia 15.6-24G84
        \tTitle: macOS Sequoia, Version: 15.6, Size: 700000KiB, Recommended: YES, Action: restart,
        """
        let items = SoftwareUpdateSource.parse(sample)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "macOS Sequoia")
        XCTAssertEqual(items.first?.latestVersion, "15.6")
        XCTAssertEqual(items.first?.identifier, "macOS Sequoia 15.6-24G84")
    }
}

// MARK: - The sources that used to decode inline

/// Homebrew is the default source with the most complex payload — two arrays,
/// snake_case keys, `installed_versions` as a list — and it was the one with no
/// parse test.
final class RemainingParserTests: XCTestCase {

    func testHomebrewParsesFormulaeAndCasks() {
        let json = """
        {"formulae":[{"name":"ripgrep","installed_versions":["14.1.0"],"current_version":"14.1.1"}],
         "casks":[{"name":"wezterm","installed_versions":["20240203"],"current_version":"20260101"}]}
        """
        let items = HomebrewSource.parse(json)
        XCTAssertEqual(items?.count, 2)
        XCTAssertEqual(items?.first { $0.identifier == "ripgrep" }?.currentVersion, "14.1.0")
        XCTAssertEqual(items?.first { $0.identifier == "wezterm" }?.latestVersion, "20260101")
    }

    /// What a healthy machine returns. An empty payload is success, not failure.
    func testHomebrewEmptyPayloadIsNotAnError() {
        XCTAssertEqual(HomebrewSource.parse(#"{"formulae":[],"casks":[]}"#)?.count, 0)
    }

    func testHomebrewUndecodableYieldsNil() {
        XCTAssertNil(HomebrewSource.parse("Error: something went wrong"))
    }

    /// A formula with no recorded installed version still belongs on the list —
    /// dropping it would hide an available upgrade.
    func testHomebrewFormulaWithoutInstalledVersion() {
        let json = #"{"formulae":[{"name":"jq","installed_versions":[],"current_version":"1.8"}],"casks":[]}"#
        let items = HomebrewSource.parse(json)
        XCTAssertEqual(items?.count, 1)
        XCTAssertNil(items?.first?.currentVersion)
        XCTAssertEqual(items?.first?.latestVersion, "1.8")
    }

    func testNpmParsesKeyedObject() throws {
        let json = """
        {"typescript":{"current":"5.4.0","latest":"5.9.2"},
         "pnpm":{"current":"9.0.0","latest":"10.2.0"}}
        """
        let items = try XCTUnwrap(NpmSource.parse(json))
        XCTAssertEqual(items.map(\.identifier), ["pnpm", "typescript"], "sorted by name")
        XCTAssertEqual(items.first { $0.identifier == "typescript" }?.latestVersion, "5.9.2")
    }

    /// npm prints `{}` when everything is current, and nothing at all in some
    /// versions. Both mean "up to date", neither is an error.
    func testNpmEmptyShapes() {
        XCTAssertEqual(NpmSource.parse("{}")?.isEmpty, true)
        XCTAssertEqual(NpmSource.parse("")?.isEmpty, true)
    }

    /// A truncated or corrupt body is a failed check, not a healthy one. Reading
    /// it as "0 updates" is the worst possible answer: it looks like good news.
    func testNpmCorruptBodyIsNotUpToDate() {
        XCTAssertNil(NpmSource.parse(#"{"typescript":{"current":"5.4.0","lat"#))
        XCTAssertNil(NpmSource.parse("npm ERR! code E401"))
    }

    /// A package that is installed but has no published `latest` — npm omits the
    /// field rather than sending null.
    func testNpmPackageWithoutLatest() {
        let items = NpmSource.parse(#"{"private-tool":{"current":"1.0.0"}}"#)
        XCTAssertEqual(items?.count, 1)
        XCTAssertNil(items?.first?.latestVersion)
    }

    /// `gem search -r -e rubygems-update` prints `rubygems-update (4.0.16)`.
    func testSelfUpdateReadsTheGemSearchVersion() {
        XCTAssertEqual(SelfUpdateSource.parseGemSearchVersion("rubygems-update (4.0.16)\n"), "4.0.16")
        XCTAssertEqual(SelfUpdateSource.parseGemSearchVersion("rubygems-update (3.5.9, 3.5.8)"), "3.5.9")
        XCTAssertNil(SelfUpdateSource.parseGemSearchVersion("ERROR:  Could not find a valid gem"))
        XCTAssertNil(SelfUpdateSource.parseGemSearchVersion(""))
    }
}
