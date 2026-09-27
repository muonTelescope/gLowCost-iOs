import SwiftUI
import UIKit

/// "Violet & phosphor" design tokens (design/ios-redesign-plan.md).
/// The app is dark-only; widgets and the Live Activity use the same values.
///
/// Colour jobs:
/// - violet: structure, pressure, buttons
/// - lilac: muon tracks, setup state
/// - phosphor green: live data (counts, bars, rate lines, physics state, temperature, map ramp)
/// - pink: alerts and destructive actions only
enum Palette {
    // Grounds
    static let ground = hex(0x120E1A)
    static let panel = hex(0x1C1628)
    static let panelSheen = hex(0x231C33)     // top of the panel gradient
    static let raised = hex(0x261E35)
    static let hairline = hex(0x3A2F4F)
    static let brightEdge = hex(0x5E4A93)     // hero card, selected controls
    // Ink
    static let ink = hex(0xEEE9F5)
    static let muted = hex(0xA89CBF)
    // Accents
    static let violet = hex(0x9B7BFF)
    static let lilac = hex(0xC9B6FF)
    static let phosphor = hex(0x5BE3A0)
    static let pink = hex(0xFF8FB1)
    // Primary button
    static let buttonTop = hex(0xAE93FF)
    static let buttonBottom = hex(0x8462F0)
    static let buttonEdge = hex(0xC9B6FF)
    static let buttonInk = hex(0x16101F)

    // MARK: semantic names used throughout the views

    static let background = ground
    static let card = panel
    static let cardRaised = raised
    static let hero = hex(0x161120)
    static let track = lilac
    static let accent = violet
    static let accentSoft = lilac
    static let pressure = violet
    static let temperature = phosphor
    static let physics = phosphor
    static let data = phosphor
    static let setup = lilac
    /// Alerts: overdue, failed checks, noisy counting. Never used for tags or labels.
    static let alert = pink
    static let danger = pink
    static let warning = pink
    static let secondaryText = muted
    static let grid = hex(0x2A2238)
    static let raw = muted

    /// Line colours for the three coincidence pairs (CH⁰₁, CH⁰₂, CH¹₂), all read as "data".
    static let pairs: [Color] = [phosphor, hex(0xA6F5CF), lilac]

    /// Sequential ramp for rate-coloured map tracks (low → high), phosphor green.
    static let ramp: [Color] = ([0x1E4A3A, 0x2A7358, 0x3A9F77, 0x5BE3A0, 0xB4F7D6] as [UInt32]).map { hex($0) }

    static func hex(_ v: UInt32) -> Color { Color(UIColor(hex: v)) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The detector's state for one completed minute, as shown everywhere.
enum Phase: String, Codable, Hashable {
    case searching, connecting, setup, settling, physics, overdue, stopped
    var title: String {
        switch self {
        case .searching: "Looking for MuonP4"
        case .connecting: "Connecting"
        case .setup: "Setup"
        case .settling: "HV settling"
        case .physics: "Physics run"
        case .overdue: "Update overdue"
        case .stopped: "Not logging"
        }
    }
    var tint: Color {
        switch self {
        case .physics: Palette.physics
        case .setup, .settling: Palette.setup
        case .overdue: Palette.alert
        default: Palette.secondaryText
        }
    }
}
