import Foundation

enum RecordIntegrity {
    static func hash(_ data: Data) -> UInt32 { data.reduce(2166136261) { ($0 ^ UInt32($1)) &* 16777619 } }
    static func deviceKey(_ id: String) -> String { id.replacingOccurrences(of: ":", with: "").lowercased() }
}
