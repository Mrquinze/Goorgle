import AppKit
import SwiftUI

/// Click-to-record control for the global shortcut.
///
/// Recording is a local `NSEvent` monitor rather than a first-responder
/// `NSView`: the monitor sees the key *before* the menu system does, so
/// combinations that are already menu shortcuts (⌘W, ⌘Q) can still be
/// recorded, and returning nil swallows the key so recording ⌘Q doesn't quit
/// the app on the way past.
struct ShortcutRecorder: View {
    @Binding var shortcut: HotKeyShortcut
    /// Reports the accepted shortcut; returns false if the system refused to
    /// register it, which surfaces as the "already in use" note.
    var onRecorded: (HotKeyShortcut) -> Bool

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: toggleRecording) {
                    Text(isRecording ? "Type a shortcut…" : shortcut.label)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .frame(minWidth: 120)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .accentColor : nil)

                if !isRecording, shortcut != .default {
                    Button("Reset") { commit(.default) }
                        .buttonStyle(.link)
                }
            }

            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(note.hasPrefix("Recorded") ? .secondary : Color.red)
            }
        }
        .onDisappear(perform: stopRecording)
        // An armed recorder swallows every keystroke in the app (that's how it
        // captures ⌘Q without quitting). Clicking away from Preferences while
        // it's armed would leave the keyboard feeling dead, so disarm as soon
        // as the window stops being key.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if isRecording {
                stopRecording()
                note = nil
            }
        }
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        note = "Press a combination including ⌘, ⌥ or ⌃. Esc cancels."
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stopRecording()
                note = nil
                return nil
            }
            if let recorded = HotKeyShortcut(event: event) {
                commit(recorded)
            } else {
                note = "That needs at least one of ⌘, ⌥ or ⌃."
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }

    private func commit(_ recorded: HotKeyShortcut) {
        stopRecording()
        shortcut = recorded
        note = onRecorded(recorded)
            ? "Recorded — \(recorded.label) now opens Goorgle."
            : "\(recorded.label) is already taken by another app. Pick a different one."
    }
}
