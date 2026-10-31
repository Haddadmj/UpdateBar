import AppKit
import XCTest

@testable import UpdateBar

/// An accessory app never draws its main menu, so losing an item here is silent:
/// the shortcut just stops working. Paste is the one that matters most — it is how
/// a password gets into the admin password field.
@MainActor
final class MainMenuTests: XCTestCase {

    func testKeepsShortcutsThatOnlyWorkThroughTheMainMenu() {
        let items = AppDelegate().makeMainMenu().items.flatMap { $0.submenu?.items ?? [] }
        let bound = Set(items.compactMap { item in item.action.map { "\($0) \(item.keyEquivalent)" } })

        XCTAssertTrue(bound.contains("cut: x"))
        XCTAssertTrue(bound.contains("copy: c"))
        XCTAssertTrue(bound.contains("paste: v"))
        XCTAssertTrue(bound.contains("selectAll: a"))
        XCTAssertTrue(bound.contains("undo: z"))
        XCTAssertTrue(bound.contains("performClose: w"))
        XCTAssertTrue(bound.contains("menuOpenSettings ,"))
        XCTAssertTrue(bound.contains("menuQuit q"))
    }
}
