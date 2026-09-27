import SwiftUI
import Charts
import MapKit
import UniformTypeIdentifiers

struct RunDetailView: View {
    @Environment(AppModel.self) private var app
    @Bindable var run: Run
    private let channel = -1
    @State private var binMinutes = 30
    @State private var selected: Date?
    @State private var renaming = false
    @State private var assigningLocation = false
    @State private var editingTags = false
    @State private var sharing = false
    @State private var filling = false
    @State private var fillProgress = ""
    @State private var message: String?
    @State private var eventsOpen = false

    private var records: [MinuteRecord] { run.records }

    var body: some View {
        let recs = records
        let bins = Binning.bins(recs, channel: channel, minutes: binMinutes)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                    Color.clear.frame(height: 1).id(TabScrollTop.anchor(.runs)).accessibilityHidden(true)
                header
                stats(recs)
                controls
                RateChart(bins: bins, events: run.events, binMinutes: binMinutes, selected: $selected, channels: (0..<3).map { Binning.bins(recs, channel: $0, minutes: binMinutes) })
                environmentCharts(bins)
                if hasAltitude(recs) { AltitudeChart(bins: bins, selected: $selected) }
                TrackMap(records: recs, selected: selected, channel: channel)
                Button("Assign stationary location") { assigningLocation = true }.buttonStyle(.muonSecondary)
                HealthCard(records: recs)
                eventsCard
                sdCard
                notesCard
                exportCard(recs)
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
            .tabScrollTop(.runs)
        .background(Palette.background)
        .navigationTitle(run.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { sharing = true } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share run card")
            }
        }
        .sheet(isPresented: $assigningLocation) { StationaryLocationSheet(run: run) }
        .sheet(isPresented: $renaming) { RenameSheet(run: run) }
        .sheet(isPresented: $editingTags) { TagEditor(run: run) }
        .sheet(isPresented: $sharing) { ShareCardSheet(run: run) }
        .alert("Run", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} } message: { Text(message ?? "") }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if run.isLive { PhaseBadge(phase: app.phase) }
            Text(dateRange).capsLabel(Palette.secondaryText)
            HStack(spacing: 8) {
                Text(run.name).font(Typography.title).lineLimit(2)
                Button { renaming = true } label: { Image(systemName: "pencil") }
                    .buttonStyle(.muonIcon).accessibilityLabel("Rename run")
            }
            FlowLayout(spacing: 6) {
                ForEach(run.tags, id: \.self) { TagChip(tag: $0) }
                Button { editingTags = true } label: {
                    Label(run.tags.isEmpty ? "Add tags" : "Edit", systemImage: "tag").font(Typography.raleway(12, .semibold, relativeTo: .caption))
                        .foregroundStyle(Palette.lilac)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .overlay(ChamferedShape.chip.strokeBorder(Palette.secondaryText, style: StrokeStyle(lineWidth: 1, dash: [3])))
                }.buttonStyle(.plain)
            }
            if let label = run.detectorLabel, !label.isEmpty {
                Text("Detector label \(label)" + (run.sdFileName.map { " · \($0)" } ?? ""))
                    .font(Typography.mono(11, .regular, relativeTo: .caption2)).foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private var dateRange: String {
        let end = run.end ?? records.last?.date ?? Date()
        return "\(run.start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .abbreviated, time: .shortened))"
    }

    private func stats(_ recs: [MinuteRecord]) -> some View {
        let phys = recs.filter(\.physics)
        let p = recs.compactMap(\.pressure)
        let rate = phys.isEmpty ? nil : Double(phys.reduce(0) { $0 + $1.coincidences }) / phys.reduce(0.0) { $0 + Double($1.intervalMS) / 60000 }
        return HStack(spacing: 8) {
            StatTile(value: (Double(phys.count) * 60).hoursMinutes, label: "exposure")
            StatTile(value: rate.map { String(format: "%.2f", $0) } ?? "—", label: "mean /min")
            StatTile(value: p.isEmpty ? "—" : String(format: "%.2f", (p.max() ?? 0) - (p.min() ?? 0)), label: "ΔP hPa")
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            ChamferSegmented(options: [1, 10, 30, 60], selection: $binMinutes) { m, on in
                Text("\(m) min").font(Typography.mono(13, .medium, relativeTo: .footnote)).foregroundStyle(on ? Palette.ink : Palette.muted)
            }
            .accessibilityLabel("Bin size")
        }
    }

    private func hasAltitude(_ recs: [MinuteRecord]) -> Bool {
        let a = recs.compactMap(\.altitude)
        return (a.max() ?? 0) - (a.min() ?? 0) > 50 || TagCatalog.isFlight(run.tags)
    }

    private func environmentCharts(_ bins: [RateBin]) -> some View {
        HStack(spacing: 10) {
            MiniSeries(title: "PRESSURE, hPa", tint: Palette.pressure, points: bins.compactMap { b in b.pressure.map { (b.date, $0, b.segment) } }, selected: selected)
            MiniSeries(title: "TEMPERATURE, °C", tint: Palette.temperature, points: bins.compactMap { b in b.temperature.map { (b.date, $0, b.segment) } }, selected: selected)
        }
    }

    // MARK: events, SD, notes, export

    private var eventsCard: some View {
        let events = run.events.sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $eventsOpen) {
                if events.isEmpty { Text("Nothing unusual recorded.").font(Typography.footnote).foregroundStyle(Palette.secondaryText) }
                ForEach(events) { e in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: e.eventKind.symbol).frame(width: 20).foregroundStyle(Palette.lilac)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.eventKind.title).font(Typography.subheadline)
                            Text(e.detail).font(Typography.caption).foregroundStyle(Palette.secondaryText)
                            Text(e.date.formatted(date: .abbreviated, time: .shortened)).font(Typography.mono(11, .regular, relativeTo: .caption2)).foregroundStyle(Palette.secondaryText)
                        }
                    }.padding(.top, 6)
                }
            } label: {
                Text("Events · \(events.count)").font(Typography.headline)
            }.tint(Palette.ink)
        }.card()
    }

    @ViewBuilder private var sdCard: some View {
        let gaps = run.events.filter { $0.eventKind == .gap }.count
        if run.source == "phone" {
            VStack(alignment: .leading, spacing: 8) {
                Text("SD card").font(Typography.headline)
                Text(gaps > 0 ? "The phone missed minutes \(gaps == 1 ? "once" : "\(gaps) times"). The detector's SD card has every minute." :
                        "The detector's SD card is the complete record. Merge it to be sure no minute is missing.")
                    .font(Typography.footnote).foregroundStyle(Palette.secondaryText)
                if run.isLive {
                    Button {
                        filling = true
                        Task {
                            do { let n = try await app.fillFromDetector(run) { a, b in fillProgress = "\(a / 1024) of \(b / 1024) KB" }; message = "\(n) missing minutes added from the SD card." }
                            catch { message = error.localizedDescription }
                            filling = false
                        }
                    } label: { Label(filling ? "Downloading \(fillProgress)" : "Fill gaps from the SD card", systemImage: "sdcard").frame(maxWidth: .infinity) }
                        .buttonStyle(.muonSecondary).disabled(filling || !app.link.controlsReady)
                } else {
                    Text("For a finished run, import its muon_….csv on the Runs tab; missing minutes are merged into this run.")
                        .font(Typography.caption).foregroundStyle(Palette.secondaryText)
                }
            }.card()
        }
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes").font(Typography.headline)
            TextField("Where was the detector, what changed…", text: $run.notes, axis: .vertical).lineLimit(2...6)
        }.card()
    }

    private func exportCard(_ recs: [MinuteRecord]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if app.cloud.isConfigured {
                Button { if !app.cloud.save(run) { message = app.cloud.problem } } label: {
                    Label("Save to \(app.cloud.folderName ?? "cosmic") now", systemImage: "icloud.and.arrow.up").frame(maxWidth: .infinity)
                }.buttonStyle(.muonPrimary)
                Text(run.exportedAt.map { "Saved \($0.formatted(date: .omitted, time: .shortened)) in \(app.cloud.folderName ?? "cosmic") › phone › \(run.exportFolder ?? "")" } ?? "Not saved yet. Live runs save every 5 minutes.")
                    .font(Typography.caption).foregroundStyle(Palette.secondaryText)
            } else {
                Text("Choose your cosmic folder in Settings to save runs to iCloud Drive automatically.").font(Typography.footnote).foregroundStyle(Palette.secondaryText)
            }
            ShareLink(item: CSVFile(name: CSVExport.folderName(start: run.start, name: run.name) + ".csv", records: recs), preview: SharePreview(run.name)) {
                Label("Share CSV", systemImage: "tablecells").frame(maxWidth: .infinity)
            }.buttonStyle(.muonSecondary)
        }.card()
    }
}

