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
            Palette.hero
            TrackPlate(count: count, seed: seed, animated: false)
            // Same fade as the Now hero: tracks dissolve before they reach the text.
            LinearGradient(stops: [.init(color: .clear, location: 0.2), .init(color: Palette.ground.opacity(0.85), location: 0.5),
                                   .init(color: Palette.ground, location: 0.62)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text(caption.uppercased()).font(Typography.monoFixed(12, .medium)).tracking(1.2).foregroundStyle(Palette.muted).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(count)").font(Typography.monoFixed(96, .medium)).foregroundStyle(Palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.4)
                    Text("muons").font(Typography.monoFixed(20, .regular)).foregroundStyle(Palette.data)
                }
                Text(place.isEmpty ? date.formatted(date: .abbreviated, time: .shortened) : "\(place) · \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(Typography.raleway(17, .bold)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    MuonMark(size: 14, color: Palette.lilac)
                    Text("Counted by a gLOWCOST scintillator telescope").font(Typography.raleway(13, .medium)).foregroundStyle(Palette.muted)
                }
            }
            .padding(28)
        }
        .frame(width: 1080 / 3, height: 1350 / 3)
        .chamferClip(.panel(22), edge: Palette.brightEdge)
        .environment(\.colorScheme, .dark)
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
                card.shadow(color: .black.opacity(0.5), radius: 12)
                TextField("Place, e.g. Magnolia", text: $place).font(Typography.body)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Palette.raised, in: ChamferedShape.control())
                    .overlay { ChamferedShape.control().strokeBorder(Palette.hairline, lineWidth: 1) }
                    .padding(.horizontal, 40)
                if let image {
                    ShareLink(item: image, preview: SharePreview("Muons", image: image)) {
                        Label("Share image", systemImage: "square.and.arrow.up").frame(maxWidth: 260)
                    }.buttonStyle(.muonPrimary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
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
