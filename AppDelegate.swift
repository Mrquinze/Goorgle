import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: SearchPanel!
    private var hotKeyMonitor: HotKeyMonitor!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Goorgle")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        panel = SearchPanel(onDismiss: { [weak self] in self?.hidePanel() })

        // ⌃⌘Space — summons the panel from anywhere, not just via the menu bar icon.
        // Note: this is also macOS's default Character Viewer (emoji picker) shortcut.
        hotKeyMonitor = HotKeyMonitor(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | controlKey)
        ) { [weak self] in
            self?.togglePanel()
        }
    }

    @objc private func handleStatusItemClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = LoginItemManager.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Goorgle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Temporarily attach the menu so performClick shows it like a real right-click,
        // then detach so left-clicks go back to toggling the panel instead of a menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItemManager.toggle()
    }

    private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else if let button = statusItem.button {
            panel.show(relativeTo: button)
        }
    }

    private func hidePanel() {
        panel.orderOut(nil)
    }
}