/// CSV handed to the share sheet, written to a temporary file with a readable name.
struct CSVFile: Transferable {
    let name: String
    let records: [MinuteRecord]
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { item in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(item.name)
            try Data(CSVExport.csv(item.records).utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

// MARK: charts

struct RateChart: View {
    let bins: [RateBin]
    let events: [RunEvent]
    var binMinutes: Int = 30
    @Binding var selected: Date?
    var channels: [[RateBin]] = []

    private var selectedBin: RateBin? {
        guard let selected else { return nil }
        return bins.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }

    /// Fit the plotted data (error bars included) with a little headroom, instead of
    /// rounding up to the next "nice" axis value and leaving the top of the chart empty.
    private var yDomain: ClosedRange<Double> {
        let values = bins.flatMap { [$0.rate - $0.error, $0.rate + $0.error] } + channels.flatMap { $0.map(\.rate) }
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.08, 1)
        return max(0, lo - pad)...(hi + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rate, \(binMinutes)-min bins").font(Typography.headline).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text("counts / min").font(Typography.monoCaption).foregroundStyle(Palette.secondaryText).lineLimit(1)
            }
            FlowLayout(spacing: 12) {
                ForEach([-1] + Array(channels.indices), id: \.self) { ch in
                    ChannelLabel(channel: ch, size: 13, legendColor: ch < 0 ? Palette.data : Palette.pairs[ch])
                }
            }
            if bins.isEmpty {
                ContentUnavailableView("No physics minutes yet", systemImage: "chart.xyaxis.line", description: Text("Setup and HV settling are not charted."))
                    .frame(height: 200)
            } else {
                // Review fix 5: the readout lives in a strip above the plot, on the side
                // away from the selected point, so it never covers the peak it describes.
                tooltipStrip.frame(height: 50)
                Chart {
                    ForEach(bins) { b in
                        RuleMark(x: .value("Time", b.date), yStart: .value("Low", b.rate - b.error), yEnd: .value("High", b.rate + b.error))
                            .foregroundStyle(Palette.data.opacity(0.25)).lineStyle(StrokeStyle(lineWidth: bins.count > 80 ? 1 : 3, lineCap: .butt))
                        LineMark(x: .value("Time", b.date), y: .value("Rate", b.rate), series: .value("Segment", "line\(b.segment)"))
                            .foregroundStyle(Palette.data).lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                    }
                    ForEach(Array(channels.enumerated()), id: \.offset) { entry in
                        ForEach(entry.element) { b in
                            LineMark(x: .value("Time", b.date), y: .value("Rate", b.rate), series: .value("Segment", "channel\(entry.offset)-\(b.segment)"))
                                .foregroundStyle(Palette.pairs[entry.offset]).lineStyle(StrokeStyle(lineWidth: 1.5))
                            PointMark(x: .value("Time", b.date), y: .value("Rate", b.rate))
                                .foregroundStyle(Palette.pairs[entry.offset]).symbolSize(10)
                        }
                    }
                    ForEach(events.filter { $0.eventKind != .label && $0.eventKind != .note }) { e in
                        RuleMark(x: .value("Event", e.date))
                            .foregroundStyle(Palette.secondaryText.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, alignment: .center) {
                                Image(systemName: e.eventKind.symbol).font(.system(size: 9)).foregroundStyle(Palette.secondaryText)
                            }
                    }
                    if let b = selectedBin {
                        RuleMark(x: .value("Selected", b.date)).foregroundStyle(Palette.ink.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        PointMark(x: .value("Time", b.date), y: .value("Rate", b.rate)).foregroundStyle(Palette.data).symbolSize(60)
                    }
                }
                .chartYScale(domain: yDomain)
                .chartXAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Palette.grid); AxisValueLabel().font(Typography.mono(10, .regular, relativeTo: .caption2)).foregroundStyle(Palette.secondaryText) } }
                .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Palette.grid); AxisValueLabel().font(Typography.mono(10, .regular, relativeTo: .caption2)).foregroundStyle(Palette.secondaryText) } }
                .chartXSelection(value: $selected)
                .frame(height: 200)
            }
        }.card()
    }

    @ViewBuilder private var tooltipStrip: some View {
        if let b = selectedBin, let first = bins.first?.date, let last = bins.last?.date {
            let rightHalf = last > first && b.date.timeIntervalSince(first) / last.timeIntervalSince(first) > 0.5
            HStack {
                if rightHalf { tooltip(b); Spacer(minLength: 0) } else { Spacer(minLength: 0); tooltip(b) }
            }
        } else {
            Text("Drag across the chart to read a bin").font(Typography.caption).foregroundStyle(Palette.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func tooltip(_ b: RateBin) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(b.date.formatted(date: .omitted, time: .shortened)) · \(b.minutes) min")
            Text(String(format: "%.2f ± %.2f /min", b.rate, b.error)).foregroundStyle(Palette.data)
            if let p = b.pressure { Text(String(format: "%.1f hPa", p) + (b.temperature.map { String(format: " · %.1f °C", $0) } ?? "")) }
        }
        .font(Typography.mono(11, .regular, relativeTo: .caption2)).foregroundStyle(Palette.ink)
        .lineLimit(1)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .chamferGlass(.control(Chamfer.chip + 2))
    }
}

