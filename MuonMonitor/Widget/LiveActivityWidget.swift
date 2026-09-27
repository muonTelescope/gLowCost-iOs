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
                    }.padding(.leading, 10).padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PhasePill(phase: stale ? .overdue : s.phase).padding(.trailing, 10).padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .bottom, spacing: 12) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(stale ? "—" : s.total.map(String.init) ?? "—")
                                    .font(Typography.monoFixed(36, .medium)).foregroundStyle(Palette.ink)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Text("/min").font(Typography.monoFixed(11)).foregroundStyle(Palette.data)
                            }
                            ActivityPlot(state: s).frame(maxWidth: .infinity).frame(height: 42)
                        }
                        ActivityLegend(pairs: s.pairs)
                        HStack(spacing: 8) {
                            EnvLine(state: s).layoutPriority(1)
                            Spacer(minLength: 0)
                            Button(intent: StopLoggingIntent()) {
                                Text("Stop").font(Typography.raleway(11, .bold)).foregroundStyle(Palette.ink)
                            }
                            .tint(Palette.violet.opacity(0.35))
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 12)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                MuonMark(size: 14, color: Palette.lilac)
                Text("MuonP4").font(Typography.raleway(14, .bold)).foregroundStyle(Palette.ink)
                PhasePill(phase: stale ? .overdue : state.phase)
                Spacer(minLength: 2)
                if let d = state.sampleDate {
                    Text("\(Text(d, style: .relative)) ago").font(Typography.monoFixed(10))
                        .foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(stale ? "—" : state.total.map(String.init) ?? "—")
                        .font(Typography.monoFixed(36, .medium)).foregroundStyle(Palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("coincidences / min").font(Typography.monoFixed(10)).foregroundStyle(Palette.data)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                ActivityPlot(state: state).frame(maxWidth: .infinity).frame(height: 44)
            }
            ActivityLegend(pairs: state.pairs)
            EnvLine(state: state).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

/// The same pair colours and plot appear on the Lock Screen and expanded Island.
struct ActivityPlot: View {
    let state: MuonActivity.ContentState
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let series = state.recentPairs, series.count == 3, (series.first?.count ?? 0) > 1 {
                PairLines(series: series).padding(.horizontal, 2).padding(.vertical, 2)
            } else {
                MinuteBars(values: state.recent, tint: Palette.data)
            }
            Text("last 30 min").font(Typography.monoFixed(9)).foregroundStyle(Palette.muted)
        }
    }
}

struct ActivityLegend: View {
    let pairs: [Int]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 3) {
                    ChannelLabel(channel: i, size: 12, color: Palette.muted, fixed: true, legendColor: Palette.pairs[i])
                    Text(pairs.count > i ? "\(pairs[i])" : "—")
                        .font(Typography.monoFixed(12, .medium)).foregroundStyle(Palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
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

struct EnvLine: View {
    let state: MuonActivity.ContentState
    var body: some View {
        HStack(spacing: 4) {
            if let p = state.pressure { Text(String(format: "%.1f hPa", p)).foregroundStyle(Palette.pressure).fixedSize() }
            if state.pressure != nil, state.temperature != nil { Text("·").foregroundStyle(Palette.muted) }
            if let t = state.temperature { Text(String(format: "%.1f °C", t)).foregroundStyle(Palette.temperature).fixedSize() }
        }
        .font(Typography.monoFixed(11))
        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }
}
