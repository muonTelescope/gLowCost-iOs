import SwiftUI

/// Outreach image: the muon lines, the count, where and when.
struct ShareCard: View {
    let count: Int
    let caption: String
    let place: String
    let date: Date
    let seed: UInt64

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(UIColor(hex: 0x0C1120))
            TrackPlate(count: count, seed: seed, animated: false).environment(\.colorScheme, .dark)
            LinearGradient(colors: [.clear, Color(UIColor(hex: 0x0C1120)).opacity(0.95)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text(caption.uppercased()).font(.system(size: 13, weight: .semibold)).tracking(1).foregroundStyle(Color(UIColor(hex: 0xA9B8D6)))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(count)").font(.system(size: 120, weight: .light, design: .rounded)).monospacedDigit()
                    Text("muons").font(.title2).foregroundStyle(Color(UIColor(hex: 0xA9B8D6)))
                }
                Text("\(place) · \(date.formatted(date: .abbreviated, time: .shortened))").font(.headline).foregroundStyle(Color(UIColor(hex: 0xA9B8D6)))
                Text("Counted by a gLOWCOST scintillator telescope").font(.footnote).foregroundStyle(Color(UIColor(hex: 0x6B7383)))
            }
            .foregroundStyle(.white).padding(32)
        }
        .frame(width: 1080 / 3, height: 1350 / 3)
    }
}

struct ShareCardSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var run: Run? = nil
    @State private var place = ""
    @State private var image: Image?

    private var card: ShareCard {
        if let run {
            let phys = run.records.filter(\.physics)
            return ShareCard(count: phys.reduce(0) { $0 + $1.coincidences }, caption: "\(run.name) · \((Double(phys.count) * 60).hoursMinutes)",
                             place: place, date: run.start, seed: UInt64(run.start.timeIntervalSince1970))
        }
        let last = app.recent.last
        return ShareCard(count: last?.coincidences ?? 0, caption: "In one minute", place: place, date: last?.date ?? Date(),
                         seed: UInt64(bitPattern: Int64(last?.epoch ?? 0)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                card.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)).shadow(radius: 12)
                TextField("Place, e.g. Magnolia", text: $place).textFieldStyle(.roundedBorder).padding(.horizontal, 40)
                if let image {
                    ShareLink(item: image, preview: SharePreview("Muons", image: image)) {
                        Label("Share image", systemImage: "square.and.arrow.up").frame(maxWidth: 260)
                    }.buttonStyle(.glassProminent)
                }
            }
            .padding()
            .navigationTitle("Share").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: place) { render() }
        }
    }

    @MainActor private func render() {
        let r = ImageRenderer(content: card)
        r.scale = 3
        if let ui = r.uiImage { image = Image(uiImage: ui) }
    }
}
