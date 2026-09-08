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

    /// Applies an explicit desired state and reports whether it stuck.
    ///
    /// Takes the wanted value rather than flipping the current one: the caller
    /// is a SwiftUI toggle that has *already* moved, so a self-flipping
    /// `toggle()` could read a status that disagrees with the switch and undo
    /// the user's click. Returning the real outcome lets the toggle snap back
    /// when registration silently fails (the DerivedData case below).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Goorgle: failed to \(enabled ? "register" : "unregister") login item — \(error)")
        }
        return isEnabled
    }
}
