import SwiftUI
import AppKit

/// The two looks the search panel can wear.
///
/// `gradient` is the original Android-style pill: an opaque capsule filled
/// with the accent color. `liquidGlass` swaps that for a translucent surface
/// that refracts the desktop behind it, tinted by the same accent — the accent
/// picker keeps meaning something either way.
enum AppTheme: String, CaseIterable, Identifiable {
    case gradient
    case liquidGlass

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gradient: return "Gradient"
        case .liquidGlass: return "Liquid Glass"
        }
    }

    static func stored(_ raw: String) -> AppTheme {
        AppTheme(rawValue: raw) ?? .gradient
    }

    /// Colors live on `PanelPalette`, not here: the theme decides how a
    /// surface is *painted*, the palette decides what it's painted with.
}

/// Shape of a panel surface — spelled out rather than generic so it can be
/// handed to both `glassEffect(in:)` and a `clipShape`.
enum PanelShape {
    case capsule
    case rounded(CGFloat)

    var shape: AnyShape {
        switch self {
        case .capsule: return AnyShape(Capsule())
        case .rounded(let radius): return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

extension View {
    /// Applies the themed background, border and shadow for one panel surface.
    func panelSurface(
        theme: AppTheme,
        palette: PanelPalette,
        shape: PanelShape,
        tint: Double = 0.3,
        shadow: Double = 0.28,
        shadowRadius: CGFloat = 14
    ) -> some View {
        modifier(PanelSurface(
            theme: theme, palette: palette, shape: shape,
            tint: tint, shadow: shadow, shadowRadius: shadowRadius
        ))
    }
}

private struct PanelSurface: ViewModifier {
    let theme: AppTheme
    let palette: PanelPalette
    let shape: PanelShape
    let tint: Double
    let shadow: Double
    let shadowRadius: CGFloat

    func body(content: Content) -> some View {
        switch theme {
        case .gradient:
            content
                .background(shape.shape.fill(palette.gradient))
                .overlay(shape.shape.stroke(borderGradient, lineWidth: 1))
                .shadow(color: .black.opacity(shadow), radius: shadowRadius, y: shadowRadius / 2)
        case .liquidGlass:
            glass(content)
        }
    }

    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // The real thing: Liquid Glass refracts and specularly highlights
            // what's behind the window, so it needs no border or heavy shadow
            // of its own — adding them just muddies it.
            content
                .glassEffect(.regular.tint(palette.tint.opacity(tint * 0.55)).interactive(), in: shape.shape)
                .shadow(color: .black.opacity(shadow * 0.5), radius: shadowRadius * 0.8, y: shadowRadius / 3)
        } else {
            // macOS 15 has no Liquid Glass, so approximate it with the
            // longstanding blur material plus an accent wash and a hairline —
            // the border matters here precisely because this fallback has no
            // specular edge of its own.
            content
                .background {
                    VisualEffectBackground(material: .hudWindow)
                        .overlay(palette.tint.opacity(tint * 0.42))
                        .clipShape(shape.shape)
                }
                .overlay(shape.shape.stroke(borderGradient, lineWidth: 1))
                .shadow(color: .black.opacity(shadow * 0.7), radius: shadowRadius, y: shadowRadius / 3)
        }
    }

    private var borderGradient: LinearGradient {
        let edge = palette.foreground(for: theme)
        return LinearGradient(
            colors: [edge.opacity(0.45), edge.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// `NSVisualEffectView` bridge for the pre-macOS-26 glass fallback.
///
/// `.behindWindow` blending is what samples the desktop rather than the app's
/// own backdrop — it works here only because the panel is a transparent,
/// non-opaque window.
private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
