import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

struct MuonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MuonActivity.self) { context in
            LockScreenActivity(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color(UIColor(hex: 0x141A26)).opacity(0.72))
                .activitySystemActionForegroundColor(.white)
                .environment(\.colorScheme, .dark)
        } dynamicIsland: { context in
            let s = context.state, stale = context.isStale || s.phase == .overdue
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "line.diagonal").foregroundStyle(Palette.accentSoft)
                        Text("MuonP4").font(.subheadline.weight(.semibold))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PhasePill(phase: stale ? .overdue : s.phase)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .lastTextBaseline) {
                            Text(s.total.map(String.init) ?? "—").font(.system(size: 50, weight: .medium, design: .rounded)).monospacedDigit()
                            Text("/ min").font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            PairColumn(pairs: s.pairs)
                        }
                        HStack {
                            EnvLine(state: s).font(.caption)
                            Spacer()
                            Button(intent: StopLoggingIntent()) { Text("Stop logging").font(.caption.weight(.semibold)) }
                                .tint(.white.opacity(0.2))
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: stale ? "antenna.radiowaves.left.and.right.slash" : s.phase == .physics ? "line.diagonal" : "clock")
                    .foregroundStyle(stale ? Palette.danger : s.phase == .physics ? Palette.accentSoft : Palette.setup)
            } compactTrailing: {
                if stale {
                    Text(s.sampleDate ?? Date(), style: .relative).monospacedDigit().foregroundStyle(Palette.danger).frame(maxWidth: 50)
                } else if s.phase != .physics, let ends = s.setupEnds, ends > Date() {
                    Text(timerInterval: Date()...ends, countsDown: true).monospacedDigit().foregroundStyle(Palette.setup).frame(maxWidth: 44)
                } else {
                    Text(s.total.map(String.init) ?? "—").monospacedDigit().foregroundStyle(Palette.accentSoft)
                }
            } minimal: {
                Text(stale ? "—" : s.total.map(String.init) ?? "—").monospacedDigit().foregroundStyle(stale ? Palette.danger : Palette.accentSoft)
            }
            .keylineTint(Palette.accent)
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
                Image(systemName: "line.diagonal").foregroundStyle(Palette.accentSoft)
                Text("MuonP4").font(.subheadline.weight(.semibold))
                PhasePill(phase: stale ? .overdue : state.phase)
                Spacer()
                if let d = state.sampleDate { (Text(d, style: .relative) + Text(" ago")).font(.caption).foregroundStyle(.secondary) }
            }
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(stale ? "—" : state.total.map(String.init) ?? "—").font(.system(size: 44, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("coincidences / min").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    MinuteBars(values: state.recent, tint: Palette.accentSoft).frame(width: 170, height: 40)
                    Text("last 30 min · 1 bar per minute").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { i in
                    Text("\(["CH01", "CH02", "CH12"][i]) ").foregroundStyle(.secondary) + Text(state.pairs.count > i ? "\(state.pairs[i])" : "—").monospacedDigit()
                }
                Spacer()
                EnvLine(state: state)
            }
            .font(.caption)
        }
        .padding(16)
    }
}

struct PhasePill: View {
    let phase: Phase
    var body: some View {
        Text(phase == .physics ? "Physics" : phase.title)
            .font(.caption2.weight(.semibold)).foregroundStyle(phase.tint)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(phase.tint.opacity(0.2), in: Capsule())
    }
}

struct PairColumn: View {
    let pairs: [Int]
    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 1) {
            ForEach(0..<3, id: \.self) { i in
                GridRow {
                    Text(["CH01", "CH02", "CH12"][i]).foregroundStyle(.secondary)
                    Text(pairs.count > i ? "\(pairs[i])" : "—").monospacedDigit()
                }
            }
        }.font(.caption2)
    }
}

struct EnvLine: View {
    let state: MuonActivity.ContentState
    var body: some View {
        HStack(spacing: 4) {
            if let p = state.pressure { Text(String(format: "%.1f hPa", p)).monospacedDigit() }
            if let t = state.temperature { Text("·").foregroundStyle(.secondary); Text(String(format: "%.1f °C", t)).monospacedDigit() }
        }
    }
}
