import Foundation
import ServiceManagement

/// Wraps `SMAppService` to register/unregister UpdateBar as a login item.
/// Only works when running from a proper `.app` bundle (not the raw SwiftPM binary).
enum LoginItemManager {

    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the achieved state (true = will launch at login), or throws.
    @discardableResult
    static func setEnabled(_ enabled: Bool) throws -> Bool {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
        return SMAppService.mainApp.status == .enabled
    }
}