struct MiniSeries: View {
    let title: String
    let tint: Color
    let points: [(Date, Double, Int)]
    let selected: Date?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).capsLabel(tint)
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { item in
                    LineMark(x: .value("Time", item.element.0), y: .value("Value", item.element.1), series: .value("S", item.element.2)).foregroundStyle(tint)
                }
                if let selected { RuleMark(x: .value("Selected", selected)).foregroundStyle(Palette.ink.opacity(0.3)) }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Palette.grid); AxisValueLabel().font(Typography.mono(9, .regular, relativeTo: .caption2)).foregroundStyle(Palette.secondaryText) } }
            .frame(height: 80)
            if let lo = points.map(\.1).min(), let hi = points.map(\.1).max() {
                // Review fix 6: one line, shrinks instead of wrapping.
                Text(String(format: "%.1f – %.1f", lo, hi)).font(Typography.mono(11, .regular, relativeTo: .caption2)).foregroundStyle(Palette.secondaryText)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }.card(padding: 12)
    }
}

struct AltitudeChart: View {
    let bins: [RateBin]
    @Binding var selected: Date?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GPS ALTITUDE, m").capsLabel(Palette.setup)
            Chart {
                ForEach(bins.filter { $0.altitude != nil }) { b in
                    LineMark(x: .value("Time", b.date), y: .value("Altitude", b.altitude!), series: .value("S", b.segment)).foregroundStyle(Palette.setup)
                }
                if let selected { RuleMark(x: .value("Selected", selected)).foregroundStyle(Palette.ink.opacity(0.3)) }
            }
            .chartXSelection(value: $selected)
            .frame(height: 110)
            Text("Muon rates rise with altitude. Pressure measured inside a vehicle or cabin is not outside air pressure.")
                .font(Typography.caption).foregroundStyle(Palette.secondaryText)
        }.card()
    }
}

