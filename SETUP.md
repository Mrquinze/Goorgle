# Goorgle — Setup Guide

A menu bar recreation of the Android search bar for your Mac desktop: click
the icon (or press **⌥⌘Space** from anywhere), a rounded gradient pill
drops down with a focused text field and up to 5 live suggestions —
type and hit Enter to search (or jump straight to a URL) in your default
browser. Type **`/file <name>`** to search your Mac with Spotlight instead
and open the result, **`/yt`**, **`/gh`**, **`/wiki`**, **`/maps`**, `/so`
(or your own keyword) to search somewhere other than your default engine.
That default is Google out of the box and switchable to any of fourteen
engines in Preferences — DuckDuckGo, Brave, Bing, Ecosia, Startpage, Yahoo,
Mojeek, Marginalia, Swisscows, Kagi, or the answer engines Perplexity,
ChatGPT and Claude. Or just type **`12*34`** /
**`10 km to miles`** / **`100 usd to ils`** for an answer inline.

Search engine, **theme** (the original gradient pill or a Liquid Glass one),
**colors** (one accent, or a multicolour gradient of up to five stops at any
angle), font (any family installed via Font Book),
menu bar glyph, the global shortcut, custom `/keyword` engines, and menu
bar/Dock icon visibility are all customizable via **Preferences…**
(right-click the menu bar icon).

`Goorgle.app.xcodeproj` in this folder is already set up and kept in sync
with the source files — open it directly and skip to **step 4**. Steps 1–3
are reference material for recreating the project from scratch if it's
ever lost.

## 1. Create the Xcode Project

1. Open Xcode → **New Project** → macOS → **App**
   - Product Name: `Goorgle`
   - Bundle ID: `app.yair.goorgle`
   - Interface: SwiftUI | Language: Swift
   - Minimum Deployment: macOS 15.0

2. Delete the auto-generated `ContentView.swift` and `GoorgleApp.swift`.

3. **Add the source files** by dragging the `Goorgle/` folder from this
   repo into Xcode (into the `Goorgle` target):
   - `GoorgleApp.swift`
   - `AppDelegate.swift`
   - `SearchPanel.swift`
   - `PreferencesWindowController.swift`
   - `Services/HotKeyMonitor.swift`
   - `Services/LoginItemManager.swift`
   - `Services/SuggestionsClient.swift`
   - `Services/AppSettingsKeys.swift`
   - `Services/HubCommand.swift`
   - `Services/FileSearchClient.swift`
   - `Services/Calculator.swift`
   - `Services/CurrencyRatesClient.swift`
   - `Services/SearchEngines.swift`
   - `Services/PanelPalette.swift`
   - `Views/ShortcutRecorder.swift`
   - `Views/EngineSettingsTab.swift`
   - `Views/PanelSurface.swift`
   - `Views/SearchBarView.swift`
   - `Views/GoogleGMark.swift`
   - `Views/SettingsView.swift`
   - `Info.plist` — replace the auto-generated one, or merge the
     `LSUIElement` key into it (see step 2 below).
   - `Goorgle.entitlements` — records the deliberate opt-out of App Sandbox
     (see step 3).

---

## 2. Make It a Menu Bar Agent (no Dock icon)

Newer Xcode project templates auto-generate `Info.plist` from build
settings (`Generate Info.plist File` = Yes) and **ignore a physical
`Info.plist` file you drag in** unless you also disable that setting and
point `Info.plist File` at it. The reliable way that works either way:

1. Select the **Goorgle** target → **Info** tab.
2. Under **Custom macOS Application Target Properties**, click **+**.
3. Add key `Application is agent (UIElement)` → set value to **YES**.

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

1. Set **Signing** to your Apple ID/team.
2. **App Sandbox is deliberately OFF** (`ENABLE_APP_SANDBOX = NO` on both
   configurations). Xcode turns it on for new macOS App targets, so this is
   a conscious opt-out: Spotlight file search (`/file`) works fine *inside*
   a sandbox — `NSMetadataQuery` returns results — but `NSWorkspace.open`
   then refuses every path outside the app's own container, verified
   returning `false` even for a file in `~/Documents`. Every file result
   would be a dead end. Goorgle ships as an ad-hoc `.dmg`, never through the
   App Store, so the sandbox buys nothing it costs here. Unsandboxed, the
   suggest endpoint needs no network entitlement either.
   Whatever you choose, set it on **both** configurations — the checkbox in
   Signing & Capabilities only edits the one you have selected, which is
   exactly how this project ended up sandboxed in Debug and not in Release.
   `codesign -d --entitlements - path/to/Goorgle.app` shows what actually
   got signed in.
