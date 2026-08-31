import XCTest

@testable import UpdateBar

/// The rule is tested; the machine's `/etc` is not. Same split as ticket 01 —
/// what a file says is a property of its text, and reading `/etc/pam.d` in a
/// test would make the suite depend on how this Mac happens to be configured.
final class SudoAuthenticationTests: XCTestCase {

    /// Apple's shipped template, verbatim. Its `pam_tid` line is commented out,
    /// which is the state of every machine nobody has configured.
    func testShippedTemplateReadsAsOff() {
        let template = """
        # sudo_local: local config file which survives system update and is included for sudo
        # uncomment following line to enable Touch ID for sudo
        #auth       sufficient     pam_tid.so
        """
        XCTAssertFalse(SudoAuthentication.enablesTouchID(pamConfiguration: template))
    }

    func testUncommentedLineReadsAsOn() {
        XCTAssertTrue(SudoAuthentication.enablesTouchID(
            pamConfiguration: "auth       sufficient     pam_tid.so"
        ))
    }

    func testLeadingWhitespaceIsTolerated() {
        XCTAssertTrue(SudoAuthentication.enablesTouchID(
            pamConfiguration: "\t  auth sufficient pam_tid.so\n"
        ))
    }

    /// The tmux fix people add above it must not confuse the reading.
    func testPamReattachAboveItStillReadsAsOn() {
        let config = """
        auth       optional       /opt/homebrew/lib/pam/pam_reattach.so
        auth       sufficient     pam_tid.so
        """
        XCTAssertTrue(SudoAuthentication.enablesTouchID(pamConfiguration: config))
    }

    /// Someone writing themselves a note is not someone enabling Touch ID.
    func testMentionInsideACommentReadsAsOff() {
        let config = """
        # remember to add pam_tid.so here one day
        auth       sufficient     pam_smartcard.so
        """
        XCTAssertFalse(SudoAuthentication.enablesTouchID(pamConfiguration: config))
    }

    /// A trailing comment on a live line does not disable it.
    func testTrailingCommentOnALiveLine() {
        XCTAssertTrue(SudoAuthentication.enablesTouchID(
            pamConfiguration: "auth sufficient pam_tid.so # touch id for sudo"
        ))
    }

    /// Only `auth` decides authentication. A module named in another stack is
    /// not what raises the prompt.
    func testNonAuthLineDoesNotCount() {
        XCTAssertFalse(SudoAuthentication.enablesTouchID(
            pamConfiguration: "session optional pam_tid.so"
        ))
    }

    /// The file read itself, not just the rule — via a temporary file, so the
    /// suite still says nothing about how this Mac is configured.
    func testReadsAFileFromDisk() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sudo_local_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        try "#auth       sufficient     pam_tid.so\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertFalse(SudoAuthentication.isEnabled(at: url.path))

        try "auth       sufficient     pam_tid.so\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(SudoAuthentication.isEnabled(at: url.path))
    }

    /// The common case: no such file, because it has never been created.
    func testEmptyOrMissingReadsAsOff() {
        XCTAssertFalse(SudoAuthentication.enablesTouchID(pamConfiguration: ""))
        XCTAssertFalse(SudoAuthentication.isEnabled(at: "/nonexistent/sudo_local"))
    }
}
