import SwiftUI

/// One bar per minute; -1 draws a short grey dash for a missing minute.
/// Built from shapes (not Canvas) so it also renders in widgets and Live Activities.
struct MinuteBars: View {
    let values: [Int]
    var tint: Color = Palette.accent
    var highlightLast = true
    var body: some View {
        GeometryReader { geo in
            let maxV = CGFloat(max(1, values.max() ?? 1))
            let n = max(values.count, 1)
            let slot = geo.size.width / CGFloat(n)
            HStack(alignment: .bottom, spacing: slot * 0.4) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    if v < 0 {
                        Capsule().fill(Palette.secondaryText.opacity(0.5)).frame(width: slot * 0.6, height: 1.5)
                    } else {
                        Capsule().fill(tint.opacity(highlightLast && i == n - 1 ? 1 : 0.45))
                            .frame(width: slot * 0.6, height: max(2, geo.size.height * CGFloat(v) / maxV))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
        .accessibilityElement()
        .accessibilityLabel("Coincidences per minute")
        .accessibilityValue(values.filter { $0 >= 0 }.suffix(5).map(String.init).joined(separator: ", "))
    }
}
