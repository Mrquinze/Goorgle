# Goorgle — Setup Guide

A menu bar recreation of the Android search bar for your Mac desktop: click
the icon (or press **⌃⌘Space** from anywhere), a rounded sky-blue pill
drops down with a focused text field and up to 3 live Google suggestions —
type and hit Enter to search (or jump straight to a URL) in your default
browser.

OPTION 1 - Download release .dmg file and move to /Applications. Then go to System Settings/Privacy and Security and scroll down to "Open Anyway".

## 1. Create the Xcode Project

1. 1Open Xcode → **New Project** → macOS → **App**
  - Product Name: `Goorgle`
  - Bundle ID: `app.developer.goorgle`
  - Interface: SwiftUI | Language: Swift
  - Minimum Deployment: macOS 15.0

2. 2Delete the auto-generated `ContentView.swift` and `GoorgleApp.swift`.

3. 3**Add the source files** by dragging the `Goorgle/` folder from this
   repo into Xcode (into the `Goorgle` target):
  - `GoorgleApp.swift`
  - `AppDelegate.swift`
  - `SearchPanel.swift`
  - `Services/HotKeyMonitor.swift`
  - `Services/LoginItemManager.swift`
  - `Services/GoogleSuggestClient.swift`
  - `Views/SearchBarView.swift`
  - `Views/GoogleGMark.swift`
  - `Info.plist` — replace the auto-generated one, or merge the
     `LSUIElement` key into it (see step 2 below).
  - `Goorgle.entitlements` — needed for the live-suggestions network call
     under App Sandbox (see step 3).

---

## 2. Make It a Menu Bar Agent (no Dock icon)

Newer Xcode project templates auto-generate `Info.plist` from build
settings (`Generate Info.plist File` = Yes) and **ignore a physical**
**`Info.plist` file you drag in** unless you also disable that setting and
point `Info.plist File` at it. The reliable way that works either way:

1. 1Select the **Goorgle** target → **Info** tab.
2. 2Under **Custom macOS Application Target Properties**, click **+**.
3. 3Add key `Application is agent (UIElement)` → set value to **YES**.

Without this, Goorgle shows up in the Dock and Cmd+Tab like a normal app —
and since it has no real `WindowGroup`, clicking its Dock icon just
activates the app with nothing to show, which looks like a hang. Once
`LSUIElement` is set, the Dock icon disappears entirely and the app is
reached only via the menu bar icon or the global hotkey.

If you'd rather use the provided `Info.plist` file directly: target →
**Build Settings** → search "Info.plist" → set `Generate Info.plist File`
to **No** and `Info.plist File` to `Goorgle/Info.plist`, then make sure
that file is *not* also listed under **Copy Bundle Resources** in Build
Phases (remove it if Xcode added it there — otherwise you'll get a
"multiple commands produce Info.plist" build error).

---

## 3. Signing & Capabilities

1. 1Set **Signing** to your Apple ID/team.
2. 2Live suggestions fetch from `suggestqueries.google.com`, which needs
   outgoing network access. If App Sandbox is enabled (Xcode's default for
   new macOS App targets), add the capability: target → **Signing &**
**   Capabilities** → **+ Capability** → **App Sandbox** → check **Outgoing**
**   Connections (Client)**. This should match the provided
   `Goorgle.entitlements` file — point **Code Signing Entitlements** (Build
   Settings) at it if Xcode generated a separate one instead.
3. 3`NSWorkspace.shared.open(_:)` (used to hand the search URL to your
   default browser) needs no extra entitlement either way — it's Launch
   Services doing the work, not the app itself.

---

## 4. Build & Run

```
Cmd+R
```

1. 1A magnifying-glass icon appears in the menu bar. Click it to drop down
   the search pill — the text field is focused automatically.
2. 2Or press **⌃⌘Space** from any app to summon it without touching the
  1. 1
3. 3Start typing — up to 3 Google suggestions appear below the pill after a
   short debounce. **↑/↓** to highlight one, **Return** to search the
   highlighted suggestion (or the raw text if none is highlighted).
4. 4Type something that looks like a domain (contains a `.`, no spaces) and
   press **Return**: opens it directly as a URL instead of searching.
5. 5Press **Esc**, or click anywhere outside the pill, to dismiss it.
6. 6Right-click (or Control-click) the menu bar icon for **Launch at**
**   Login** and **Quit**.

**Launch at Login** is a checkbox in that right-click menu now (via
`SMAppService`) — no manual System Settings step needed. One caveat: it
only registers reliably for a properly signed build running from a stable
location like `/Applications`; a raw debug build launched straight from
Xcode's DerivedData folder may fail to register silently. If the toggle
doesn't seem to do anything, archive the app (**Product → Archive →**
**Distribute App → Copy App**) and run it from `/Applications` once, then
try the toggle again.

**Changing the hotkey:** it's hardcoded in `AppDelegate.swift` as
`kVK_Space` + `cmdKey | controlKey`. Swap `kVK_Space` for any other
`kVK_*` constant from `Carbon.HIToolbox` and/or adjust the modifier flags
(`cmdKey`, `controlKey`, `shiftKey`, `optionKey`) to taste. Note that
⌃⌘Space collides with macOS's built-in Character Viewer shortcut — if the
hotkey doesn't fire, disable/remap it at System Settings → Keyboard →
Keyboard Shortcuts → "Emoji & Symbols".

---

## Architecture Overview

```
Goorgle (menu bar agent, LSUIElement)
├── GoorgleApp          – empty Settings scene; AppDelegate does the real work
├── AppDelegate          – NSStatusItem (left-click toggles, right-click menu),
│                          owns the SearchPanel + HotKeyMonitor
├── SearchPanel           – borderless NSPanel, non-activating but key-capable,
│                          transparent + fixed-size so unused space is invisible,
│                          click-outside-to-dismiss via resignKey()
├── Services/
│   ├── HotKeyMonitor      – Carbon RegisterEventHotKey wrapper (⌃⌘Space),
│   │                        no Accessibility permission required
│   ├── LoginItemManager   – SMAppService wrapper for the login-item toggle
│   └── GoogleSuggestClient – fetches Google's own autocomplete endpoint
└── Views/
    ├── SearchBarView      – sky-blue gradient pill + suggestions list,
    │                        arrow-key navigation, submit → NSWorkspace.open
    └── GoogleGMark        – stylized 4-color "G" glyph (arcs + bar), not the
                             real asset
```

Design notes: the app moved off `MenuBarExtra` (used in the first version)
because SwiftUI gives no public API to programmatically open a
`MenuBarExtra`'s popover, which the global hotkey needs to do. A hand-rolled
`NSStatusItem` + `NSPanel` gives full control over showing/hiding, sizing,
and dismiss behavior. The panel is sized to fit the pill plus 3 suggestion
rows up front rather than resized dynamically — since its background is
fully transparent, the reserved-but-unused space when there are no
suggestions is simply invisible, so this is visually identical to a
dynamically-sized panel with far less code. The pill's gradient and corner
radius (`Capsule`) lean into Android 16 / Material 3 Expressive's
fully-rounded, high-contrast search bar look, recolored sky blue per
request instead of the stock light gray/white fill.
