import AppKit
import SwiftUI
import Carbon.HIToolbox

/// UserDefaults keys shared between SettingsView (writer) and the views/
/// AppDelegate that read them (SearchBarView, AppDelegate).
enum AppSettingsKeys {
    static let accentColorHex = "accentColorHex"
    /// Legacy: the four system font *designs*, superseded by `fontFamily`
    /// (which folds those designs in alongside every installed font).
    /// Still read once, at launch, to migrate an existing pick over.
    static let fontDesign = "fontDesign"
    static let fontFamily = "fontFamily"
    static let fontSize = "fontSize"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let showDockIcon = "showDockIcon"
    static let menuBarIcon = "menuBarIcon"
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyModifiers = "hotKeyModifiers"
    static let hotKeyLabel = "hotKeyLabel"
    static let customEngines = "customEngines"
    static let defaultEngine = "defaultEngine"
    static let theme = "theme"
    static let colorMode = "colorMode"
    static let gradientStops = "gradientStops"
    static let gradientAngle = "gradientAngle"
    static let textColorMode = "textColorMode"
    static let colorMenuBarIcon = "colorMenuBarIcon"
    static let paletteRevision = "paletteRevision"

    /// Folds a pre-`fontFamily` `fontDesign` pick into the new single font
    /// setting, so upgrading doesn't silently reset someone's font.
    static func migrateLegacyFontDesignIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: fontFamily) == nil,
              let legacy = defaults.string(forKey: fontDesign),
              let option = FontDesignOption(rawValue: legacy)
        else { return }
        defaults.set(option.fontFamilyToken, forKey: fontFamily)
    }
}

/// Legacy setting — see `AppSettingsKeys.fontDesign`.
enum FontDesignOption: String, CaseIterable, Identifiable {
    case system, rounded, serif, monospaced

    var id: String { rawValue }

    var fontFamilyToken: String {
        switch self {
        case .system: return AppFont.systemToken
        case .rounded: return AppFont.roundedToken
        case .serif: return AppFont.serifToken
        case .monospaced: return AppFont.monospacedToken
        }
    }
}

/// The font shown in the search field and suggestion rows.
///
/// One setting covers both the four system designs and every family installed
/// via Font Book: the designs are stored as reserved `__`-prefixed tokens, and
/// anything else is a literal family name handed to `Font.custom`. Two pickers
/// (design *and* family) would have needed a rule for which one wins.
enum AppFont {
    static let systemToken = "__system"
    static let roundedToken = "__rounded"
    static let serifToken = "__serif"
    static let monospacedToken = "__monospaced"

    /// The system entries, in menu order, ahead of the installed families.
    static let systemChoices: [(token: String, label: String)] = [
        (systemToken, "System"),
        (roundedToken, "System Rounded"),
        (serifToken, "System Serif"),
        (monospacedToken, "System Monospaced"),
    ]

    /// Every family Font Book knows about, minus the ones whose names start
    /// with a dot — those are internal system faces that aren't meant to be
    /// picked directly (`.SF NS`, `.LastResort`, …).
    static var installedFamilies: [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func label(for family: String) -> String {
        systemChoices.first { $0.token == family }?.label ?? family
    }

    /// Resolves a stored family (token or Font Book name) into a SwiftUI font.
    /// An installed family that has since been uninstalled falls back to the
    /// system font rather than rendering in a substituted face.
    static func font(family: String, size: CGFloat) -> Font {
        switch family {
        case systemToken, "": return .system(size: size)
        case roundedToken: return .system(size: size, design: .rounded)
        case serifToken: return .system(size: size, design: .serif)
        case monospacedToken: return .system(size: size, design: .monospaced)
        default:
            guard NSFont(name: family, size: size) != nil
                    || NSFontManager.shared.availableFontFamilies.contains(family)
            else { return .system(size: size) }
            return .custom(family, size: size)
        }
    }
}

/// The glyph shown in the menu bar.
///
/// `symbol` is looked up at render time and falls back to the plain
/// magnifying glass when a symbol isn't present on this macOS version, so an
/// older system degrades to a working icon instead of a blank status item.
enum MenuBarIconOption: String, CaseIterable, Identifiable {
    case magnifyingglass
    case sparkle
    case text
    case circle
    case globe
    case letterG
    case goorgleMark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .magnifyingglass: return "Magnifying Glass"
        case .sparkle: return "Sparkle Search"
        case .text: return "Text Search"
        case .circle: return "Filled Circle"
        case .globe: return "Globe"
        case .letterG: return "Letter G"
        case .goorgleMark: return "Goorgle Mark (color)"
        }
    }

    private var symbolName: String? {
        switch self {
        case .magnifyingglass: return "magnifyingglass"
        case .sparkle: return "sparkle.magnifyingglass"
        case .text: return "text.magnifyingglass"
        case .circle: return "magnifyingglass.circle.fill"
        case .globe: return "globe"
        case .letterG: return "g.circle.fill"
        case .goorgleMark: return nil
        }
    }

    /// A status-item-sized image.
    ///
    /// Passing a palette paints the glyph with it and marks the result
    /// non-template, so macOS renders the actual colors instead of flattening
    /// it to a monochrome mask — which is also why the color Goorgle mark has
    /// always had to go through `ImageRenderer` rather than an SF Symbol.
    @MainActor
    func statusItemImage(palette: PanelPalette? = nil) -> NSImage? {
        guard let symbolName else {
            return Self.rendered(GoogleGMark().frame(width: 16, height: 16))
        }
        let resolved = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Goorgle")
            ?? NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Goorgle")
        guard let palette else { return resolved }

        let colored = Self.rendered(
            Image(systemName: resolved == nil ? "magnifyingglass" : symbolName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.gradient)
                .frame(width: 18, height: 18)
        )
        return colored ?? resolved
    }

    @MainActor
    private static func rendered(_ content: some View) -> NSImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage
        image?.isTemplate = false
        return image
    }
}

extension Color {
    nonisolated init(hex: String) {
        let hexValue = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hexValue).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }

    nonisolated var hexString: String {
        guard let rgb = NSColor(self).usingColorSpace(.deviceRGB) else { return "4D9EF5" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }

    /// Derives a light→dark two-stop gradient from a single accent color,
    /// so the pill keeps its glossy look regardless of which color is picked.
    nonisolated var pillGradientStops: [Color] {
        let base = NSColor(self).usingColorSpace(.deviceRGB)
            ?? NSColor(red: 0.18, green: 0.51, blue: 0.93, alpha: 1)
        let light = base.blended(withFraction: 0.35, of: .white) ?? base
        let dark = base.blended(withFraction: 0.25, of: .black) ?? base
        return [Color(light), Color(dark)]
    }

    /// True when the accent is light enough that white text on it would be
    /// hard to read — the pill flips to near-black text for those.
    nonisolated var prefersDarkForeground: Bool {
        guard let rgb = NSColor(self).usingColorSpace(.deviceRGB) else { return false }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.72
    }
}
