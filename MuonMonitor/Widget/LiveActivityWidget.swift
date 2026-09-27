import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

// Lock Screen Live Activity and Dynamic Island, in the violet & phosphor palette.
// Widgets always render dark (the ground colour), matching the dark-only app.
// Sizes here use fixed fonts: Live Activities do not grow with Dynamic Type
// beyond what the system allows, and fixed sizes keep channel digits ≥ 11 pt.

struct MuonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MuonActivity.self) { context in
            LockScreenActivity(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Palette.ground.opacity(0.85))
                .activitySystemActionForegroundColor(Palette.ink)
                .environment(\.colorScheme, .dark)
        } dynamicIsland: { context in
            let s = context.state, stale = context.isStale || s.phase == .overdue
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        MuonMark(size: 16, color: Palette.lilac)
                        Text("MuonP4").font(Typography.raleway(15, .bold)).foregroundStyle(Palette.ink)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PhasePill(phase: stale ? .overdue : s.phase)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .lastTextBaseline) {
                            Text(s.total.map(String.init) ?? "—").font(Typography.monoFixed(46, .medium)).foregroundStyle(Palette.ink)
                                .lineLimit(1).minimumScaleFactor(0.6)
                            Text("/ min").font(Typography.monoFixed(13)).foregroundStyle(Palette.data)
                            Spacer()
                            PairColumn(pairs: s.pairs)
                        }
                        HStack {
                            EnvLine(state: s)
                            Spacer()
                            Button(intent: StopLoggingIntent()) {
                                Text("Stop logging").font(Typography.raleway(12, .bold)).foregroundStyle(Palette.ink)
                            }
                            .tint(Palette.violet.opacity(0.35))
                        }
                    }
                }
            } compactLeading: {
                if stale {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash").foregroundStyle(Palette.alert)
                } else if s.phase == .physics {
                    MuonMark(size: 14, color: Palette.lilac)
                } else {
                    Image(systemName: "clock").foregroundStyle(Palette.setup)
                }
            } compactTrailing: {
                if stale {
                    Text(s.sampleDate ?? Date(), style: .relative).font(Typography.monoFixed(13)).foregroundStyle(Palette.alert).frame(maxWidth: 50)
                } else if s.phase != .physics, let ends = s.setupEnds, ends > Date() {
                    Text(timerInterval: Date()...ends, countsDown: true).font(Typography.monoFixed(13)).foregroundStyle(Palette.setup).frame(maxWidth: 44)
                } else {
                    Text(s.total.map(String.init) ?? "—").font(Typography.monoFixed(14, .medium)).foregroundStyle(Palette.data)
                }
            } minimal: {
                Text(stale ? "—" : s.total.map(String.init) ?? "—").font(Typography.monoFixed(13, .medium))
                    .foregroundStyle(stale ? Palette.alert : Palette.data)
            }
            .keylineTint(Palette.violet)
            .widgetURL(URL(string: "muonp4://now"))
        }
    }
}

struct LockScreenActivity: View {
    let state: MuonActivity.ContentState
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                MuonMark(size: 15, color: Palette.lilac)
                Text("MuonP4").font(Typography.raleway(15, .bold)).foregroundStyle(Palette.ink)
                PhasePill(phase: stale ? .overdue : state.phase)
                Spacer(minLength: 4)
                if let d = state.sampleDate {
                    (Text(d, style: .relative) + Text(" ago")).font(Typography.monoFixed(11)).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(stale ? "—" : state.total.map(String.init) ?? "—").font(Typography.monoFixed(40, .medium)).foregroundStyle(Palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("coincidences / min").font(Typography.monoFixed(11)).foregroundStyle(Palette.data).lineLimit(1).fixedSize()
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 3) {
                    chart.frame(width: 170, height: 40)
                    Text(usesLines ? "last 30 min · per pair" : "last 30 min · 1 bar per minute")
                        .font(Typography.monoFixed(10)).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 4) {
                        if usesLines { Rectangle().fill(Palette.pairs[i]).frame(width: 8, height: 2) }
                        ChannelLabel(channel: i, size: 14, color: Palette.muted, fixed: true)
                        Text(state.pairs.count > i ? "\(state.pairs[i])" : "—").font(Typography.monoFixed(13, .medium)).foregroundStyle(Palette.ink)
                    }
                }
                Spacer(minLength: 4)
                EnvLine(state: state)
            }
        }
        .padding(16)
    }

    /// Decided default: three coincidence-pair lines. Older app builds that do not send
    /// `recentPairs` fall back to the green minute bars (review fix 4).
    private var usesLines: Bool { (state.recentPairs?.count ?? 0) == 3 && (state.recentPairs?.first?.count ?? 0) > 1 }

    @ViewBuilder private var chart: some View {
        if usesLines, let series = state.recentPairs {
            PairLines(series: series)
        } else {
            MinuteBars(values: state.recent, tint: Palette.data)
        }
    }
}

/// Phase chip with cut corners; overdue is the only pink state (an alert).
struct PhasePill: View {
    let phase: Phase
    var body: some View {
        Text(phase == .physics ? "Physics" : phase.title)
            .font(Typography.raleway(11, .bold)).foregroundStyle(phase.tint)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(phase.tint.opacity(0.16), in: ChamferedShape.chip)
            .overlay { ChamferedShape.chip.strokeBorder(phase.tint.opacity(0.45), lineWidth: 1) }
    }
}

struct PairColumn: View {
    let pairs: [Int]
    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 1) {
            ForEach(0..<3, id: \.self) { i in
                GridRow {
                    ChannelLabel(channel: i, size: 14, color: Palette.muted, fixed: true)
                    Text(pairs.count > i ? "\(pairs[i])" : "—").font(Typography.monoFixed(12, .medium)).foregroundStyle(Palette.ink)
                }
            }
        }
    }
}

struct EnvLine: View {
    let state: MuonActivity.ContentState
    var body: some View {
        HStack(spacing: 4) {
            if let p = state.pressure { Text(String(format: "%.1f hPa", p)).foregroundStyle(Palette.pressure) }
            if state.pressure != nil, state.temperature != nil { Text("·").foregroundStyle(Palette.muted) }
            if let t = state.temperature { Text(String(format: "%.1f °C", t)).foregroundStyle(Palette.temperature) }
        }
        .font(Typography.monoFixed(12))
        .lineLimit(1)
    }
}
