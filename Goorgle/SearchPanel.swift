import AppKit
import SwiftUI

/// Borderless, non-activating floating panel that hosts SearchBarView.
/// `canBecomeKey` is overridden true so the text field can actually take
/// keystrokes without the app fully activating (Spotlight/Alfred-style).
final class SearchPanel: NSPanel {
    private let onDismissHandler: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismissHandler = onDismiss
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 230),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        contentView = NSHostingView(rootView: SearchBarView(onDismiss: onDismiss))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onDismissHandler()
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let x = buttonFrame.midX - frame.width / 2
        let y = buttonFrame.minY - frame.height - 6
        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
