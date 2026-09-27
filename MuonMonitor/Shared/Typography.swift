import SwiftUI
import UIKit
import CoreText

/// Raleway (titles, headings, body) and IBM Plex Mono (counts, units, caps labels).
///
/// Both are bundled (Resources/Fonts, SIL OFL 1.1) and registered through
/// UIAppFonts in the app and widget Info.plists. Raleway ships as the unmodified
/// variable font `Raleway[wght].ttf`, so weights are set on the `wght` axis, and
/// lining figures are switched on so numbers in Raleway text sit on the baseline.
/// Everything scales with Dynamic Type relative to a text style, and falls back
/// to the system font if a file is missing.
enum Typography {
    enum Weight: CGFloat { case regular = 400, medium = 500, semibold = 600, bold = 700, heavy = 800 }

    // MARK: Raleway

    static func raleway(_ size: CGFloat, _ weight: Weight = .medium, relativeTo style: Font.TextStyle = .body) -> Font {
        guard let base = ralewayUIFont(size: size, weight: weight) else {
            return .system(size: size, weight: systemWeight(weight)).leading(.standard)
        }
        let scaled = UIFontMetrics(forTextStyle: uiStyle(style)).scaledFont(for: base)
        return Font(scaled as CTFont)
    }

    /// Variable-axis Raleway with lining numerals, or nil when the font is not registered.
    static func ralewayUIFont(size: CGFloat, weight: Weight) -> UIFont? {
        let key = "\(size)-\(weight.rawValue)"
        if let f = cache[key] { return f }
        let wghtAxis = 0x7767_6874  // 'wght'
        let attributes: [UIFontDescriptor.AttributeName: Any] = [
            .family: "Raleway",
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wghtAxis: weight.rawValue],
            .featureSettings: [[UIFontDescriptor.FeatureKey.type: kNumberCaseType,
                                UIFontDescriptor.FeatureKey.selector: kUpperCaseNumbersSelector]],
        ]
        let font = UIFont(descriptor: UIFontDescriptor(fontAttributes: attributes), size: size)
        guard font.familyName == "Raleway" else { return nil }
        cache[key] = font
        return font
    }
    nonisolated(unsafe) private static var cache: [String: UIFont] = [:]

    // MARK: IBM Plex Mono

    enum MonoWeight: String { case regular = "IBMPlexMono-Regular", medium = "IBMPlexMono-Medium", semibold = "IBMPlexMono-SemiBold" }

    static func mono(_ size: CGFloat, _ weight: MonoWeight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }
    /// Fixed-size mono for places that must not grow (Dynamic Island compact regions).
    static func monoFixed(_ size: CGFloat, _ weight: MonoWeight = .regular) -> Font { .custom(weight.rawValue, fixedSize: size) }

    // MARK: named styles

    static var largeTitle: Font { raleway(34, .heavy, relativeTo: .largeTitle) }
    static var title: Font { raleway(28, .heavy, relativeTo: .title) }
    static var title2: Font { raleway(22, .bold, relativeTo: .title2) }
    static var headline: Font { raleway(17, .bold, relativeTo: .headline) }
    static var subheadline: Font { raleway(15, .semibold, relativeTo: .subheadline) }
    static var body: Font { raleway(16, .medium, relativeTo: .body) }
    static var footnote: Font { raleway(13, .medium, relativeTo: .footnote) }
    static var caption: Font { raleway(12, .medium, relativeTo: .caption) }
    /// Caps labels ("PRESSURE", "COINCIDENCES, LAST MINUTE"): mono, tracked.
    static var capsLabel: Font { mono(11, .medium, relativeTo: .caption2) }
    static var monoCaption: Font { mono(12, .regular, relativeTo: .caption) }
    static var monoBody: Font { mono(15, .regular, relativeTo: .body) }
    static var monoValue: Font { mono(22, .medium, relativeTo: .title3) }
    static var monoLarge: Font { mono(30, .medium, relativeTo: .title) }

    // MARK: UIKit (navigation bar titles)

    static func uiRaleway(_ size: CGFloat, _ weight: Weight) -> UIFont {
        ralewayUIFont(size: size, weight: weight) ?? .systemFont(ofSize: size, weight: weight.rawValue >= 700 ? .bold : .semibold)
    }

    /// Navigation titles in Raleway 800 / 700, ink on the violet ground.
    @MainActor static func styleNavigationBars() {
        let ink = UIColor(hex: 0xEEE9F5)
        let large = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: uiRaleway(34, .heavy))
        let inline = UIFontMetrics(forTextStyle: .headline).scaledFont(for: uiRaleway(17, .bold))
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: large, .foregroundColor: ink]
        nav.titleTextAttributes = [.font: inline, .foregroundColor: ink]
    }

    private static func systemWeight(_ w: Weight) -> Font.Weight {
        switch w { case .regular: .regular; case .medium: .medium; case .semibold: .semibold; case .bold: .bold; case .heavy: .heavy }
    }
    private static func uiStyle(_ s: Font.TextStyle) -> UIFont.TextStyle {
        switch s {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

extension View {
    /// Tracked mono caps label, e.g. "PRESSURE, HPA".
    func capsLabel(_ color: Color = Palette.muted) -> some View {
        font(Typography.capsLabel).tracking(1).textCase(.uppercase).foregroundStyle(color)
    }
}
