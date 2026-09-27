import Foundation
import Observation

/// Saves runs into a folder the user picks once — normally iCloud Drive › cosmic.
/// Uses a security-scoped bookmark, so it needs no iCloud entitlement and works
/// with a free Apple developer account. Files land in <folder>/phone/<run>/.
@Observable
final class CloudFolder {
    private(set) var folderName: String?
    private(set) var lastSave: Date?
    private(set) var problem: String?
    @ObservationIgnored private let key = "cosmicBookmark"

    init() { folderName = resolve()?.lastPathComponent }

    var isConfigured: Bool { UserDefaults.standard.data(forKey: key) != nil }

    /// Call with the URL from .fileImporter(allowedContentTypes: [.folder]).
    func choose(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: key)
            folderName = url.lastPathComponent; problem = nil
        } catch { problem = "Could not remember that folder: \(error.localizedDescription)" }
    }

    func forget() { UserDefaults.standard.removeObject(forKey: key); folderName = nil }

    private func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: key)
        }
        return url
    }

    /// Runs `body` with security-scoped access to the chosen folder.
    private func withFolder<T>(_ body: (URL) throws -> T) throws -> T {
        guard let root = resolve() else { throw LinkError("Choose your cosmic folder in Settings") }
        guard root.startAccessingSecurityScopedResource() else { throw LinkError("iOS denied access to \(root.lastPathComponent). Choose the folder again in Settings.") }
        defer { root.stopAccessingSecurityScopedResource() }
        return try body(root)
    }

    /// Coordinated write so iCloud Drive sees consistent files.
    private func coordinatedWrite(_ url: URL, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var inner: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { u in
            do { try body(u) } catch { inner = error }
        }
        if let coordinationError { throw coordinationError }
        if let inner { throw inner }
    }

    struct RunFile: Codable {
        var name: String; var detectorLabel: String?; var device: String?; var start: Date; var end: Date?
        var tags: [String]; var notes: String; var source: String
        var events: [Event]; var minutes: Int; var physicsMinutes: Int
        var health: [String: Double]
        struct Event: Codable { var date: Date; var kind: String; var detail: String }
    }

    /// Writes phone/<folder>/minutes.csv and run.json. Renames the run folder when the run was renamed.
    @discardableResult
    func save(_ run: Run) -> Bool {
        let records = run.records
        let folder = CSVExport.folderName(start: run.start, name: run.name)
        let health = Health.report(records).reduce(into: [String: Double]()) { $0["fano_\(MinuteRecord.channelNames[$1.channel])"] = $1.fano.isFinite ? $1.fano : nil }
        let meta = RunFile(name: run.name, detectorLabel: run.detectorLabel, device: run.deviceID, start: run.start, end: run.end,
                           tags: run.tags, notes: run.notes, source: run.source,
                           events: run.events.sorted { $0.date < $1.date }.map { .init(date: $0.date, kind: $0.kind, detail: $0.detail) },
                           minutes: records.count, physicsMinutes: records.filter(\.physics).count, health: health)
        do {
            try withFolder { root in
                let fm = FileManager.default
                let phone = root.appendingPathComponent("phone", isDirectory: true)
                try fm.createDirectory(at: phone, withIntermediateDirectories: true)
                let dir = phone.appendingPathComponent(folder, isDirectory: true)
                if let old = run.exportFolder, old != folder {
                    let oldURL = phone.appendingPathComponent(old, isDirectory: true)
                    if fm.fileExists(atPath: oldURL.path), !fm.fileExists(atPath: dir.path) { try fm.moveItem(at: oldURL, to: dir) }
                }
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let csv = CSVExport.csv(records)
                try coordinatedWrite(dir.appendingPathComponent("minutes.csv")) { try csv.write(to: $0, atomically: true, encoding: .utf8) }
                let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
                let json = try enc.encode(meta)
                try coordinatedWrite(dir.appendingPathComponent("run.json")) { try json.write(to: $0, options: .atomic) }
            }
            run.exportFolder = folder; run.exportedAt = Date(); lastSave = Date(); problem = nil
            return true
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    /// SD logs already in the folder (e.g. cosmic/rawData), for import.
    func sdLogs() -> [URL] {
        (try? withFolder { root in
            let fm = FileManager.default
            let e = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            var out: [URL] = []
            while let u = e?.nextObject() as? URL {
                if u.pathComponents.contains("phone") { continue }
                let n = u.lastPathComponent
                if n.hasPrefix("muon_") && n.hasSuffix(".csv") { out.append(u) }
            }
            return out.sorted { $0.lastPathComponent > $1.lastPathComponent }
        }) ?? []
    }

    /// Reads a file inside the chosen folder (coordinated, downloads from iCloud if needed).
    func read(_ url: URL) throws -> String {
        try withFolder { _ in
            var err: NSError?; var text = ""
            var readError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in
                do { text = try String(contentsOf: u, encoding: .utf8) } catch { readError = error }
            }
            if let err { throw err }
            if let readError { throw readError }
            return text
        }
    }
}