3. `NSWorkspace.shared.open(_:)` (used to hand the search URL to your
   default browser) needs no extra entitlement either way — it's Launch
   Services doing the work, not the app itself.

---

## 4. Build & Run

```
Cmd+R
```

1. A magnifying-glass icon appears in the menu bar. Click it to drop down
   the search pill — the text field is focused immediately, so you can
   summon and type in one motion without waiting or clicking the field.
2. Or press **⌥⌘Space** from any app to summon it without touching the
   mouse.
3. Start typing — up to 5 live suggestions appear below the pill after a
   short debounce. **↑/↓** to highlight one, **Return** to search the
   highlighted suggestion (or the raw text if none is highlighted), or just
   **click** any row.
4. Type something that looks like a domain (contains a `.`, no spaces) and
   press **Return**: opens it directly as a URL instead of searching.
4b. **File search:** start the query with `/file ` (or `/f `) to search this
   Mac's Spotlight index instead of the web — the pill switches to a "Files"
   mode and lists up to 6 matches with their icon and folder, ranked by how
   recently you used them. **Return** or a click opens the top/selected one;
   **⌥**-click (or ⌥Return) reveals it in Finder instead. Applications in
   `/Applications` are included, so `/f safari` doubles as a launcher, while
   Library, caches, build output and bundle internals are filtered out.
4c. **Other search engines:** start with a `/keyword` — `/yt` (YouTube),
   `/gh` (GitHub), `/wiki` (Wikipedia), `/maps`, `/so` (Stack Overflow), or
   any engine you add in **Preferences → Engines**. The pill shows which
   engine is active, suggestions still autocomplete the term (from that
   engine's own API when it has one, otherwise your default engine's), and
   Return (or a click on a suggestion) sends it to *that* engine. An
   unrecognised `/word` is just searched as text.
4d. **Calculations:** type arithmetic (`12*34`, `(5+3)*2`, `2^10`,
   `20% of 250`) or a conversion (`10 km to miles`, `72 f to c`,
   `5 gb to mb`, `3 hours to minutes`) and the answer appears as the top
   row *before* the suggestions even load — all offline. Currency
   (`100 usd to ils`, `$50 to eur`) is the one exception: it fetches rates
   from `open.er-api.com` (no API key), cached for six hours. Only the
   fixed base-currency URL is requested — what you typed never leaves the
   Mac. **Click the answer row** to copy it to the clipboard; Return still
   runs the search unless the answer row is highlighted.
5. Press **Esc**, or click anywhere outside the pill, to dismiss it.
6. Right-click (or Control-click) the menu bar icon for **Preferences…**
   and **Quit**. ⌘, opens Preferences too whenever Goorgle is the active
   app (the panel or the Preferences window itself is up).