struct HealthCard: View {
    let records: [MinuteRecord]
    var body: some View {
        let report = Health.report(records)
        let pairs = Array(report.prefix(3))
        VStack(alignment: .leading, spacing: 10) {
            Text("Counting statistics · entire run").font(Typography.headline)
            Text("Scatter ÷ what pure chance allows. 1.00 is ideal; higher values point to interference, a noisy threshold or a changing setup.")
                .font(Typography.caption).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(pairs) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        ChannelLabel(channel: r.channel, size: 15)
                        Text(r.fano.isFinite ? String(format: "%.2f", r.fano) : "—").font(Typography.monoValue)
                            .foregroundStyle(r.level == .good ? Palette.ink : r.level == .unknown ? Palette.secondaryText : Palette.alert)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .panel(padding: 10, cut: 8, fill: Palette.raised)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(r.level.rawValue)
                }
            }
            if !pairs.isEmpty {
                let clean = pairs.allSatisfy { $0.level == .good }
                let unknown = pairs.contains { $0.level == .unknown }
                HStack(spacing: 6) {
                    Image(systemName: clean ? "checkmark" : unknown ? "questionmark" : "exclamationmark.triangle")
                    Text(clean ? "Counting looks clean" : unknown ? "Not enough physics minutes yet" : "More variation than chance allows")
                }
                .font(Typography.raleway(12, .bold, relativeTo: .caption))
                .foregroundStyle(clean ? Palette.physics : unknown ? Palette.muted : Palette.alert)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background((clean ? Palette.physics : unknown ? Palette.muted : Palette.alert).opacity(0.12), in: ChamferedShape.chip)
            }
        }.card()
    }
}

