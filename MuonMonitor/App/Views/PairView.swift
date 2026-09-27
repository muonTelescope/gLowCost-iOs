import SwiftUI

/// First run: find a nearby MuonP4 and pair with it, or explore the demo instead.
struct PairView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppHost.self) private var host
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    radar.frame(height: 220).frame(maxWidth: .infinity)
                    Text("Find your detector").font(Typography.largeTitle).lineLimit(1).minimumScaleFactor(0.8)
                    Text("Power on the telescope. It announces itself over Bluetooth every 15 seconds, so it can take a moment to appear.")
                        .font(Typography.body).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                    if app.link.nearby.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView().tint(Palette.lilac)
                            Text("Looking for MuonP4…").font(Typography.subheadline).foregroundStyle(Palette.secondaryText)
                        }.card()
                    }
                    ForEach(app.link.nearby) { d in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "cpu").font(.system(size: 20, weight: .medium)).foregroundStyle(Palette.lilac)
                                    .frame(width: 46, height: 46)
                                    .background(Palette.violet.opacity(0.16), in: ChamferedShape.control(Chamfer.button))
                                    .overlay { ChamferedShape.control(Chamfer.button).strokeBorder(Palette.hairline, lineWidth: 1) }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).font(Typography.headline)
                                    Text(d.lastMinute.map { "Nearby · last minute \($0) coincidences" } ?? "Nearby")
                                        .font(Typography.footnote).foregroundStyle(Palette.secondaryText).lineLimit(2)
                                }
                                Spacer(minLength: 6)
                                Image(systemName: "cellularbars", variableValue: min(1, max(0, Double(d.rssi + 100) / 50)))
                                    .foregroundStyle(Palette.lilac)
                                    .accessibilityLabel("Signal \(d.rssi) dBm")
                            }
                            Button {
                                app.link.remember(d.id)
                                app.start(); dismiss()
                            } label: { Text("Connect and pair") }
                                .buttonStyle(.muonPrimary)
                            Text("iOS may ask to pair when it connects. Pairing encrypts detector commands. It does not stop another phone from pairing too.")
                                .font(Typography.caption).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                        }
                        .card(padding: 16, edge: .bright)
                    }
                    VStack(spacing: 0) {
                        permission("Bluetooth", app.link.state == .unauthorized ? "Not allowed" : "Allowed")
                        RowDivider()
                        permission("Location, to tag each minute", app.location.permissionText)
                    }.card(padding: 0)

                    // No hardware at hand: explore generated data without touching stored runs.
                    Button {
                        dismiss()
                        host.enterDemo()
                    } label: { Label("Try the demo instead", systemImage: "wand.and.stars") }
                        .buttonStyle(.muonSecondary)
                        .disabled(app.logging || app.demo)
                    Text("The demo uses generated data and an in-memory store. Leave it any time in Settings.")
                        .font(Typography.caption).foregroundStyle(Palette.secondaryText).frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .background(Palette.background)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { app.link.browse(true); pulse = true }
            .onDisappear { app.link.browse(false) }
        }
    }

    private var radar: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Circle().stroke(Palette.violet.opacity(0.55 - Double(i) * 0.12), lineWidth: 1.2)
                    .frame(width: CGFloat(70 + i * 62), height: CGFloat(70 + i * 62))
                    .scaleEffect(pulse && !reduceMotion ? 1.06 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever().delay(Double(i) * 0.2), value: pulse)
            }
            Image(systemName: "cpu").font(.system(size: 30, weight: .medium)).foregroundStyle(Palette.lilac)
                .frame(width: 60, height: 60)
                .background(Palette.raised, in: ChamferedShape.control(Chamfer.button))
                .overlay { ChamferedShape.control(Chamfer.button).strokeBorder(Palette.brightEdge, lineWidth: 1) }
        }
        .accessibilityHidden(true)
    }

    private func permission(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(Typography.subheadline).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Text(value).font(Typography.footnote).foregroundStyle(Palette.secondaryText).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}
