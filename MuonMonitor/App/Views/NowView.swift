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
            HStack(spacing: 8) {
                PhaseBadge(phase: app.phase)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(statusLine(now: ctx.date)).font(.footnote).foregroundStyle(Palette.secondaryText).lineLimit(2)
                }
            }
            if let issue = app.issue ?? app.link.problem {
                Label(issue, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Palette.warning)
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
            Text("Not logging").font(.title3.weight(.semibold))
            Text("Start logging near your detector. The phone records every minute it receives, with GPS, and keeps going with the screen locked.")
                .font(.subheadline).foregroundStyle(Palette.secondaryText)
            Button {
                if app.needsPairing { showPair = true } else { app.start() }
            } label: {
                Label(app.needsPairing ? "Find a detector" : "Start logging", systemImage: app.needsPairing ? "dot.radiowaves.left.and.right" : "record.circle")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
        }
        .card(padding: 18)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            TrackPlate(count: last?.coincidences ?? 0, seed: UInt64(bitPattern: Int64(last?.epoch ?? 0)))
            LinearGradient(colors: [Palette.hero.opacity(0), Palette.hero.opacity(0.94)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text("COINCIDENCES, LAST MINUTE").font(.caption2.weight(.medium)).tracking(0.8).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(last.map { "\($0.coincidences)" } ?? "—")
                        .font(.system(size: 96, weight: .light, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("per min").font(.headline).foregroundStyle(.secondary)
                }
                if let l = last {
                    Text("CH01 + CH02 + CH12 · raw counts · \(l.date.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(22)
        }
        .frame(height: 300)
        .background(Palette.hero)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Palette.track.opacity(0.14)))
        .animation(.snappy, value: last?.coincidences)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(last?.coincidences ?? 0) coincidences in the last minute")
    }

    private var pairTiles: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { ch in
                VStack(alignment: .leading, spacing: 4) {
                    Text(MinuteRecord.channelNames[ch]).font(.caption2.weight(.medium)).foregroundStyle(Palette.secondaryText)
                    Text(last.map { "\(max($0.counts[ch], 0))" } ?? "—").font(.system(.title2, design: .monospaced).weight(.medium))
                    Sparkline(values: tenMinuteMeans(ch)).frame(height: 20)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last hour").font(.headline)
                Spacer()
                Text(valid.isEmpty ? "" : String(format: "mean %.1f", Double(valid.reduce(0, +)) / Double(valid.count)) + (gaps > 0 ? " · \(gaps) min gap" : ""))
                    .font(.caption.monospaced()).foregroundStyle(Palette.secondaryText)
            }
            MinuteBars(values: values).frame(height: 60)
        }
        .card()
    }

    private var environment: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PRESSURE").font(.caption2.weight(.medium)).tracking(0.8).foregroundStyle(Palette.pressure)
                Text(last?.pressure.map { "\($0.hpa) hPa" } ?? "—").font(.system(.title3, design: .monospaced))
                if let d = app.pressureChange3h {
                    Text(abs(d) < 0.3 ? "Steady over 3 h" : String(format: "%@ %.1f hPa in 3 h", d < 0 ? "Falling" : "Rising", abs(d)))
                        .font(.caption).foregroundStyle(Palette.secondaryText)
                }
            }.card()
            VStack(alignment: .leading, spacing: 6) {
                Text("DETECTOR TEMP").font(.caption2.weight(.medium)).tracking(0.8).foregroundStyle(Palette.temperature)
                Text(last?.temperature.map { String(format: "%.1f °C", $0) } ?? "—").font(.system(.title3, design: .monospaced))
                Text("Recorded with each minute").font(.caption).foregroundStyle(Palette.secondaryText)
            }.card()
        }
    }

    private var session: some View {
        let t = app.sessionTotals
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Text("This session").font(.headline); Spacer(); Text("valid physics only").font(.caption).foregroundStyle(Palette.secondaryText) }
            HStack(spacing: 18) {
                stat(t.muons.formatted(), "coincidences")
                stat((Double(t.minutes) * 60).hoursMinutes, "exposure")
                stat(t.minutes > 0 ? String(format: "%.1f", Double(t.muons) / Double(t.minutes)) : "—", "mean /min")
            }
            Text("Σ CH01 \(t.pairs[0].formatted()) · CH02 \(t.pairs[1].formatted()) · CH12 \(t.pairs[2].formatted())")
                .font(.caption.monospaced()).foregroundStyle(Palette.secondaryText)
        }
        .card()
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading) { Text(v).font(.system(.title3, design: .monospaced)); Text(l).font(.caption).foregroundStyle(Palette.secondaryText) }
    }

    @ViewBuilder private var healthCard: some View {
        let report = Health.report(app.recent)
        if report.allSatisfy({ $0.minutes >= 30 }) {
            let worst = report.max { $0.fano < $1.fano }!
            HStack(spacing: 12) {
                Image(systemName: worst.level == .good ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.title3).foregroundStyle(worst.level == .good ? Palette.physics : Palette.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(worst.level == .good ? "Counting looks clean" : "More variation than expected").font(.subheadline.weight(.semibold))
                    Text(String(format: "Spread vs pure chance: CH01 %.2f · CH02 %.2f · CH12 %.2f (1.00 is ideal)", report[0].fano, report[1].fano, report[2].fano))
                        .font(.caption).foregroundStyle(Palette.secondaryText)
                }
            }
            .card()
        }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "line.diagonal").font(.title2).foregroundStyle(Palette.track)
                VStack(alignment: .leading, spacing: 4) {
                    Text("What are the lines?").font(.subheadline.weight(.semibold))
                    Text("Each line is one muon from the last minute. Muons are heavy cousins of the electron, made when cosmic rays hit air about 15 km up. Most arrive close to straight down, and roughly one crosses your palm every second.")
                        .font(.footnote).foregroundStyle(.secondary)
                    DisclosureGroup("How the detector counts them", isExpanded: $explainerOpen) {
                        Text("Three scintillator paddles each give off a flash of light when a charged particle passes through. Silicon photomultipliers turn the flash into a pulse. A coincidence is two paddles firing within the same short window, which rejects most noise. CH01, CH02 and CH12 are the three possible pairs; the big number is their sum.")
                            .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                    }
                    .font(.footnote.weight(.medium)).tint(Palette.accent)
                }
            }
        }
        .padding(14)
        .background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.accent.opacity(0.22)))
    }
}