**Preferences…** opens a normal window with three tabs:
- **General** — toggle the menu bar icon and/or Dock icon (at least one
  must stay on, so you can't lock yourself out), and **Launch at Login**
  (via `SMAppService` — no manual System Settings step needed). One
  caveat: login-item registration only works reliably for a properly
  signed build running from a stable location like `/Applications`; a raw
  debug build launched straight from Xcode's DerivedData folder may fail
  to register silently. If the toggle doesn't seem to do anything, archive
  the app (**Product → Archive → Distribute App → Copy App**) and run it
  from `/Applications` once, then try again — or just use the prebuilt
  `dist/Goorgle.dmg` (step 5).
  Also here: the **menu bar glyph** (six SF Symbols plus the color Goorgle
  mark, each previewed in the picker as it will actually render) and the
  **global shortcut**.
- **Appearance** — a **Theme** picker: *Gradient* is the original opaque
  pill filled with your accent; *Liquid Glass* makes the pill and result card
  translucent, refracting the desktop behind them with your accent as the
  tint. Liquid Glass proper is macOS 26 (`glassEffect`); on macOS 15 the same
  option falls back to an `NSVisualEffectView` blur tinted the same way, and
  the picker says so rather than looking broken.

  **Colors** is either *Single Accent* — one color blended toward white and
  black, the original behaviour and still the default — or *Multicolour*: two
  to five stops you pick yourself, at any angle from 0° (straight down)
  through 45° (the classic diagonal) to 345°, with nine presets to start from
  including the four-color Goorgle one. **Text** is Auto/Light/Dark, and
  **Color the menu bar icon** paints the status item glyph with the same
  palette instead of the usual monochrome template.

  Auto text picks white or near-black from the palette's brightness, weighted
  70/30 between its mean and its *brightest* stop. The mean alone rated
  yellow→red gradients as comfortably mid-tone and gave them white text that
  then vanished over the yellow end; the weighting flips exactly those to dark
  text while leaving saturated mid-tones (the Goorgle preset, the default
  blue) white, as a Material search bar reads. A gradient spanning both
  extremes has no right answer — that's what the manual override is for.

  Then an accent color picker used in Single Accent mode
  (the pill's gradient is derived
  from whatever single color you pick, and text flips to near-black on pale
  accents so it stays readable), a **font family** picker listing the four
  system designs followed by every family installed via Font Book — each
  row drawn in its own face — a size stepper, and a live preview of the
  pill.
- **Engines** — **Search with** picks the engine plain searches and live
  suggestions use: Google, DuckDuckGo, Brave Search, Bing, Ecosia, Startpage,
  or any custom engine of yours. Each is also reachable ad hoc by keyword
  (`/ddg cats` searches DuckDuckGo once without changing the default), and the
  pill's trailing Google mark becomes a monogram for other engines rather than
  claiming a query is going somewhere it isn't. Startpage publishes no
  autocomplete API, so picking it means no live suggestions — the picker says
  so. Below that, add your own `/keyword` targets: a keyword, a display name,
  and a URL template with `{query}` where the search term goes. Custom
  keywords shadow the built-ins, `file`/`f` are reserved for file search,
  and a template is only accepted if it resolves to an `http(s)` URL —
  `file://`, `javascript:` and app schemes are rejected, since a template
  ends up at `NSWorkspace.open`. Edits save as you type.

**Changing the hotkey:** click the shortcut button in **Preferences →
General → Global Shortcut**, then press the combination you want (it needs
at least one of ⌘/⌥/⌃). *Reset* puts ⌥⌘Space back. If another app already
owns the combination, `RegisterEventHotKey` refuses it and the recorder
says so instead of leaving you with a shortcut that silently never fires —
note ⌥⌘Space itself is macOS's default "Show Finder search window"
shortcut, remappable at System Settings → Keyboard → Keyboard Shortcuts.
The recording is a local `NSEvent` monitor, so menu shortcuts like ⌘Q can
be recorded without firing on the way past.

---

## 5. Building a Distributable .dmg

Once the Xcode project builds and runs (step 4), package it as a
drag-to-install `.dmg`:

```
./scripts/build-dmg.sh
```

This builds the Release configuration as a **universal binary** (both
`arm64` and `x86_64` — explicit `-destination 'generic/platform=macOS'`
plus `ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO`, since a plain build only
targets the Mac doing the building), **re-signs it ad-hoc** afterward
(`codesign --force --deep --sign - --options runtime --entitlements
Goorgle/Goorgle.entitlements` — a bare re-sign drops both the entitlements
and the Hardened Runtime that xcodebuild applied, and ad-hoc signatures
carry both fine), stages `Goorgle.app` alongside an
`Applications` shortcut (the standard macOS installer layout), and writes
`dist/Goorgle.dmg`. Re-run it any time after changing source files.

**Why ad-hoc re-signing:** `xcodebuild`'s own signature uses your personal
"Apple Development" identity, which is scoped to your own registered
devices — on a *different* Mac that identity can be rejected outright
(sometimes as "app is damaged, move to Trash" rather than the milder
unidentified-developer prompt). Stripping that and re-signing ad-hoc
(`Signature=adhoc`, `TeamIdentifier=not set`) makes every Mac hit the
same, standard, universally-recoverable Gatekeeper prompt instead.

**Gatekeeper on first launch:** `spctl` will still report the app as
"rejected" on any Mac, including this one — that's simply what "not
notarized" looks like, ad-hoc or not, and is normal for an indie/personal
build.

On the Mac that *built* it there's no quarantine flag, so it just opens. A
copy that travelled (AirDrop, email, download, USB) is quarantined on
arrival, and needs one manual approval:

1. Drag `Goorgle.app` out of the mounted dmg into `/Applications`.
2. Double-click it. macOS refuses and says Apple can't verify it's free of
   malware.
3. **System Settings → Privacy & Security**, scroll to the Security
   section, and click **Open Anyway** next to the Goorgle message, then
   confirm. It opens normally from then on.

Note the **right-click → Open** trick no longer works: macOS 15 Sequoia
removed the Control-click override for software that isn't signed *and*
notarized, and Goorgle requires macOS 15.6 anyway, so Privacy & Security is
the only route. The terminal equivalent, if the recipient prefers it, is
`xattr -d com.apple.quarantine /Applications/Goorgle.app` before the first
launch — which strips the quarantine flag so the check never fires.

Fully warning-free distribution to other people's Macs requires a paid
Apple Developer Program membership ($99/yr) for Developer ID signing +
notarization, which is out of scope here.

**If the project file ever shows source files as missing/red in Xcode:**
the file references in `Goorgle.app.xcodeproj` must nest exactly like the
folders on disk (`Goorgle/`, `Goorgle/Views/`, `Goorgle/Services/`) —
dragging a file onto the wrong group in the Project Navigator silently
breaks the path Xcode resolves for it, and `Cmd+R` can still "work" off a
stale cached binary even when a file's reference is broken. If a rebuild
suddenly fails with "Build input files cannot be found," check each
red/missing file's **File Inspector → Identity and Type → Full Path**
matches its real location, and fix by dragging it into the correct group
or updating the path in the inspector.

---

## Architecture Overview

```
Goorgle (menu bar agent, LSUIElement — Dock icon is opt-in at runtime)
├── GoorgleApp                – empty Settings scene; AppDelegate does the real work
├── AppDelegate                 – NSStatusItem (left-click toggles, right-click menu),
│                                owns SearchPanel + HotKeyMonitor + PreferencesWindowController,
│                                applies showMenuBarIcon/showDockIcon via setActivationPolicy
├── SearchPanel                 – borderless NSPanel, activating and key-capable,
│                                transparent, hugs its content height (grows downward
│                                from a fixed top edge, clamped on screen),
│                                click-outside-to-dismiss via resignKey(), rebuilds its
│                                hosted view per show (fresh focus + empty field),
│                                FirstMouseHostingView so the first click counts,
│                                focuses the field synchronously on show so the
│                                first keystroke counts too
├── PreferencesWindowController – normal titled NSWindow hosting SettingsView
├── Services/
│   ├── HubCommand               – goorgle:// URL commands from Yair's Apps, plus
│   │                             HubMenuBar, the menu bar consolidation channel
│   ├── HotKeyMonitor            – Carbon RegisterEventHotKey wrapper, re-registrable
│   │                             at runtime; HotKeyShortcut is the stored combination
│   │                             (⌥⌘Space by default). No Accessibility permission
│   ├── LoginItemManager         – SMAppService wrapper for the login-item toggle
│   ├── SuggestionsClient        – live autocomplete from the selected engine;
│   │                             one OpenSearch parser covers Google, DuckDuckGo,
│   │                             Brave, Bing and Ecosia alike. Also holds
│   │                             QueryEncoding, the RFC 3986 percent-encoder every
│   │                             URL in the app is built with
│   ├── FileSearchClient         – NSMetadataQuery (Spotlight) wrapper behind /file,
│   │                             recency-ranked, noise-filtered; needs no sandbox
│   ├── Calculator               – hand-rolled expression parser + Measurement-based
│   │                             unit conversion, all offline; recognises currency
│   │                             pairs but leaves them to…
│   ├── CurrencyRatesClient      – …this, a 6-hour-cached actor over open.er-api.com
│   ├── SearchEngines            – the default web engine, the built-in /keyword
│   │                             engines and the user's own; {query} templates
│   │                             confined to http(s)
│   ├── PanelPalette             – every color the panel draws with, in one place:
│   │                             accent or multicolour stops, angle → UnitPoints,
│   │                             tint, highlight, and the auto text-color decision
│   └── AppSettingsKeys          – UserDefaults keys, AppFont (system designs +
│                                Font Book families), MenuBarIconOption, and the
│                                Color(hex:)/pillGradientStops helpers
└── Views/
    ├── SearchBarView           – gradient pill (from the accent color) + result card;
    │                             parses the query into an Intent (files / engine /
    │                             web), shows calculated answers, suggestions or file
    │                             hits, arrow-key + hover + click, open → NSWorkspace
    │                             (⌥ reveals in Finder, click copies an answer)
    ├── GoogleGMark             – stylized 4-color "G" glyph (arcs + bar), not the
    │                             real asset; doubles as a menu bar icon choice
    ├── PanelSurface            – AppTheme (how a surface is *painted*) plus the
    │                             view modifier that paints one panel surface:
    │                             glassEffect on macOS 26, NSVisualEffectView
    │                             below it, accent gradient otherwise
    ├── ShortcutRecorder        – click-to-record global shortcut control
    ├── EngineSettingsTab       – editor for custom /keyword engines
    └── SettingsView            – General/Appearance/Engines TabView, @AppStorage-backed
```

Design notes: the app moved off `MenuBarExtra` (used in the first version)
because SwiftUI gives no public API to programmatically open a
`MenuBarExtra`'s popover, which the global hotkey needs to do. A hand-rolled
`NSStatusItem` + `NSPanel` gives full control over showing/hiding, sizing,
and dismiss behavior. The panel now hugs its content: SwiftUI reports the
laid-out height and the panel resizes to match, growing downward from a
fixed top edge. The earlier fixed-size-and-transparent approach *looked*
identical, but the reserved-but-invisible area still swallowed clicks — so
clicking "outside" the pill often hit the panel and didn't dismiss it. The
pill's gradient and corner radius (`Capsule`) lean into Android 16 /
Material 3 Expressive's fully-rounded, high-contrast search bar look.

**Typing the instant it appears** takes more than `@FocusState`. SwiftUI
installs focus a beat *after* the view is shown, and someone who summons with
a hotkey is already typing inside that beat — measured with a harness that
sends keystrokes in the same run-loop turn as the summon, the first two
characters of "goat" were dropped and only "at" arrived. So `present()` lays
the content out and makes the search field first responder synchronously,
before it returns, and only then lets SwiftUI's `@FocusState` catch up (via a
token the panel bumps on every presentation, since `onAppear` fires just once
per hosted view). A last-resort pass 120ms later covers the case where the
field didn't exist yet. The panel also stopped being a `.nonactivatingPanel`
and now activates the app before taking key status, with `NSApp.hide(nil)` on
dismiss handing activation back to whatever you came from — otherwise an agent
app is left frontmost with nothing on screen.

