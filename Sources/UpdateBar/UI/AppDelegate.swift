import AppKit
import Observation
import SwiftUI

/// Owns the status-bar item. Left-click toggles a rich popover; right-click shows a
/// simple context menu (Check Updates / Update All / Settings / Quit). Using a custom
/// `NSStatusItem` (instead of SwiftUI `MenuBarExtra`) is what makes a right-click menu
/// and a reliably-activating Settings window possible in an accessory app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let coordinator = UpdateCoordinator()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateButton()

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(coordinator: coordinator, onOpenSettings: { [weak self] in
                self?.openSettings()
            })
        )

        Task {
            await coordinator.bootstrap()
            observeBadge()
        }
    }

    // MARK: Badge

    /// Keep the menu-bar icon/count in sync with the coordinator's observable state.
    private func observeBadge() {
        withObservationTracking {
            updateButton()
        } onChange: {
            Task { @MainActor in self.observeBadge() }
        }
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }
        let count = coordinator.totalCount
        let symbol = count > 0 ? "arrow.down.circle.fill" : "checkmark.circle"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "UpdateBar")
        button.title = count > 0 ? " \(count)" : ""
    }

    // MARK: Click handling

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        // Close the popover first so its arrow can't bleed through behind the menu.
        if popover.isShown { popover.performClose(nil) }

        let menu = NSMenu()
        menu.delegate = self
        func add(_ title: String, _ action: Selector, key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        add("Check for Updates", #selector(menuCheckUpdates))
        add("Upgrade All", #selector(menuUpgradeAll))
        menu.addItem(.separator())
        add("Settings…", #selector(menuOpenSettings), key: ",")
        menu.addItem(.separator())
        add("Quit UpdateBar", #selector(menuQuit), key: "q")

        // Canonical status-item menu: attach it, synthesize a click so AppKit renders
        // and positions it as a proper menu-bar dropdown, then detach so left-click
        // keeps toggling the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    /// Detach the transient context menu once it closes so left-click still opens the popover.
    nonisolated func menuDidClose(_ menu: NSMenu) {
        Task { @MainActor in statusItem.menu = nil }
    }

    // MARK: Menu actions

    @objc private func menuCheckUpdates() { Task { await coordinator.refreshAll() } }
    @objc private func menuUpgradeAll() { Task { await coordinator.upgradeEverything() } }
    @objc private func menuOpenSettings() { openSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: Settings window

    func openSettings() {
        if popover.isShown { popover.performClose(nil) }
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(coordinator: coordinator))
            let window = NSWindow(contentViewController: hosting)
            window.title = "UpdateBar Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
