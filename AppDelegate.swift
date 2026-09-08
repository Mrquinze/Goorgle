import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static weak var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private var panel: SearchPanel!
    private var hotKeyMonitor: HotKeyMonitor!
    private var preferencesWindowController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        AppSettingsKeys.migrateLegacyFontDesignIfNeeded()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        panel = SearchPanel(onDismiss: { [weak self] in self?.hidePanel() })

        // ⌥⌘Space by default — summons the panel from anywhere, not just via
        // the menu bar icon. Rebindable in Preferences → General.
        hotKeyMonitor = HotKeyMonitor(shortcut: HotKeyShortcut.stored()) { [weak self] in
            self?.togglePanel()
        }

        applyMenuBarIconSettings()
        applyIconVisibilitySettings()

        HubMenuBar.start { [weak self] visible in
            self?.hubSuppressedMenuBarIcon = !visible
            self?.applyIconVisibilitySettings()
        }
    }

    /// Set from `HubMenuBar` while Yair's Apps is
    /// consolidating menu bar icons behind its own.
    ///
    /// Deliberately in-memory rather than a stored default: it's the hub's
    /// override, not the user's preference, so it must never overwrite the
    /// `showMenuBarIcon` toggle in Preferences. A relaunch clears it, and Goorgle
    /// asks the hub for the current state as soon as it's up again.
    private var hubSuppressedMenuBarIcon = false

    /// Applies the persisted menu bar / Dock icon visibility settings.
    /// Called at launch and whenever SettingsView's toggles change.
    func applyIconVisibilitySettings() {
        let defaults = UserDefaults.standard
        let showMenuBarIcon = defaults.object(forKey: AppSettingsKeys.showMenuBarIcon) as? Bool ?? true
        let showDockIcon = defaults.object(forKey: AppSettingsKeys.showDockIcon) as? Bool ?? false

        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        statusItem.isVisible = showMenuBarIcon && !hubSuppressedMenuBarIcon
    }

    /// Applies the picked menu bar glyph. Called at launch and whenever the
    /// Menu Bar Icon picker changes.
    func applyMenuBarIconSettings() {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: AppSettingsKeys.menuBarIcon) ?? ""
        let option = MenuBarIconOption(rawValue: raw) ?? .magnifyingglass
        let colored = defaults.bool(forKey: AppSettingsKeys.colorMenuBarIcon)
        statusItem.button?.image = option.statusItemImage(palette: colored ? PanelPalette.current() : nil)
        statusItem.button?.image?.accessibilityDescription = "Goorgle"
    }

    /// Re-registers the global shortcut from the stored settings, reporting
    /// whether the system accepted it so Preferences can say when a
    /// combination is already spoken for by another app.
    @discardableResult
    func applyHotKeySettings() -> Bool {
        hotKeyMonitor.apply(HotKeyShortcut.stored())
    }

    // MARK: - Hub commands

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = HubCommand(url: url) else { continue }
            switch command {
            case .search:
                showPanel()
            case .preferences:
                showPreferences()
            }
        }
    }

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else {
            togglePanel()
            return
        }
        // Control-click arrives as a *left* mouse up with the Control modifier —
        // treating only .rightMouseUp as a menu click left Control-click
        // toggling the panel instead of opening the menu.
        let isMenuClick = event.type == .rightMouseUp
            || event.modifierFlags.contains(.control)
        if isMenuClick {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let preferencesItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Goorgle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Temporarily attach the menu so performClick shows it like a real right-click,
        // then detach so left-clicks go back to toggling the panel instead of a menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.show()
    }

    private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    /// Unconditionally shows the panel. The hub's `goorgle://search` means
    /// "open it", not "toggle it" — a toggle would close the panel for anyone
    /// who clicked Search while it was already up.
    private func showPanel() {
        if statusItem.isVisible, let button = statusItem.button {
            panel.show(relativeTo: button)
        } else {
            panel.showCentered()
        }
    }

    private func hidePanel() {
        panel.orderOut(nil)

        // Summoning the panel activates Goorgle so the field can actually take
        // keystrokes; without giving that activation back, dismissing leaves an
        // agent app frontmost with nothing on screen, and the next thing typed
        // goes nowhere. Skipped while Preferences is up, which is a window the
        // user genuinely wants to keep working in.
        let hasOtherVisibleWindow = NSApp.windows.contains {
            $0 !== panel && $0.isVisible && $0.canBecomeKey
        }
        if !hasOtherVisibleWindow {
            NSApp.hide(nil)
        }
    }

    /// Dock icon → single click with no visible windows (only relevant when
    /// "Show icon in Dock" is on): open the panel instead of doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !panel.isVisible {
            togglePanel()
        }
        return true
    }

    /// Dock icon → right-click menu. Matters most when the menu bar icon is
    /// off, since that's otherwise the only way to reach Preferences.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: "")
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        return menu
    }
}
