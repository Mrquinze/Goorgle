import SwiftUI

@main
struct GoorgleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No real window needed — AppDelegate drives an NSStatusItem + NSPanel.
        // A Scene is still required by the App protocol, so this stays empty.
        Settings {
            EmptyView()
        }
        // A `Settings` scene puts "Settings…" (⌘,) in the app menu, which
        // opened this empty scene — a blank window with nothing in it. Point
        // that menu item at the real Preferences window instead, so there's
        // exactly one preferences UI however it's reached.
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Preferences…") { AppDelegate.shared?.showPreferences() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
