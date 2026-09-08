import AppKit
import SwiftUI

/// A plain, normal-level NSWindow hosting SettingsView — separate from
/// SearchPanel's borderless/non-activating style since this one should
/// behave like an ordinary closable, activatable preferences window.
final class PreferencesWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Goorgle Preferences"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
