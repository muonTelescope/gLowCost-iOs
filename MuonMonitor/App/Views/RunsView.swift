import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RunsView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Run.start, order: .reverse) private var runs: [Run]
    @State private var filter: String?
    @State private var search = ""
    @State private var importing = false
    @State private var importFromFolder = false
    @State private var importMessage: String?
    @State private var comparing = false

    private var usedTags: [String] {
        let used = Set(runs.flatMap(\.tags))
        return TagCatalog.defaults.filter(used.contains) + used.subtracting(TagCatalog.defaults).sorted()
    }
    private var visible: [Run] {
        runs.filter { r in
            (filter == nil || r.tags.contains(filter!)) &&
            (search.isEmpty || r.name.localizedCaseInsensitiveContains(search) || r.tags.contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }
    private var sections: [(String, [Run])] {
        let groups = Dictionary(grouping: visible.filter { !$0.isLive }) { $0.start.formatted(.dateTime.month(.wide).year()) }
        return groups.sorted { ($0.value.first?.start ?? .distantPast) > ($1.value.first?.start ?? .distantPast) }.map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !usedTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Button { filter = nil } label: { TagChip(tag: "All", selected: filter == nil) }
                            ForEach(usedTags, id: \.self) { t in
                                Button { filter = filter == t ? nil : t } label: { TagChip(tag: t, selected: filter == t) }
                            }
                        }.buttonStyle(.plain)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
                if let live = visible.first(where: \.isLive) {
                    Section {
                        NavigationLink(value: live) { RunRow(run: live, live: true) }
                    } header: { Label("Recording now", systemImage: "record.circle").foregroundStyle(Palette.danger) }
                }
                ForEach(sections, id: \.0) { title, items in
                    Section(title) {
                        ForEach(items) { run in
                            NavigationLink(value: run) { RunRow(run: run, live: false) }
                                .swipeActions { Button("Delete", role: .destructive) { app.delete(run) } }
                        }
                    }
                }
                if runs.isEmpty {
                    ContentUnavailableView("No runs yet", systemImage: "list.bullet.rectangle",
                                           description: Text("Start logging on Now, or import SD-card CSVs with the download button."))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Runs")
            .searchable(text: $search, prompt: "Name or tag")
            .navigationDestination(for: Run.self) { RunDetailView(run: $0) }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { comparing = true } label: { Image(systemName: "square.2.layers.3d") }.accessibilityLabel("Compare runs").disabled(runs.count < 2)
                    Menu {
                        Button("Choose CSV files…", systemImage: "doc") { importing = true }
                        Button("From my cosmic folder…", systemImage: "folder") { importFromFolder = true }.disabled(!app.cloud.isConfigured)
                    } label: { Image(systemName: "square.and.arrow.down") }.accessibilityLabel("Import SD-card logs")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText], allowsMultipleSelection: true) { result in
                importMessage = importFiles((try? result.get()) ?? [])
            }
            .sheet(isPresented: $importFromFolder) { FolderImportView { importMessage = $0 } }
            .sheet(isPresented: $comparing) { CompareView(runs: runs) }
            .alert("Import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                Button("OK") {}
            } message: { Text(importMessage ?? "") }
        }
    }

    /// Pairs muon_X.csv with env_X.csv when both are chosen.
    private func importFiles(_ urls: [URL]) -> String {
        func text(_ u: URL) -> String? {
            let ok = u.startAccessingSecurityScopedResource(); defer { if ok { u.stopAccessingSecurityScopedResource() } }
            return try? String(contentsOf: u, encoding: .utf8)
        }
        let env = Dictionary(uniqueKeysWithValues: urls.filter { $0.lastPathComponent.hasPrefix("env_") }.compactMap { u in
            text(u).map { (String(u.lastPathComponent.dropFirst(4)), $0) } })
        let muons = urls.filter { $0.lastPathComponent.hasPrefix("muon_") }
        guard !muons.isEmpty else { return "Choose at least one muon_….csv file (its env_….csv adds pressure and temperature for older logs)." }
        return muons.compactMap { u -> String? in
            guard let t = text(u) else { return "\(u.lastPathComponent) could not be read." }
            return app.importSD(text: t, fileName: u.lastPathComponent, envText: env[String(u.lastPathComponent.dropFirst(5))])
        }.joined(separator: "\n")
    }
}

struct RunRow: View {
    let run: Run
    let live: Bool
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(run.name).font(.headline).lineLimit(1)
                Text(summary).font(.subheadline).foregroundStyle(Palette.secondaryText).monospacedDigit()
                if !run.tags.isEmpty {
                    HStack(spacing: 4) { ForEach(run.tags.prefix(3), id: \.self) { TagChip(tag: $0) } }
                }
            }
            Spacer(minLength: 8)
            Sparkline(values: hourly).frame(width: 90, height: 28)
            if run.exportedAt != nil {
                Image(systemName: "checkmark.icloud").foregroundStyle(Palette.physics).accessibilityLabel("Saved to your cosmic folder")
            }
        }
        .padding(.vertical, 4)
    }
    private var summary: String {
        var s = run.start.formatted(.dateTime.month(.abbreviated).day())
        s += " · " + run.duration.hoursMinutes
        if let r = run.meanRate { s += String(format: " · %.1f /min", r) }
        if run.source == "sd" { s += " · SD" }
        return s
    }
    private var hourly: [Double] {
        let recs = run.records.filter(\.physics)
        guard let first = recs.first?.epoch else { return [] }
        var bins: [Int: (Int, Int)] = [:]
        for r in recs { let k = Int((r.epoch - first) / 3600); let b = bins[k] ?? (0, 0); bins[k] = (b.0 + r.coincidences, b.1 + 1) }
        return bins.keys.sorted().map { Double(bins[$0]!.0) / Double(bins[$0]!.1) }
    }
}

/// Lists muon_*.csv files already in the chosen cosmic folder (e.g. rawData) for import.
struct FolderImportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let done: (String) -> Void
    @State private var files: [URL] = []
    @State private var chosen = Set<URL>()
    var body: some View {
        NavigationStack {
            List(files, id: \.self, selection: $chosen) { u in
                Text(u.lastPathComponent).font(.footnote.monospaced())
            }
            .environment(\.editMode, .constant(.active))
            .overlay { if files.isEmpty { ContentUnavailableView("No SD logs found", systemImage: "folder", description: Text("Put muon_….csv files anywhere in your cosmic folder, for example in rawData.")) } }
            .navigationTitle("Import from folder").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(chosen.count)") {
                        var msgs: [String] = []
                        for u in chosen {
                            guard let t = try? app.cloud.read(u) else { msgs.append("\(u.lastPathComponent) could not be read."); continue }
                            let envURL = u.deletingLastPathComponent().appendingPathComponent("env_" + u.lastPathComponent.dropFirst(5))
                            msgs.append(app.importSD(text: t, fileName: u.lastPathComponent, envText: try? app.cloud.read(envURL)))
                        }
                        done(msgs.joined(separator: "\n")); dismiss()
                    }.disabled(chosen.isEmpty)
                }
            }
            .task { files = app.cloud.sdLogs() }
        }
    }
}
