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
    }
}
