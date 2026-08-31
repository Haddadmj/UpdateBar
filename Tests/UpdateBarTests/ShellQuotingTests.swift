import XCTest

@testable import UpdateBar

/// Identifiers come from parsing third-party CLI output and end up in a
/// `.command` file that a terminal executes. Registry names are constrained
/// enough that nothing exploitable exists today — which is an argument about
/// today's inputs, not about the code.
final class ShellQuotingTests: XCTestCase {

    func testQuotingWrapsAndEscapes() {
        XCTAssertEqual(ShellQuoting.singleQuoted("ripgrep"), "'ripgrep'")
        XCTAssertEqual(ShellQuoting.singleQuoted("it's"), #"'it'\''s'"#)
        XCTAssertEqual(ShellQuoting.singleQuoted(""), "''")
    }

    /// Everything outside single quotes, which is the only part a shell reads as
    /// syntax. Whatever survives there is what could run.
    private func outsideQuotes(_ command: String) -> String {
        var out = ""
        var inside = false
        for character in command {
            if character == "'" { inside.toggle(); continue }
            if !inside { out.append(character) }
        }
        return out
    }

    /// The shape that matters: a name carrying a separator must upgrade that one
    /// package and run nothing else.
    func testIdentifierWithASeparatorCannotRunASecondCommand() {
        let nasty = OutdatedItem(
            identifier: "pkg; rm -rf ~", name: "pkg", currentVersion: "1", latestVersion: "2"
        )
        let runner = ProcessRunner()
        let commands = [
            "homebrew": HomebrewSource(runner: runner).upgradeCommand([nasty]),
            "npm": NpmSource(runner: runner).upgradeCommand([nasty]),
            "pipx": PipxSource(runner: runner).upgradeCommand([nasty]),
            "cargo": CargoSource(runner: runner).upgradeCommand([nasty]),
            "gem": GemSource(runner: runner).upgradeCommand([nasty]),
            "mas": MasSource(runner: runner).upgradeCommand([nasty]),
            "softwareupdate": SoftwareUpdateSource(runner: runner).upgradeCommand([nasty])
        ]
        for (name, command) in commands {
            let bare = outsideQuotes(command)
            XCTAssertFalse(bare.contains(";"), "\(name) leaves a separator loose: \(command)")
            XCTAssertFalse(bare.contains("rm"), "\(name) leaves a command loose: \(command)")
        }
    }

    /// pipx chains with `&&`, so its own separators are expected outside quotes —
    /// what must not appear is one that came from an identifier.
    func testPipxChainsItsOwnCommandsOnly() {
        let items = [
            OutdatedItem(identifier: "black", name: "black", currentVersion: "1", latestVersion: "2"),
            OutdatedItem(identifier: "ruff; whoami", name: "ruff", currentVersion: "1", latestVersion: "2")
        ]
        let command = PipxSource(runner: ProcessRunner()).upgradeCommand(items)
        XCTAssertEqual(command.components(separatedBy: "&&").count, 2, "one && per package, none injected")
        XCTAssertFalse(outsideQuotes(command).contains("whoami"))
    }

    /// Quoting must not change the command for ordinary names beyond the quotes
    /// themselves — the upgrade still has to work.
    func testOrdinaryNamesStillUpgrade() {
        let items = [
            OutdatedItem(identifier: "ripgrep", name: "ripgrep", currentVersion: "1", latestVersion: "2"),
            OutdatedItem(identifier: "jq", name: "jq", currentVersion: "1", latestVersion: "2")
        ]
        let command = HomebrewSource(runner: ProcessRunner()).upgradeCommand(items)
        XCTAssertTrue(command.hasPrefix("brew upgrade "))
        XCTAssertTrue(command.contains("'ripgrep'"))
        XCTAssertTrue(command.contains("'jq'"))
    }

    /// Empty means "everything", and that path takes no identifiers at all.
    func testEmptySelectionUpgradesEverything() {
        XCTAssertEqual(HomebrewSource(runner: ProcessRunner()).upgradeCommand([]), "brew upgrade")
        XCTAssertEqual(NpmSource(runner: ProcessRunner()).upgradeCommand([]), "npm update -g")
    }
}
