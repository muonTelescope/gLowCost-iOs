import SwiftUI

/// A rectangle with 45° cut corners instead of rounded ones.
///
/// The same shape is used to fill, clip and stroke a surface, so the 1 px
/// hairline follows every cut, diagonals included (the mockup's "ring layer";
/// never a border clipped by a second shape). `InsettableShape` keeps the
/// diagonals parallel when SwiftUI insets the path for `strokeBorder`.
struct ChamferedShape: InsettableShape {
    var topLeading: CGFloat = 0
    var topTrailing: CGFloat = 0
    var bottomTrailing: CGFloat = 0
    var bottomLeading: CGFloat = 0
    var inset: CGFloat = 0

    init(topLeading: CGFloat = 0, topTrailing: CGFloat = 0, bottomTrailing: CGFloat = 0, bottomLeading: CGFloat = 0) {
        self.topLeading = topLeading; self.topTrailing = topTrailing
        self.bottomTrailing = bottomTrailing; self.bottomLeading = bottomLeading
    }

    /// Cards and panels: top-right and bottom-left cut.
    static func panel(_ cut: CGFloat = Chamfer.panel) -> ChamferedShape { ChamferedShape(topTrailing: cut, bottomLeading: cut) }
    /// Buttons, chips, tabs, the tab bar: all four corners cut.
    static func control(_ cut: CGFloat = Chamfer.control) -> ChamferedShape { ChamferedShape(topLeading: cut, topTrailing: cut, bottomTrailing: cut, bottomLeading: cut) }
    static var chip: ChamferedShape { control(Chamfer.chip) }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        guard r.width > 0, r.height > 0 else { return Path() }
        // Offsetting a 45° cut inward by d shortens its legs by d·(2 − √2).
        let shrink = inset * (2 - 2.0.squareRoot())
        let limit = min(r.width, r.height) / 2
        func c(_ v: CGFloat) -> CGFloat { v <= 0 ? 0 : min(limit, max(0, v - shrink)) }
        let tl = c(topLeading), tr = c(topTrailing), br = c(bottomTrailing), bl = c(bottomLeading)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + tr))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        p.addLine(to: CGPoint(x: r.maxX - br, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - bl))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> ChamferedShape {
        var s = self; s.inset += amount; return s
    }
}

/// Cut sizes in points (design: panels 14, controls 8–10, chips 4).
enum Chamfer {
    static let panel: CGFloat = 14
    static let control: CGFloat = 9
    static let button: CGFloat = 10
    static let chip: CGFloat = 4
}

enum PanelEdge { case hairline, bright, none }

/// Solid card: panel fill with a faint lighter top sheen and a 1 px edge along the cuts.
/// Cards stay solid (no blur) so numbers stay easy to read.
struct Panel: ViewModifier {
    var padding: CGFloat = 14
    var edge: PanelEdge = .hairline
    var cut: CGFloat = Chamfer.panel
    var fill: Color = Palette.panel

    func body(content: Content) -> some View {
        let shape = ChamferedShape.panel(cut)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(LinearGradient(stops: [.init(color: fill == Palette.panel ? Palette.panelSheen : fill, location: 0),
                                                  .init(color: fill, location: 0.35)],
                                          startPoint: .top, endPoint: .bottom))
            }
            .overlay { if edge != .none { shape.strokeBorder(edge == .bright ? Palette.brightEdge : Palette.hairline, lineWidth: 1) } }
            .contentShape(shape)
    }
}

/// Frosted glass, only for floating elements: the tab bar, the logging bar, chart tooltips and sheets.
struct ChamferGlass: ViewModifier {
    var shape: ChamferedShape = .control()
    var edge: Color = Palette.hairline
    func body(content: Content) -> some View {
        content
            .background { ZStack { shape.fill(.ultraThinMaterial); shape.fill(Palette.ground.opacity(0.55)) } }
            .overlay { shape.strokeBorder(edge, lineWidth: 1) }
            .clipShape(shape)
    }
}

