import SwiftUI
import UIKit

/// App palette, light + dark (follows the system). Dark is the PlutoFish mini-app palette; light is its
/// counterpart (white surfaces on a soft grey ground). Brand blue marks focus and playback progress.
/// Screens that must stay dark (player, image viewer, manga reader) force `.preferredColorScheme(.dark)`,
/// so the same tokens resolve to the dark values there.
enum STVTheme {
    static let bg = adaptive(light: (0.957, 0.961, 0.969), dark: (0.067, 0.075, 0.090))
    static let surface = adaptive(light: (1, 1, 1), dark: (0.110, 0.122, 0.145))
    static let elevated = adaptive(light: (0.910, 0.918, 0.933), dark: (0.224, 0.239, 0.259))
    static let text = adaptive(light: (0.071, 0.078, 0.094), dark: (0.933, 0.941, 0.953))
    static let secondary = adaptive(light: (0.373, 0.400, 0.447), dark: (0.68, 0.71, 0.75))
    static let accent = adaptive(light: (0.12, 0.36, 0.73), dark: (0.56, 0.77, 1))
    static let accentWarm = adaptive(light: (0.835, 0.522, 0.078), dark: (0.949, 0.710, 0.361))

    // MARK: Redesign tokens (ui-redesign/styles.css — every value has a light and a dark variant)
    /// Third-level text: dimension labels, hints, timestamps.
    static let tertiary = rgba(light: (95, 102, 114, 0.68), dark: (173, 181, 191, 0.62))
    /// Unselected control ground (chips, segmented track, round buttons).
    static let glass = rgba(light: (18, 20, 24, 0.055), dark: (238, 240, 243, 0.07))
    static let glassBorder = rgba(light: (18, 20, 24, 0.10), dark: (238, 240, 243, 0.12))
    /// 1 px separators between rows / around the segmented track.
    static let hairline = rgba(light: (18, 20, 24, 0.07), dark: (238, 240, 243, 0.08))
    static let accentSoft = rgba(light: (40, 109, 239, 0.10), dark: (138, 180, 255, 0.16))
    static let accentLine = rgba(light: (40, 109, 239, 0.36), dark: (138, 180, 255, 0.42))
    /// Text / icon on a solid accent fill.
    static let onAccent = rgba(light: (255, 255, 255, 1), dark: (13, 27, 54, 1))
    static let warmSoft = rgba(light: (213, 133, 20, 0.12), dark: (242, 181, 92, 0.15))
    static let ok = rgba(light: (30, 158, 87, 1), dark: (95, 208, 138, 1))
    static let okSoft = rgba(light: (30, 158, 87, 0.12), dark: (95, 208, 138, 0.14))
    /// Cards: translucent in dark, white + soft shadow in light.
    static let card = rgba(light: (255, 255, 255, 1), dark: (238, 240, 243, 0.055))
    static let cardBorder = rgba(light: (18, 20, 24, 0.06), dark: (238, 240, 243, 0.10))
    /// Selected thumb of the segmented control and neutral ("全部") chips.
    static let thumb = rgba(light: (255, 255, 255, 1), dark: (238, 240, 243, 0.16))
    /// Floating bars (tab bar, sticky filter, play bar) under the blur.
    static let bar = rgba(light: (255, 255, 255, 0.80), dark: (24, 27, 33, 0.72))
    static let sheet = rgba(light: (255, 255, 255, 1), dark: (28, 31, 37, 1))
    static let rail = rgba(light: (18, 20, 24, 0.035), dark: (238, 240, 243, 0.035))
    static let gold = rgba(light: (219, 154, 0, 1), dark: (255, 199, 64, 1))
    static let silver = rgba(light: (135, 147, 173, 1), dark: (199, 209, 230, 1))
    static let bronze = rgba(light: (197, 115, 58, 1), dark: (219, 140, 82, 1))
    /// Pinned headers: page colour at 80 % under the blur.
    static let pin = rgba(light: (244, 245, 247, 0.80), dark: (17, 19, 23, 0.80))
    static let dim = rgba(light: (18, 20, 24, 0.34), dark: (0, 0, 0, 0.52))
    /// Card / thumb shadows only exist in light mode (dark relies on borders).
    static let shadowSoft = rgba(light: (18, 20, 24, 0.06), dark: (0, 0, 0, 0))
    static let shadowThumb = rgba(light: (18, 20, 24, 0.10), dark: (0, 0, 0, 0))
    static let barShadow = rgba(light: (18, 20, 24, 0.12), dark: (0, 0, 0, 0.30))
    /// Top-of-page ambient glow (warm on 首页 / 找剧, cool on 小说 sub-pages).
    static let ambientWarm = [rgba(light: (213, 133, 20, 0.17), dark: (150, 92, 62, 0.58)),
                              rgba(light: (213, 133, 20, 0.06), dark: (96, 60, 50, 0.30))]
    static let ambientCool = [rgba(light: (40, 109, 239, 0.15), dark: (72, 104, 168, 0.34)),
                              rgba(light: (40, 109, 239, 0.05), dark: (40, 56, 92, 0.16))]
    static func rankColor(_ r: Int) -> Color { r == 1 ? gold : r == 2 ? silver : r == 3 ? bronze : tertiary }

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(UIColor { t in
            let c = t.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
    private static func rgba(light: (Double, Double, Double, Double), dark: (Double, Double, Double, Double)) -> Color {
        Color(UIColor { t in
            let c = t.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: c.3)
        })
    }
}

enum STVAppearance: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct STVGlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

private struct STVGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let backing: Color
    let interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(backing, in: shape)
                .overlay { shape.strokeBorderFallback(.white.opacity(0.16)) }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content.background {
                shape.fill(.ultraThinMaterial)
                    .overlay { shape.fill(tint ?? .clear) }
            }
            .overlay { shape.strokeBorderFallback(STVTheme.glassBorder) }
        }
    }
}

private extension Shape {
    func strokeBorderFallback(_ color: Color) -> some View {
        stroke(color, lineWidth: 0.8).allowsHitTesting(false)
    }
}

extension View {
    func stvGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        backing: Color = STVTheme.surface,
        interactive: Bool = false
    ) -> some View {
        modifier(STVGlassSurface(shape: shape, tint: tint, backing: backing, interactive: interactive))
    }
}
struct GlassChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(ToneChipStyle(on: selected))
    }
}

struct GlassChipBar<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { it in
                    GlassChip(title: label(it), selected: selection == it) { selection = it }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
