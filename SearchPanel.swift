import AppKit
import Combine
import SwiftUI

/// Borderless floating panel that hosts SearchBarView, Spotlight-style.
///
/// `canBecomeKey` has to be overridden for a borderless window — without it
/// the panel can never hold keyboard focus at all.
///
/// It is deliberately *not* a `.nonactivatingPanel` any more. That flag means
/// "show without activating the app", which reads like the right thing for an
/// overlay summoned by a global hotkey — but the app then stays in the
/// background, and SwiftUI's focus machinery won't hand a `TextField` a live
/// field editor there. The result was a panel that appeared, looked focused,
/// and quietly sent every keystroke to whatever app you came from.
final class SearchPanel: NSPanel {
    /// Bumped on every presentation so the hosted SwiftUI view re-asserts
    /// focus at a moment when the window is actually key.
    private let focus = SearchFocus()
    private let onDismissHandler: () -> Void
    /// Where the panel's top-left corner belongs. Height changes with the
    /// result list, and growing downward from a fixed top keeps the pill
    /// itself from jumping around under the pointer.
    private var anchorTopLeft: NSPoint?

    private static let width = SearchBarView.width
    private static let initialHeight: CGFloat = 96

    init(onDismiss: @escaping () -> Void) {
        self.onDismissHandler = onDismiss
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.initialHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // A panel that only takes key status when a subview "needs" it will
        // skip doing so on the way up, which is the exact moment we need it.
        becomesKeyOnlyIfNeeded = false

        resetContentIfHidden()
    }

    /// Rebuilds the hosted SwiftUI view from scratch.
    ///
    /// Hiding the panel is `orderOut(_:)`, which leaves the SwiftUI view alive:
    /// `onAppear` would never fire again, so the text field came up unfocused on
    /// every show after the first, still holding the previous query. A fresh
    /// hosting view per presentation gives a focused, empty field every time.
    ///
    /// No-op when the panel is already up: `goorgle://search` from the hub
    /// means "open it", and hitting it with the panel already open shouldn't
    /// throw away what the user is in the middle of typing.
    private func resetContentIfHidden() {
        guard !isVisible else { return }
        contentView = FirstMouseHostingView(
            rootView: SearchBarView(
                focus: focus,
                onDismiss: onDismissHandler,
                onContentHeightChange: { [weak self] height in
                    // The report arrives from inside SwiftUI's layout pass;
                    // resizing the window synchronously would re-enter it.
                    DispatchQueue.main.async { self?.applyContentHeight(height) }
                }
            )
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onDismissHandler()
    }

    /// Positions the panel just under the status item button and shows it.
    /// Falls back to `showCentered()` if the button has no valid on-screen
    /// frame (e.g. the menu bar icon is currently hidden via Preferences).
    func show(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else {
            showCentered()
            return
        }
        resetContentIfHidden()
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        anchorTopLeft = NSPoint(x: buttonFrame.midX - frame.width / 2, y: buttonFrame.minY - 6)
        applyAnchor(on: buttonWindow.screen ?? NSScreen.main)
        present()
    }

    /// Used when there's no status item button to anchor to — e.g. summoned
    /// via the global hotkey or the Dock icon while the menu bar icon is off.
    func showCentered() {
        resetContentIfHidden()
        let screen = NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        anchorTopLeft = NSPoint(
            x: visible.midX - frame.width / 2,
            // Slightly above center reads better than dead center — the result
            // list grows downward into the space below.
            y: visible.midY + visible.height * 0.18
        )
        applyAnchor(on: screen)
        present()
    }

    /// Shows the panel *and* makes it typable.
    ///
    /// Order matters: activating the app after taking key status let the
    /// activation reshuffle key windows and drop the field's focus, so the app
    /// is brought forward first and the panel takes key status into an already
    /// active app. Focus is then asserted three times, at the three moments it
    /// can be lost: now, after the window has actually become key, and once
    /// more as a hard AppKit fallback.
    private func present() {
        // Dismissing hides the app to hand activation back, and a hidden app's
        // windows won't come forward until it's unhidden.
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        focus.request()

        // Synchronously, before this call returns: SwiftUI installs `@FocusState`
        // a beat later, and someone who summons with a hotkey is already typing
        // in that beat — those first characters used to land nowhere. Laying the
        // subtree out first is what makes the field exist to focus at all.
        contentView?.layoutSubtreeIfNeeded()
        focusFieldDirectlyIfNeeded()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.isKeyWindow { self.makeKeyAndOrderFront(nil) }
            self.focus.request()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.focusFieldDirectlyIfNeeded()
        }
    }

    /// Last resort: if nothing text-like ended up as first responder, hand the
    /// field editor over by hand. A focused `NSTextField` shows up as its field
    /// editor (`NSTextView`) being first responder, so that's the test.
    private func focusFieldDirectlyIfNeeded() {
        guard isVisible, !(firstResponder is NSTextView) else { return }
        guard let contentView, let field = Self.firstTextInput(in: contentView) else { return }
        makeFirstResponder(field)
    }

    private static func firstTextInput(in view: NSView) -> NSView? {
        for subview in view.subviews {
            if subview is NSTextField || subview is NSTextView { return subview }
            if let found = firstTextInput(in: subview) { return found }
        }
        return nil
    }

    /// Resizes to the height SwiftUI just laid out, keeping the top edge put.
    private func applyContentHeight(_ height: CGFloat) {
        let target = max(60, height.rounded(.up))
        guard abs(target - frame.height) > 0.5 else { return }
        if anchorTopLeft == nil {
            anchorTopLeft = NSPoint(x: frame.minX, y: frame.maxY)
        }
        setContentSize(NSSize(width: Self.width, height: target))
        applyAnchor(on: screen ?? NSScreen.main)
    }

    /// Places the panel at its anchor, nudged to stay fully on screen — a
    /// status item near the right edge, or a long result list near the bottom,
    /// would otherwise push part of the panel off.
    private func applyAnchor(on screen: NSScreen?) {
        guard let anchor = anchorTopLeft else { return }
        guard let visible = screen?.visibleFrame else {
            setFrameOrigin(NSPoint(x: anchor.x, y: anchor.y - frame.height))
            return
        }
        let x = min(max(anchor.x, visible.minX + 8), max(visible.minX + 8, visible.maxX - frame.width - 8))
        let y = max(anchor.y - frame.height, visible.minY + 8)
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// Carries "focus the search field now" from the panel to the SwiftUI view.
///
/// A plain token rather than a bound Bool: the view sets its own `@FocusState`
/// in response, and re-requesting focus that's already held is a no-op, so the
/// panel can ask as many times as it needs to without fighting the view.
@MainActor
final class SearchFocus: ObservableObject {
    @Published private(set) var token = 0

    func request() { token += 1 }
}

/// Lets a click land on whatever it hits the moment the panel appears.
///
/// `NSHostingView` declines the first mouse click by default, so the click
/// that arrives while the panel is still taking key status is spent activating
/// the window — which is why suggestion rows appeared unclickable unless you
/// clicked them twice.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @MainActor required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
