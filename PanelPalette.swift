import SwiftUI
import AppKit

/// Where the panel's colors come from.
enum ColorMode: String, CaseIterable, Identifiable {
    /// One accent color, expanded into a light→dark two-stop gradient. The
    /// original behaviour, and still the default so nobody's setup changes
    /// under them.
    case accent
    /// Two to five colors the user picked, at an angle they picked.
    case gradient

    var id: String { rawValue }

    var label: String {
        switch self {
        case .accent: return "Single Accent"
        case .gradient: return "Multicolour"
        }
    }
}

/// Whether text on the panel is chosen for contrast or forced.
///
/// Auto works from luminance, which is right nearly always — but a gradient
/// that runs from near-white to near-black has no single right answer, so the
/// override exists for the cases the math can't win.
enum TextColorMode: String, CaseIterable, Identifiable {
    case auto, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// A ready-made multicolour palette.
struct GradientPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let hexes: [String]
    let angle: Double

    var colors: [Color] { hexes.map(Color.init(hex:)) }

    static let all: [GradientPreset] = [
        // The four Google colors, since that's the joke the whole app is built on.
        GradientPreset(id: "goorgle", name: "Goorgle", hexes: ["4285F4", "EA4335", "FBBC05", "34A853"], angle: 45),
        GradientPreset(id: "sunset", name: "Sunset", hexes: ["FF6B6B", "FF8E53", "FFC371"], angle: 60),
        GradientPreset(id: "aurora", name: "Aurora", hexes: ["00C9A7", "4D9EF5", "845EC2"], angle: 45),
        GradientPreset(id: "candy", name: "Candy", hexes: ["FF5FA2", "FF8ADE", "C86DD7"], angle: 30),
        GradientPreset(id: "vapor", name: "Vaporwave", hexes: ["8E2DE2", "4A00E0", "00D2FF"], angle: 60),
        GradientPreset(id: "citrus", name: "Citrus", hexes: ["F9D423", "FF4E50"], angle: 90),
        GradientPreset(id: "mint", name: "Mint", hexes: ["43E97B", "38F9D7"], angle: 45),
        GradientPreset(id: "ocean", name: "Deep Ocean", hexes: ["0F2027", "203A43", "2C5364"], angle: 45),
        GradientPreset(id: "graphite", name: "Graphite", hexes: ["3A3A3C", "636366"], angle: 45),
    ]
}

/// Every color the panel draws with, resolved from the stored settings.
///
/// One type so the pill, the result card, the glass tint, the row highlight
/// and the menu bar glyph can't drift apart — before this they each derived
/// their own color from the accent and only agreed by coincidence.
struct PanelPalette: Equatable {
    /// At least two, in gradient order.
    let stops: [Color]
    /// Degrees clockwise from straight down: 0 = ↓, 45 = ↘ (the classic look),
    /// 90 = →, 180 = ↑.
    let angle: Double
    let textMode: TextColorMode

    static let minimumStops = 2
    static let maximumStops = 5
    static let defaultAngle: Double = 45
    /// Above this mean brightness, dark text reads better than white.
    ///
    /// Tuned for this design rather than taken from WCAG: the strict contrast
    /// crossover (~0.18 relative luminance) would put black text on the
    /// default blue, which every Material-style search bar renders white. The
    /// looser bar keeps saturated mid-tones white while catching pastels — a
    /// mint or peach gradient was previously handed unreadable white text.
    /// Gradients that span both extremes have no right answer, which is what
    /// the Light/Dark override is for.
    static let darkTextThreshold = 0.66

    // MARK: - Reading settings

