import WidgetKit
import SwiftUI
import AppIntents

@main
struct MuonWidgets: WidgetBundle {
    var body: some Widget {
        MuonLiveActivity()
        RateWidget()
        LoggingControl()
        PhysicsRunControl()
    }
}

// MARK: Home Screen and Lock Screen widget

struct RateEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var overdue: Bool {
        guard let s = snapshot, s.logging, let d = s.sampleDate else { return false }
        return date.timeIntervalSince(d) > 240
    }
}

struct RateProvider: TimelineProvider {
    func placeholder(in context: Context) -> RateEntry { RateEntry(date: Date(), snapshot: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (RateEntry) -> Void) {
        completion(RateEntry(date: Date(), snapshot: context.isPreview ? .preview : SharedStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RateEntry>) -> Void) {
        let s = SharedStore.load()
        var entries = [RateEntry(date: Date(), snapshot: s)]
        // A second entry flips the widget to "overdue" if the app stops publishing.
        if let d = s?.sampleDate, s?.logging == true { entries.append(RateEntry(date: max(Date(), d.addingTimeInterval(241)), snapshot: s)) }
        completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct RateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "org.muonreadout.rate", provider: RateProvider()) { entry in
            RateWidgetView(entry: entry).containerBackground(for: .widget) { Palette.ground }
                .environment(\.colorScheme, .dark)
                .widgetURL(URL(string: "muonp4://now"))
        }
        .configurationDisplayName("Muon rate")
        .description("The last completed minute from your detector.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct RateWidgetView: View {
    let entry: RateEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.snapshot, SharedStore.isAvailable || family == .systemSmall || s.logging {
            content(s)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                MuonMark(size: 16, color: Palette.lilac)
                Text(SharedStore.isAvailable ? "Start logging in MuonP4" : "Open MuonP4 to set up widgets")
                    .font(Typography.raleway(13, .semibold)).foregroundStyle(Palette.ink)
            }
        }
    }

    private var value: String { entry.overdue ? "—" : entry.snapshot?.total.map(String.init) ?? "—" }

    @ViewBuilder private func content(_ s: WidgetSnapshot) -> some View {
        switch family {
        case .accessoryCircular:
            // Accessory families are tinted by the system; keep them simple.
            Gauge(value: Double(s.total ?? 0), in: 0...Double(max(1, Int((s.meanRate ?? 60) * 1.5)))) {
                Text("/min")
            } currentValueLabel: { Text(value).font(Typography.monoFixed(14, .medium)) }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    MuonMark(size: 12, color: .primary)
                    Text(s.runName.isEmpty ? "MuonP4" : s.runName).font(Typography.raleway(14, .bold)).lineLimit(1)
                }
                Text("\(value) muons/min").font(Typography.monoFixed(13, .medium))
                if let p = s.pressure { Text(String(format: "%.1f hPa", p)).font(Typography.monoFixed(11)) }
            }
        case .accessoryInline:
            Text("\(value) muons/min")
        case .systemMedium:
            VStack(alignment: .leading, spacing: 8) {
                header(s)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(value).font(Typography.monoFixed(38, .medium)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
                        Text(s.meanRate.map { String(format: "per min · mean %.1f", $0) } ?? "per min")
                            .font(Typography.monoFixed(11)).foregroundStyle(Palette.data).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 3) {
                        if let p = s.pressure {
                            Text("\(Text(String(format: "%.1f", p)).foregroundStyle(Palette.ink))\(Text(" hPa").foregroundStyle(Palette.pressure))\(Text(s.pressureChange3h.map { $0 < -0.3 ? " ↓" : $0 > 0.3 ? " ↑" : "" } ?? "").foregroundStyle(Palette.muted))")
                        }
                        if let t = s.temperature { Text("\(Text(String(format: "%.1f", t)).foregroundStyle(Palette.ink))\(Text(" °C").foregroundStyle(Palette.temperature))") }
                    }
                    .font(Typography.monoFixed(12)).lineLimit(1)
                }
                // Review fix 4: minute bars are green everywhere.
                MinuteBars(values: s.recent, tint: Palette.data).frame(height: 30)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                header(s)
                Spacer(minLength: 0)
                Text(value).font(Typography.monoFixed(40, .medium)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
                Text(entry.overdue ? "update overdue" : "muons / min").font(Typography.monoFixed(11))
                    .foregroundStyle(entry.overdue ? Palette.alert : Palette.data).lineLimit(1)
                MinuteBars(values: Array(s.recent.suffix(30)), tint: Palette.data).frame(height: 24)
            }
        }
    }

    private func header(_ s: WidgetSnapshot) -> some View {
        HStack(spacing: 5) {
            MuonMark(size: 13, color: Palette.lilac)
            Text(family == .systemMedium && !s.runName.isEmpty ? s.runName : "MuonP4")
                .font(Typography.raleway(12, .bold)).foregroundStyle(Palette.ink).lineLimit(1)
            Spacer(minLength: 4)
            Rectangle().fill(entry.overdue ? Palette.alert : s.logging ? s.phase.tint : Palette.secondaryText)
                .frame(width: 6, height: 6).rotationEffect(.degrees(45))
        }
    }
}

// MARK: Control Center

struct LoggingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "org.muonreadout.logging", provider: Provider()) { on in
            ControlWidgetToggle("Muon logging", isOn: on, action: SetLoggingIntent()) { isOn in
                Label(isOn ? "Logging" : "Off", systemImage: isOn ? "record.circle.fill" : "record.circle")
            }
            .tint(Palette.violet)
        }
        .displayName("Muon logging")
        .description("Start or stop logging from your MuonP4 detector.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { SharedStore.load()?.logging ?? false }
    }
}

struct PhysicsRunControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "org.muonreadout.physics") {
            ControlWidgetButton(action: StartPhysicsRunIntent()) {
                Label("Physics run", systemImage: "play.fill")
            }
        }
        .displayName("Start physics run")
        .description("Opens MuonP4 and starts a clean physics run on the detector.")
    }
}