// MARK: map

/// One GPS fix per minute, joined into a track and coloured by that minute's rate.
/// A stationary run shows its fixes as a small cluster with the typical accuracy circle.
struct TrackMap: View {
    let records: [MinuteRecord]
    let selected: Date?
    let channel: Int

    private struct Fix { let coord: CLLocationCoordinate2D; let rate: Double; let date: Date; let accuracy: Double }

    var body: some View {
        let fixes = records.compactMap { r -> Fix? in
            guard let lat = r.latitude, let lon = r.longitude, r.physics, let rate = r.rate(channel) else { return nil }
            return Fix(coord: .init(latitude: lat, longitude: lon), rate: rate, date: r.date, accuracy: r.horizontalAccuracy ?? 10)
        }
        VStack(alignment: .leading, spacing: 8) {
            if fixes.isEmpty {
                Label("No GPS for this run", systemImage: "location.slash").font(Typography.raleway(15, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryText)
            } else {
                let spread = maxDistance(fixes.map(\.coord))
                let lo = fixes.map(\.rate).sorted()[fixes.count / 10], hi = fixes.map(\.rate).sorted()[fixes.count * 9 / 10]
                let marker = selected.flatMap { s in fixes.min { abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s)) } } ?? fixes.last!
                Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
                    if spread < 60 {
                        MapCircle(center: centroid(fixes.map(\.coord)), radius: median(fixes.map(\.accuracy)))
                            .foregroundStyle(Palette.data.opacity(0.12)).stroke(Palette.data.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3]))
                    }
                    ForEach(Array(stride(from: 1, to: fixes.count, by: 1)), id: \.self) { i in
                        MapPolyline(coordinates: [fixes[i - 1].coord, fixes[i].coord])
                            .stroke(color(for: (fixes[i].rate + fixes[i - 1].rate) / 2, lo, hi), lineWidth: spread < 60 ? 2 : 5)
                    }
                    Annotation("", coordinate: marker.coord) {
                        Circle().fill(Palette.ink).frame(width: 14, height: 14).overlay(Circle().stroke(Palette.ground.opacity(0.6), lineWidth: 2))
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: 220)
                .chamferClip(.panel(10))
                HStack {
                    Text(spread < 60 ? "Stationary · \(fixes.count) fixes" : String(format: "Moved %.1f km · %d fixes", pathLength(fixes.map(\.coord)) / 1000, fixes.count))
                        .font(Typography.subheadline)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("rate").font(Typography.mono(10, .regular, relativeTo: .caption2)).foregroundStyle(Palette.secondaryText)
                        HStack(spacing: 0) { ForEach(0..<5, id: \.self) { Palette.ramp[$0].frame(width: 12, height: 6) } }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Colour shows rate, dim green is low, bright green is high")
                }
                Text("Recorded or manually assigned positions, coloured by minute rate. The white dot follows the time selected in the chart. Location stays on your phone and in your cosmic folder.")
                    .font(Typography.caption).foregroundStyle(Palette.secondaryText)
            }
        }.card()
    }

    private func color(for rate: Double, _ lo: Double, _ hi: Double) -> Color {
        let f = hi > lo ? (rate - lo) / (hi - lo) : 0.5
        return Palette.ramp[min(4, max(0, Int(f * 5)))]
    }
    private func centroid(_ c: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        .init(latitude: c.map(\.latitude).reduce(0, +) / Double(c.count), longitude: c.map(\.longitude).reduce(0, +) / Double(c.count))
    }
    private func maxDistance(_ c: [CLLocationCoordinate2D]) -> Double {
        let m = centroid(c), center = CLLocation(latitude: m.latitude, longitude: m.longitude)
        return c.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: center) }.max() ?? 0
    }
    private func pathLength(_ c: [CLLocationCoordinate2D]) -> Double {
        zip(c, c.dropFirst()).reduce(0) { $0 + CLLocation(latitude: $1.0.latitude, longitude: $1.0.longitude).distance(from: CLLocation(latitude: $1.1.latitude, longitude: $1.1.longitude)) }
    }
    private func median(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
}

/// Wrapping row of chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing; rowH = max(rowH, size.height); maxX = max(maxX, x)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
    }
}
