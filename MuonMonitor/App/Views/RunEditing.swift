import SwiftUI

/// Rename a run. For the live run this also changes the detector's run label,
/// which renames the active SD files (muon_… and env_…).
struct RenameSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let run: Run
    @State private var name = ""
    @State private var sendToDetector = true
    @State private var saving = false
    @State private var error: String?

    private var canSend: Bool { run.isLive && app.link.controlsReady }
    private var label: String { RunLabel.sanitize(name) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Run name", text: $name).font(.title3).submitLabel(.done)
                } footer: {
                    Text("Shown in the app, in Runs, and as the folder name in your cosmic folder.")
                }
                if run.isLive {
                    Section {
                        Toggle("Rename on the detector too", isOn: $sendToDetector).disabled(!canSend)
                        if sendToDetector {
                            LabeledContent("SD label", value: label.isEmpty ? "—" : label).font(.footnote.monospaced())
                            if let file = app.status.logFile.isEmpty ? nil : app.status.logFile {
                                Text("The detector renames \(file) and its env file to end in _\(label).csv")
                                    .font(.caption).foregroundStyle(Palette.secondaryText)
                            }
                        }
                    } footer: {
                        Text(canSend ? "Labels keep letters, numbers, - and _. Spaces become _. Up to 32 characters."
                                     : "Connect to the detector to rename its SD files. The app name changes now.")
                    }
                }
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.warning) } }
            }
            .navigationTitle("Rename run").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        saving = true
                        Task {
                            do { try await app.rename(run, to: name, sendToDetector: sendToDetector && canSend); dismiss() }
                            catch { self.error = "Renamed in the app, but the detector did not confirm: \(error.localizedDescription)" }
                            saving = false
                        }
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear { name = run.name; sendToDetector = canSend }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Default tag groups plus custom tags. New custom tags are remembered for later runs.
struct TagEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let run: Run
    @State private var tags: Set<String> = []
    @State private var newTag = ""
    @State private var custom: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                ForEach(TagCatalog.groups) { g in
                    Section(g.id) { chips(g.tags) }
                }
                Section("Your tags") {
                    if !custom.isEmpty { chips(custom) }
                    HStack {
                        TextField("New tag", text: $newTag).submitLabel(.done).onSubmit(add)
                        Button("Add", action: add).disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Tags").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let ordered = (TagCatalog.defaults + custom).filter(tags.contains)
                        app.setTags(run, ordered + tags.subtracting(ordered).sorted())
                        dismiss()
                    }
                }
            }
            .onAppear {
                tags = Set(run.tags)
                custom = Array(Set(TagCatalog.custom + run.tags.filter { !TagCatalog.defaults.contains($0) })).sorted()
            }
        }
    }

    private func chips(_ list: [String]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(list, id: \.self) { t in
                Button { if tags.contains(t) { tags.remove(t) } else { tags.insert(t) } } label: { TagChip(tag: t, selected: tags.contains(t)) }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tags.contains(t) ? .isSelected : [])
            }
        }
    }

    private func add() {
        let t = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        TagCatalog.addCustom(t)
        if !custom.contains(t) && !TagCatalog.defaults.contains(t) { custom.append(t); custom.sort() }
        tags.insert(t); newTag = ""
    }
}