    static func current(from defaults: UserDefaults = .standard) -> PanelPalette {
        let mode = ColorMode(rawValue: defaults.string(forKey: AppSettingsKeys.colorMode) ?? "") ?? .accent
        let textMode = TextColorMode(rawValue: defaults.string(forKey: AppSettingsKeys.textColorMode) ?? "") ?? .auto

        switch mode {
        case .accent:
            let accent = Color(hex: defaults.string(forKey: AppSettingsKeys.accentColorHex) ?? "4D9EF5")
            return PanelPalette(stops: accent.pillGradientStops, angle: defaultAngle, textMode: textMode)
        case .gradient:
            let hexes = storedStopHexes(from: defaults)
            let angle = defaults.object(forKey: AppSettingsKeys.gradientAngle) as? Double ?? defaultAngle
            return PanelPalette(stops: hexes.map(Color.init(hex:)), angle: angle, textMode: textMode)
        }
    }

    /// The custom stops as hex strings, falling back to the Goorgle preset the
    /// first time multicolour is switched on.
    static func storedStopHexes(from defaults: UserDefaults = .standard) -> [String] {
        guard let data = defaults.data(forKey: AppSettingsKeys.gradientStops),
              let hexes = try? JSONDecoder().decode([String].self, from: data),
              hexes.count >= minimumStops
        else { return GradientPreset.all[0].hexes }
        return Array(hexes.prefix(maximumStops))
    }

    static func saveStopHexes(_ hexes: [String], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(Array(hexes.prefix(maximumStops))) else { return }
        defaults.set(data, forKey: AppSettingsKeys.gradientStops)
        // JSON in UserDefaults is invisible to @AppStorage, so bump a plain
        // integer alongside it for views to observe.
        defaults.set(defaults.integer(forKey: AppSettingsKeys.paletteRevision) + 1,
                     forKey: AppSettingsKeys.paletteRevision)
    }

    // MARK: - Derived values

    var gradient: LinearGradient {
        LinearGradient(colors: stops, startPoint: startPoint, endPoint: endPoint)
    }

    /// Angle → the two unit points SwiftUI wants. Vector (sin, cos) puts 0° at
    /// straight down because UnitPoint's y axis grows downward.
    var startPoint: UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 - sin(radians) / 2, y: 0.5 - cos(radians) / 2)
    }

    var endPoint: UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 + sin(radians) / 2, y: 0.5 + cos(radians) / 2)
    }

    /// One representative color, for places that can't take a gradient: the
    /// glass tint, the leading glyph, the row highlight. It's the middle stop
    /// rather than the first, so a palette's character survives the reduction.
    var tint: Color {
        stops.isEmpty ? .accentColor : stops[stops.count / 2]
    }

    /// Perceived brightness of each stop.
    private var stopLuminances: [Double] {
        stops.compactMap { color in
            guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return nil }
            return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        }
    }

    /// Mean perceived brightness across every stop.
    var luminance: Double {
        let values = stopLuminances
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// What the text color is actually decided on: mostly the mean, pulled up
    /// by the brightest stop.
    ///
    /// The mean alone reads a gradient as more legible than it is — Citrus
    /// (yellow → red) averages to a comfortable 0.65 and was handed white
    /// text, which then crossed the yellow end and vanished. Letting the
    /// brightest stop carry 30% of the vote flips exactly those palettes to
    /// dark text while leaving saturated mid-tone ones (the four-color Goorgle
    /// preset, the default blue) white, the way a Material search bar reads.
    var textDecisionBrightness: Double {
        let values = stopLuminances
        guard let brightest = values.max() else { return 0 }
        return luminance * 0.7 + brightest * 0.3
    }

    /// Text color for content drawn on this palette.
    func foreground(for theme: AppTheme) -> Color {
        switch textMode {
        case .light: return .white
        case .dark: return Color.black.opacity(0.85)
        case .auto:
            switch theme {
            // Glass shows the desktop, not the palette, so the system label
            // color is the readable choice there.
            case .liquidGlass: return .primary
            case .gradient: return textDecisionBrightness > Self.darkTextThreshold
                ? Color.black.opacity(0.85)
                : .white
            }
        }
    }

    /// Selected/hovered row wash.
    func highlight(for theme: AppTheme, strength: Double) -> Color {
        switch theme {
        case .gradient: return foreground(for: theme).opacity(strength)
        case .liquidGlass: return tint.opacity(strength * 1.4)
        }
    }
}
