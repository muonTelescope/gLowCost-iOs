import SwiftUI
import Charts

/// Overlay two runs, each divided by its own mean, against hours since start.
/// Different thresholds give different absolute rates, so shapes are compared, not levels.
struct CompareView: View {
    @Environment(\.dismiss) private var dismiss
    let runs: [Run]
    @State private var a: Run?
    @State private var b: Run?

    private struct Point: Identifiable { let id = UUID(); let hours: Double; let value: Double; let run: String; let segment: Int }

    private func points(_ run: Run, _ label: String) -> [Point] {
        let bins = Binning.bins(run.records, channel: -1, minutes: 30)
        let mean = bins.map(\.rate).reduce(0, +) / Double(max(bins.count, 1))
        return bins.map { Point(hours: $0.date.timeIntervalSince(run.start) / 3600, value: $0.rate / mean, run: label, segment: $0.segment) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("First", selection: $a) { Text("Choose").tag(Run?.none); ForEach(runs) { Text($0.name).tag(Run?.some($0)) } }
                    Picker("Second", selection: $b) { Text("Choose").tag(Run?.none); ForEach(runs) { Text($0.name).tag(Run?.some($0)) } }
                }
                if let a, let b {
                    let pa = points(a, a.name), pb = points(b, b.name == a.name ? b.name + " (2)" : b.name)
                    Section("Rate ÷ run mean, 30-min bins") {
                        Chart(pa + pb) { p in
                            LineMark(x: .value("Hours", p.hours), y: .value("Relative rate", p.value), series: .value("Run", "\(p.run)-\(p.segment)"))
                                .foregroundStyle(by: .value("Run", p.run))
                        }
                        .chartForegroundStyleScale(domain: [pa.first?.run ?? "", pb.first?.run ?? ""], range: [Palette.data, Palette.lilac])
                        .chartXAxisLabel("hours since start").chartLegend(position: .top, alignment: .leading).frame(height: 240)
                    }
                    Section("Side by side") {
                        row("Mean rate", a.meanRate.map { String(format: "%.2f", $0) } ?? "—", b.meanRate.map { String(format: "%.2f", $0) } ?? "—")
                        row("Physics time", (Double(a.physicsMinutes) * 60).hoursMinutes, (Double(b.physicsMinutes) * 60).hoursMinutes)
                        let ha = Health.report(a.records), hb = Health.report(b.records)
                        ForEach(0..<3, id: \.self) { ch in
                            row("\(ChannelLabel.plain(ch)) spread", String(format: "%.2f", ha[ch].fano), String(format: "%.2f", hb[ch].fano))
                        }
                        row("Tags", a.tags.joined(separator: ", "), b.tags.joined(separator: ", "))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .listRowBackground(Palette.panel)
            .navigationTitle("Compare runs").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { a = runs.first; b = runs.dropFirst().first }
        }
    }

    private func row(_ title: String, _ x: String, _ y: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(Palette.secondaryText).frame(width: 110, alignment: .leading)
            Text(x).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Palette.data)
            Text(y).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Palette.lilac)
        }.font(Typography.mono(13, .regular, relativeTo: .footnote))
    }
}
