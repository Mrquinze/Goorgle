import Carbon.HIToolbox

/// Registers a system-wide keyboard shortcut via the (still fully supported)
/// Carbon Event Manager hotkey APIs — no Accessibility/Input Monitoring
/// permission required, unlike an NSEvent global monitor on keyDown.
final class HotKeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onTrigger: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        register(keyCode: keyCode, modifiers: modifiers)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        var hotKeyID = EventHotKeyID(signature: OSType(0x476F6F72), id: 1) // "Goor"
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

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
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
