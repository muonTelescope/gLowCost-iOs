import Foundation
import SwiftUI

/// Default tag vocabulary plus the user's own tags. Tags are plain strings on
/// the run, so custom tags need no schema change.
enum TagCatalog {
    struct Group: Identifiable { let id: String; let tags: [String]; let tint: Color }

    static let groups: [Group] = [
        Group(id: "Power", tags: ["Mains", "Power bank", "Internal battery"], tint: Palette.pressure),
        Group(id: "Radio", tags: ["Wi‑Fi on", "Wi‑Fi auto-off"], tint: Palette.accent),
        Group(id: "Place", tags: ["Indoors", "Outdoors", "Vehicle", "Flight", "Underground"], tint: Palette.temperature),
        Group(id: "Purpose", tags: ["Test", "Calibration", "Outreach"], tint: Palette.setup),
    ]
    static var defaults: [String] { groups.flatMap(\.tags) }

    private static let key = "customTags"
    static var custom: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(Array(Set(newValue)).sorted(), forKey: key) }
    }
    static func addCustom(_ tag: String) {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !defaults.contains(t) else { return }
        custom = custom + [t]
    }
    static func tint(for tag: String) -> Color {
        groups.first { $0.tags.contains(tag) }?.tint ?? Palette.secondaryText
    }
    static func isFlight(_ tags: [String]) -> Bool { tags.contains("Flight") }
}
