import Foundation
import Observation

/// The slice of settings the coordinator reads.
///
/// Narrower than `AppPreferences` on purpose: the coordinator has no business
/// with the login item or the terminal choice, and a test should not have to
/// supply them.
@MainActor
protocol SourcePreferences: AnyObject {
    var refreshIntervalHours: Int { get }
    var refreshOnOpen: Bool { get }
    var notifyOnNewUpdates: Bool { get }
    func isEnabled(_ sourceID: String) -> Bool
}

/// User-facing settings, persisted to `UserDefaults` and observed by the UI.
@MainActor
@Observable
final class AppPreferences: SourcePreferences {
    static let shared = AppPreferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let refreshIntervalHours = "refreshIntervalHours"
        static let refreshOnOpen = "refreshOnOpen"
        static let disabledSourceIDs = "disabledSourceIDs"
        static let notifyOnNewUpdates = "notifyOnNewUpdates"
        static let launchAtLogin = "launchAtLogin"
        static let terminalApp = "terminalApp"
    }

    /// Which terminal app runs upgrades, stored by name (e.g. "WezTerm").
    /// Empty or "Default" means the system handler for `.command` files.
    ///
    /// A name rather than a path so an existing setting survives the app moving;
    /// `TerminalApps.resolve` turns it back into a bundle URL at launch time and
    /// falls back to the system handler when it no longer resolves.
    var terminalApp: String {
        didSet { defaults.set(terminalApp, forKey: Key.terminalApp) }
    }

    /// How often to auto-refresh, in hours. 0 = manual only.
    var refreshIntervalHours: Int {
        didSet { defaults.set(refreshIntervalHours, forKey: Key.refreshIntervalHours) }
    }

    /// Re-check when the menu is opened, if the counts are more than a few
    /// minutes old. On by default: opening the menu is the moment the numbers
    /// are read, so that is when they should be worth reading.
    var refreshOnOpen: Bool {
        didSet { defaults.set(refreshOnOpen, forKey: Key.refreshOnOpen) }
    }

    /// Source ids the user has switched off (won't be checked or shown).
    var disabledSourceIDs: Set<String> {
        didSet { defaults.set(Array(disabledSourceIDs), forKey: Key.disabledSourceIDs) }
    }

    /// Post a notification when previously-unseen updates appear.
    var notifyOnNewUpdates: Bool {
        didSet { defaults.set(notifyOnNewUpdates, forKey: Key.notifyOnNewUpdates) }
    }

    /// Mirror of the SMAppService login-item registration state.
    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    private init() {
        // Sensible defaults on first launch.
        if defaults.object(forKey: Key.refreshIntervalHours) == nil {
            defaults.set(6, forKey: Key.refreshIntervalHours)
        }
        if defaults.object(forKey: Key.refreshOnOpen) == nil {
            defaults.set(true, forKey: Key.refreshOnOpen)
        }
        if defaults.object(forKey: Key.notifyOnNewUpdates) == nil {
            defaults.set(true, forKey: Key.notifyOnNewUpdates)
        }
        refreshIntervalHours = defaults.integer(forKey: Key.refreshIntervalHours)
        refreshOnOpen = defaults.bool(forKey: Key.refreshOnOpen)
        disabledSourceIDs = Set(defaults.stringArray(forKey: Key.disabledSourceIDs) ?? [])
        notifyOnNewUpdates = defaults.bool(forKey: Key.notifyOnNewUpdates)
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        terminalApp = defaults.string(forKey: Key.terminalApp) ?? "Default"
    }

    func isEnabled(_ sourceID: String) -> Bool { !disabledSourceIDs.contains(sourceID) }

    func setEnabled(_ enabled: Bool, for sourceID: String) {
        if enabled { disabledSourceIDs.remove(sourceID) }
        else { disabledSourceIDs.insert(sourceID) }
    }
}