Result rows are `Button`s with an explicit `contentShape(Rectangle())` and
a hover state, hosted in a `FirstMouseHostingView`. All three matter for
them to feel clickable: without the content shape only the drawn glyphs are
hit-testable, and `NSHostingView` declines the first mouse click by
default, which ate the click that arrived as the panel took key status.

The Preferences window (`PreferencesWindowController`) is a deliberately
different NSWindow flavor than `SearchPanel`: normal/titled/activating,
since it's an ordinary utility window rather than a Spotlight-style
overlay. Settings persist via `@AppStorage` (plain UserDefaults) rather
than a shared `ObservableObject`, since `@AppStorage` works fine wherever
it's declared in a SwiftUI view — including inside `SearchBarView`, which
lives in an `NSHostingView` outside any app-level environment — without
needing a hand-rolled Combine publisher. The one exception is icon
visibility: `AppDelegate` is a plain `NSObject`, not a SwiftUI view, so it
can't read `@AppStorage` reactively; `SettingsView` calls
`AppDelegate.shared?.applyIconVisibilitySettings()` directly via
`.onChange` instead. Accent color is stored as a single hex string and
expanded into a light/dark two-stop gradient at render time
(`Color.pillGradientStops`) by blending toward white/black, rather than
storing two colors — one picker, and the gradient always stays visually
consistent with whatever's picked.
