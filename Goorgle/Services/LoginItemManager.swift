import Foundation
import ServiceManagement

/// Thin wrapper around SMAppService so the menu bar's "Launch at Login"
/// checkbox doesn't need to send people to System Settings by hand.
///
/// Note: registration only succeeds for a properly signed build running
/// from a stable location (e.g. /Applications) — a raw DerivedData debug
/// build often fails silently or throws. Archive/export before relying on it.
enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Goorgle: failed to toggle login item — \(error)")
        }
    }
}
