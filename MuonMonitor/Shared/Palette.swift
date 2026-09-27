import SwiftUI
import UIKit

/// Colours from the redesign mockup. Each has a dark and a light value so the
/// app follows the system appearance.
enum Palette {
    private static func dyn(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    static let background = dyn(0x07090D, 0xF4F6FA)
    static let card = dyn(0x121722, 0xFFFFFF)
    static let cardRaised = dyn(0x1A2030, 0xEEF1F6)
    static let hero = dyn(0x0C1120, 0xE8EEFB)
    static let track = dyn(0x8FB0FF, 0x2F63E0)
    static let accent = dyn(0x5B8CFF, 0x2F63E0)
    static let accentSoft = dyn(0x8FB0FF, 0x2F63E0)
    static let pressure = dyn(0xF2A33A, 0xB86E00)
    static let temperature = dyn(0x3CC8B4, 0x0E8A7A)
    static let physics = dyn(0x4CD07D, 0x1F8F4E)
    static let setup = dyn(0xC9A6FF, 0x7446C9)
    static let warning = dyn(0xF5B75E, 0xA35F00)
    static let danger = dyn(0xFF6B5B, 0xC73A2E)
    static let secondaryText = dyn(0x8A93A4, 0x5C6574)
    static let grid = dyn(0x1F2533, 0xE3E7EF)
    static let raw = dyn(0x6B7383, 0x9AA2B1)
    /// Sequential ramp for rate-coloured map tracks (low → high).
    static let ramp: [Color] = [0xB7D3F6, 0x86B6EF, 0x5598E7, 0x2A78D6, 0x1C5CAB].map { Color(UIColor(hex: $0)) }
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
        case .overdue: Palette.danger
        default: Palette.secondaryText
        }
    }
}
