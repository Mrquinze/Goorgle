import AppKit
import Carbon.HIToolbox

/// A global shortcut, stored as the Carbon key code + modifier mask the hotkey
/// API wants, plus the label to show in Preferences.
///
/// The label is persisted alongside the codes rather than derived from the key
/// code on demand: turning a key code back into "Space" or "]" means going
/// through the current keyboard layout with `UCKeyTranslate`, and the honest
/// answer — what the key produced when the user pressed it — is already in the
/// event that recorded it.
struct HotKeyShortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String

    static let `default` = HotKeyShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey | optionKey),
        label: "⌥⌘Space"
    )

    /// Builds a shortcut from a recorded key event, or nil if the combination
    /// isn't usable as a global hotkey (bare keys and Shift-only combinations
    /// would swallow ordinary typing system-wide).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
        else { return nil }

        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }

        self.keyCode = UInt32(event.keyCode)
        self.modifiers = carbon
        self.label = Self.label(for: event, flags: flags)
    }

    init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    private static func label(for event: NSEvent, flags: NSEvent.ModifierFlags) -> String {
        var parts = ""
        if flags.contains(.control) { parts += "⌃" }
        if flags.contains(.option) { parts += "⌥" }
        if flags.contains(.shift) { parts += "⇧" }
        if flags.contains(.command) { parts += "⌘" }
        return parts + keyName(for: event)
    }

    /// Names the keys whose characters are invisible or misleading; everything
    /// else uses what the key actually types, uppercased.
    private static func keyName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "Delete"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        default:
            let typed = event.charactersIgnoringModifiers ?? ""
            return typed.isEmpty ? "Key \(event.keyCode)" : typed.uppercased()
        }
    }

    /// Reads the persisted shortcut, falling back to ⌥⌘Space.
    static func stored(in defaults: UserDefaults = .standard) -> HotKeyShortcut {
        guard defaults.object(forKey: AppSettingsKeys.hotKeyCode) != nil else { return .default }
        return HotKeyShortcut(
            keyCode: UInt32(defaults.integer(forKey: AppSettingsKeys.hotKeyCode)),
            modifiers: UInt32(defaults.integer(forKey: AppSettingsKeys.hotKeyModifiers)),
            label: defaults.string(forKey: AppSettingsKeys.hotKeyLabel) ?? HotKeyShortcut.default.label
        )
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(Int(keyCode), forKey: AppSettingsKeys.hotKeyCode)
        defaults.set(Int(modifiers), forKey: AppSettingsKeys.hotKeyModifiers)
        defaults.set(label, forKey: AppSettingsKeys.hotKeyLabel)
    }
}

/// Registers a system-wide keyboard shortcut via the (still fully supported)
/// Carbon Event Manager hotkey APIs — no Accessibility/Input Monitoring
/// permission required, unlike an NSEvent global monitor on keyDown.
final class HotKeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onTrigger: () -> Void

    init(shortcut: HotKeyShortcut, onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        installHandler()
        _ = apply(shortcut)
    }

    /// Swaps in a new shortcut, reporting whether the system accepted it —
    /// `RegisterEventHotKey` refuses a combination another app already owns
    /// (⌥⌘Space is Finder's by default), and Preferences says so rather than
    /// leaving a shortcut that quietly never fires.
    @discardableResult
    func apply(_ shortcut: HotKeyShortcut) -> Bool {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x476F6F72), id: 1) // "Goor"
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return status == noErr
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                monitor.onTrigger()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
