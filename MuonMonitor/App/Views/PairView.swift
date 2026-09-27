import SwiftUI

/// First run: find a nearby MuonP4 and pair with it.
struct PairView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    radar.frame(height: 240).frame(maxWidth: .infinity)
                    Text("Find your detector").font(.largeTitle.bold())
                    Text("Power on the telescope. It announces itself over Bluetooth every 15 seconds, so it can take a moment to appear.")
                        .font(.body).foregroundStyle(.secondary)
                    if app.link.nearby.isEmpty {
                        HStack(spacing: 10) { ProgressView(); Text("Looking for MuonP4…").foregroundStyle(.secondary) }.card()
                    }
                    ForEach(app.link.nearby) { d in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "cpu").font(.title2).foregroundStyle(Palette.accentSoft)
                                    .frame(width: 46, height: 46).background(Palette.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).font(.headline)
                                    Text(d.lastMinute.map { "Nearby · last minute \($0) coincidences" } ?? "Nearby").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "cellularbars", variableValue: min(1, max(0, Double(d.rssi + 100) / 50)))
                                    .accessibilityLabel("Signal \(d.rssi) dBm")
                            }
                            Button {
                                app.link.remember(d.id)
                                app.start(); dismiss()
                            } label: { Text("Connect and start logging").frame(maxWidth: .infinity).padding(.vertical, 6) }
                                .buttonStyle(.glassProminent)
                            Text("iOS may ask to pair when it connects. Pairing encrypts detector commands. It does not stop another phone from pairing too.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .card(padding: 16)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        permission("Bluetooth", app.link.state == .unauthorized ? "Not allowed" : "Allowed")
                        permission("Location, to tag where each minute was recorded", app.location.permissionText)
                    }
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
            ForEach(0..<4) { i in
                Circle().stroke(Palette.accent.opacity(0.5 - Double(i) * 0.12), lineWidth: 1.2)
                    .frame(width: CGFloat(80 + i * 70), height: CGFloat(80 + i * 70))
                    .scaleEffect(pulse && !reduceMotion ? 1.06 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever().delay(Double(i) * 0.2), value: pulse)
            }
            Image(systemName: "cpu").font(.largeTitle).foregroundStyle(Palette.accentSoft)
        }
        .accessibilityHidden(true)
    }

    private func permission(_ title: String, _ value: String) -> some View {
        HStack { Text(title).font(.subheadline); Spacer(); Text(value).font(.subheadline).foregroundStyle(.secondary) }
    }
}