extension View {
    /// Standard card (the old `.card()` call sites keep working).
    func card(padding: CGFloat = 14, edge: PanelEdge = .hairline) -> some View { modifier(Panel(padding: padding, edge: edge)) }
    func panel(padding: CGFloat = 14, edge: PanelEdge = .hairline, cut: CGFloat = Chamfer.panel, fill: Color = Palette.panel) -> some View {
        modifier(Panel(padding: padding, edge: edge, cut: cut, fill: fill))
    }
    func chamferGlass(_ shape: ChamferedShape = .control(), edge: Color = Palette.hairline) -> some View { modifier(ChamferGlass(shape: shape, edge: edge)) }
    /// Clip and outline anything (maps, images) with a cut-corner shape.
    func chamferClip(_ shape: ChamferedShape = .panel(), edge: Color? = Palette.hairline) -> some View {
        clipShape(shape).overlay { if let edge { shape.strokeBorder(edge, lineWidth: 1) } }
    }
}

// MARK: buttons

/// Primary action: light-to-deep violet with a lilac edge.
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let shape = ChamferedShape.control(Chamfer.button)
        configuration.label
            .font(Typography.raleway(17, .bold, relativeTo: .headline))
            .foregroundStyle(Palette.buttonInk)
            .padding(.horizontal, 18).padding(.vertical, fullWidth ? 14 : 10)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background { shape.fill(LinearGradient(colors: [Palette.buttonTop, Palette.buttonBottom], startPoint: .top, endPoint: .bottom)) }
            .overlay { shape.strokeBorder(Palette.buttonEdge, lineWidth: 1) }
            .contentShape(shape)
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// Secondary action on a raised panel.
struct SecondaryButtonStyle: ButtonStyle {
    var fullWidth = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let shape = ChamferedShape.control(Chamfer.control)
        configuration.label
            .font(Typography.raleway(15, .semibold, relativeTo: .subheadline))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background { shape.fill(configuration.isPressed ? Palette.hairline : Palette.raised) }
            .overlay { shape.strokeBorder(Palette.hairline, lineWidth: 1) }
            .contentShape(shape)
            .opacity(enabled ? 1 : 0.4)
    }
}

/// Destructive action (Turn HV off, Forget MuonP4): the only buttons that use pink.
struct DestructiveButtonStyle: ButtonStyle {
    var fullWidth = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let shape = ChamferedShape.control(Chamfer.control)
        configuration.label
            .font(Typography.raleway(15, .semibold, relativeTo: .subheadline))
            .foregroundStyle(Palette.pink)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background { shape.fill(Palette.pink.opacity(configuration.isPressed ? 0.22 : 0.12)) }
            .overlay { shape.strokeBorder(Palette.pink.opacity(0.55), lineWidth: 1) }
            .contentShape(shape)
            .opacity(enabled ? 1 : 0.4)
    }
}

/// Small square icon button (steppers, edit pencil, toolbar-like actions inside content).
struct IconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let shape = ChamferedShape.control(Chamfer.chip + 2)
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.lilac)
            .frame(minWidth: 36, minHeight: 36)
            .background { shape.fill(configuration.isPressed ? Palette.hairline : Palette.raised) }
            .overlay { shape.strokeBorder(Palette.hairline, lineWidth: 1) }
            .contentShape(shape)
            .opacity(enabled ? 1 : 0.4)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var muonPrimary: PrimaryButtonStyle { .init() }
    static var muonPrimaryCompact: PrimaryButtonStyle { .init(fullWidth: false) }
}
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var muonSecondary: SecondaryButtonStyle { .init() }
    static var muonSecondaryCompact: SecondaryButtonStyle { .init(fullWidth: false) }
}
extension ButtonStyle where Self == DestructiveButtonStyle {
    static var muonDestructive: DestructiveButtonStyle { .init() }
    static var muonDestructiveCompact: DestructiveButtonStyle { .init(fullWidth: false) }
}
extension ButtonStyle where Self == IconButtonStyle { static var muonIcon: IconButtonStyle { .init() } }
