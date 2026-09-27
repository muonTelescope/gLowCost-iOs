import SwiftUI

struct NowView: View {
    @Environment(AppModel.self) private var app
    @State private var showPair = false
    @State private var showShare = false
    @State private var explainerOpen = false

    private var last: MinuteRecord? { app.recent.last }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if !app.logging { idleCard } else {
                        hero
                        pairTiles
                        lastHour
                        environment
                        session
                        healthCard
                    }
                    explainer
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
            .background(Palette.background)
            .navigationTitle("Now")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share this minute").disabled(last == nil)
                }
            }
            .sheet(isPresented: $showPair) { PairView() }
            .sheet(isPresented: $showShare) { ShareCardSheet() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if app.demo { DemoBanner() }
            Text(app.currentRun.map { "MuonP4 · \($0.name)" } ?? "MuonP4").capsLabel().lineLimit(1)
            PhaseBadge(phase: app.phase)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(statusLine(now: ctx.date)).font(Typography.footnote).foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let issue = app.issue ?? app.link.problem {
                Label(issue, systemImage: "exclamationmark.triangle").font(Typography.footnote).foregroundStyle(Palette.alert)
            }
        }
    }

    private func statusLine(now: Date) -> String {
        if let ends = app.setupEnds, ends > now {
            return "Physics starts in about \(Int(ends.timeIntervalSince(now))) s · Wi‑Fi on"
        }
        guard let end = app.lastMinuteEnd else { return app.logging ? "Waiting for the first complete minute" : "" }
        let s = Int(now.timeIntervalSince(end))
        let age = s < 120 ? "\(s) s ago" : "\(s / 60) min ago"
        var parts = ["Minute ended \(age)"]
        if let t = app.latest { parts.append(t.flags & 16 != 0 ? "Wi‑Fi off" : "Wi‑Fi on"); if t.flags & 32 != 0 { parts.append("HV settled") } }
        return parts.joined(separator: " · ")
    }

    private var idleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Not logging").font(Typography.title2)
            Text("Start logging near your detector. The phone records every minute it receives, with GPS, and keeps going with the screen locked.")
                .font(Typography.subheadline.weight(.medium)).foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if app.needsPairing { showPair = true } else { app.start() }
            } label: {
                Label(app.needsPairing ? "Find a detector" : "Start logging", systemImage: app.needsPairing ? "dot.radiowaves.left.and.right" : "record.circle")
            }
            .buttonStyle(.muonPrimary)
        }
        .card(padding: 18, edge: .bright)
    }

    /// Hero: muon tracks from the last minute behind the count.
    /// Review fix 1: the fade starts above the caps label and the text sits on a
    /// solid strip, so no track runs through "COINCIDENCES, LAST MINUTE".
    private var hero: some View {
        let shape = ChamferedShape.panel(18)
        return ZStack(alignment: .bottomLeading) {
            TrackPlate(count: last?.coincidences ?? 0, seed: UInt64(bitPattern: Int64(last?.epoch ?? 0)))
            LinearGradient(stops: [.init(color: Palette.hero.opacity(0), location: 0.18),
                                   .init(color: Palette.hero.opacity(0.9), location: 0.42),
                                   .init(color: Palette.hero, location: 0.5),
                                   .init(color: Palette.hero, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text("Coincidences, last minute").capsLabel()
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(last.map { "\($0.coincidences)" } ?? "—")
                        .font(Typography.mono(92, .regular, relativeTo: .largeTitle)).monospacedDigit()
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                    Text("muons / min").font(Typography.raleway(17, .bold, relativeTo: .headline)).foregroundStyle(Palette.data)
                        .lineLimit(1).fixedSize()
                }
                if let l = last {
                    HStack(spacing: 6) {
                        ChannelLabel(channel: -1, size: 13)
                        Text("· raw counts · \(l.date.formatted(date: .omitted, time: .shortened))")
                            .font(Typography.monoCaption).foregroundStyle(Palette.secondaryText).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
            .padding(20)
        }
        .frame(height: 300)
        .background(Palette.hero)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Palette.brightEdge, lineWidth: 1) }
        .animation(.snappy, value: last?.coincidences)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(last?.coincidences ?? 0) coincidences in the last minute")
    }

    private var pairTiles: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { ch in
                VStack(alignment: .leading, spacing: 6) {
                    ChannelLabel(channel: ch, size: 15)
                    Text(last.map { "\(max($0.counts[ch], 0))" } ?? "—").font(Typography.monoLarge).foregroundStyle(Palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Sparkline(values: tenMinuteMeans(ch)).frame(height: 20)
                }
                .panel(padding: 12, cut: 12)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func tenMinuteMeans(_ ch: Int) -> [Double] {
        let phys = app.recent.filter(\.physics).suffix(60)
        return stride(from: 0, to: phys.count, by: 10).map { i in
            let slice = phys.dropFirst(i).prefix(10)
            return Double(slice.reduce(0) { $0 + max($1.counts[ch], 0) }) / Double(max(slice.count, 1))
        }
    }

    private var lastHour: some View {
        let values = app.recentTotals(60)
        let valid = values.filter { $0 >= 0 }
        let gaps = values.filter { $0 < 0 }.count
        let end = last?.date
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last hour").font(Typography.headline)
                Spacer(minLength: 8)
                Text(valid.isEmpty ? "" : String(format: "mean %.1f", Double(valid.reduce(0, +)) / Double(valid.count)) + (gaps > 0 ? " · \(gaps) min gap" : ""))
                    .font(Typography.monoCaption).foregroundStyle(Palette.secondaryText).lineLimit(1).minimumScaleFactor(0.8)
            }
            MinuteBars(values: values).frame(height: 60)
            if let end {
                HStack {
                    ForEach([60.0, 30.0, 0.0], id: \.self) { m in
                        Text(end.addingTimeInterval(-m * 60).formatted(date: .omitted, time: .shortened))
                        if m > 0 { Spacer() }
                    }
                }
                .font(Typography.mono(10, .regular, relativeTo: .caption2)).foregroundStyle(Palette.secondaryText)
            }
        }
        .card()
    }

    private var environment: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pressure").capsLabel(Palette.pressure)
                valueWithUnit(last?.pressure.map(\.hpa), "hPa")
                if let d = app.pressureChange3h, abs(d) >= 0.3 {
                    Text(abs(d) < 0.3 ? "Steady over 3 h" : String(format: "%@ %.1f hPa in 3 h", d < 0 ? "Falling" : "Rising", abs(d)))
                        .font(Typography.caption).foregroundStyle(Palette.secondaryText).lineLimit(2).minimumScaleFactor(0.85)
                }
            }.card()
            VStack(alignment: .leading, spacing: 6) {
                Text("Detector temp").capsLabel(Palette.temperature)
                valueWithUnit(last?.temperature.map { String(format: "%.1f", $0) }, "°C")
            }.card()
        }
    }

    private func valueWithUnit(_ v: String?, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(v ?? "—").font(Typography.monoValue).foregroundStyle(Palette.ink)
            if v != nil { Text(unit).font(Typography.monoCaption).foregroundStyle(Palette.secondaryText) }
        }
        .lineLimit(1).minimumScaleFactor(0.7)
    }

    private var session: some View {
        let t = app.sessionTotals
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("This session").font(Typography.headline)
                Spacer(minLength: 8)
                Text("valid physics only").font(Typography.caption).foregroundStyle(Palette.secondaryText).lineLimit(1)
            }
            // Review fix 6: three equal columns; labels shrink rather than wrap.
            HStack(alignment: .top, spacing: 12) {
                stat(t.muons.formatted(), "coincidences")
                stat((Double(t.minutes) * 60).hoursMinutes, "exposure")
                stat(t.minutes > 0 ? String(format: "%.1f", Double(t.muons) / Double(t.minutes)) : "—", "mean /min")
            }
            ViewThatFits(in: .horizontal) {
                sessionPairs(size: 15)
                sessionPairs(size: 13)
                VStack(alignment: .leading, spacing: 4) { pairTotal(-1, t.muons, size: 15); ForEach(0..<3, id: \.self) { pairTotal($0, t.pairs[$0], size: 15) } }
            }
        }
        .card()
    }

    private func sessionPairs(size: CGFloat) -> some View {
        let t = app.sessionTotals
        return HStack(spacing: 10) {
            pairTotal(-1, t.muons, size: size)
            ForEach(0..<3, id: \.self) { pairTotal($0, t.pairs[$0], size: size) }
        }
    }

    private func pairTotal(_ ch: Int, _ n: Int, size: CGFloat) -> some View {
        HStack(spacing: 4) {
            ChannelLabel(channel: ch, size: size)
            Text(n.formatted()).font(Typography.mono(size - 2, .regular, relativeTo: .caption)).foregroundStyle(Palette.ink)
        }.fixedSize()
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(Typography.mono(19, .medium, relativeTo: .title3)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(Typography.caption).foregroundStyle(Palette.secondaryText).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var healthCard: some View {
        let report = Health.report(app.currentRun?.records ?? app.recent)
        if report.allSatisfy({ $0.minutes >= 30 }), let worst = report.max(by: { $0.fano < $1.fano }) {
            HStack(spacing: 12) {
                Image(systemName: worst.level == .good ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.system(size: 20)).foregroundStyle(worst.level == .good ? Palette.physics : Palette.alert)
                VStack(alignment: .leading, spacing: 4) {
                    Text(worst.level == .good ? "Counting looks clean" : "More variation than expected").font(Typography.subheadline)
                    HStack(spacing: 10) {
                        ForEach(report.prefix(3)) { r in
                            HStack(spacing: 4) {
                                ChannelLabel(channel: r.channel, size: 13)
                                Text(String(format: "%.2f", r.fano)).font(Typography.monoCaption).foregroundStyle(Palette.ink)
                            }
                        }
                    }
                    Text("Spread vs pure chance, 1.00 is ideal").font(Typography.caption).foregroundStyle(Palette.secondaryText)
                }
            }
            .card()
        }
    }

    private var explainer: some View {
        HStack(alignment: .top, spacing: 12) {
            MuonMark(size: 26, color: Palette.track)
            VStack(alignment: .leading, spacing: 4) {
                Text("What are the lines?").font(Typography.subheadline)
                Text("Each line is one muon from the last minute. Muons are heavy cousins of the electron, made when cosmic rays hit air about 15 km up. Most arrive close to straight down, and roughly one crosses your palm every second.")
                    .font(Typography.footnote).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("How the detector counts them", isExpanded: $explainerOpen) {
                    Text("Three scintillator paddles, numbered 0, 1 and 2, each give off a flash of light when a charged particle passes through. Silicon photomultipliers turn the flash into a pulse. A coincidence is two paddles firing within the same short window, which rejects most noise. CH⁰₁, CH⁰₂ and CH¹₂ are the three possible pairs (the digits name the paddles); the big number, ΣCH, is their sum.")
                        .font(Typography.footnote).foregroundStyle(Palette.secondaryText).padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Typography.raleway(13, .semibold, relativeTo: .footnote)).tint(Palette.lilac)
            }
        }
        .panel(padding: 14, fill: Palette.raised)
    }
}
