import Foundation
import CoreBluetooth
import Observation

/// Bluetooth link to MuonP4 (protocol v4). Transport logic is carried over
/// unchanged from the hardware-tested monitor: notify tokens trigger full
/// 160-byte reads, one command at a time, no automatic retry of mutations.
@Observable
final class DetectorLink: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let service = CBUUID(string: "73B47A10-6F6E-4D75-9A50-4D756F6E5034")
    static let sampleID = CBUUID(string: "73B47A11-6F6E-4D75-9A50-4D756F6E5034")
    static let controlID = CBUUID(string: "73B47A12-6F6E-4D75-9A50-4D756F6E5034")
    static let responseID = CBUUID(string: "73B47A13-6F6E-4D75-9A50-4D756F6E5034")

    enum State: Equatable { case idle, bluetoothOff, unauthorized, searching, connecting, connected }
    struct Nearby: Identifiable, Equatable { let id: UUID; let name: String; var rssi: Int; var lastMinute: Int? }

    private(set) var state: State = .idle
    private(set) var controlsReady = false
    private(set) var rssi: Int?
    private(set) var nearby: [Nearby] = []
    private(set) var problem: String?
    var knownDetector: UUID? {
        get { UserDefaults.standard.string(forKey: "peripheral").flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "peripheral") }
    }

    @ObservationIgnored var onSample: ((Telemetry) -> Void)?
    @ObservationIgnored var onDisconnect: (() -> Void)?
    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var sampleChar: CBCharacteristic?
    @ObservationIgnored private var commandChar: CBCharacteristic?
    @ObservationIgnored private var responseChar: CBCharacteristic?
    @ObservationIgnored private var readPending = false
    @ObservationIgnored private var readStarted = Date.distantPast
    @ObservationIgnored var onDiagnostic: ((String) -> Void)?
    @ObservationIgnored private var wantsConnection = false
    @ObservationIgnored private var browsing = false
    @ObservationIgnored private var controlContinuation: CheckedContinuation<[String: Any], Error>?
    @ObservationIgnored private var requestID = UInt32.random(in: 1...UInt32.max)
    @ObservationIgnored private var controlTimeout: DispatchWorkItem?

    /// `restoring: false` for demo mode, so a demo session never claims the
    /// background-restoration identifier used by real logging.
    init(restoring: Bool = true) {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: restoring ? [CBCentralManagerOptionRestoreIdentifierKey: "MuonP4.monitor"] : nil)
    }

    // MARK: connection lifecycle

    /// Connect to the saved detector, or the first MuonP4 found when none is saved.
    func connect() { wantsConnection = true; problem = nil; discover() }

    func disconnect() {
        wantsConnection = false
        finishControl(.failure(LinkError("Logging stopped")))
        if central.state == .poweredOn {
            central.stopScan()
            if let p = peripheral { central.cancelPeripheralConnection(p) }
        }
        peripheral = nil; sampleChar = nil; commandChar = nil; responseChar = nil
        readPending = false; controlsReady = false; state = .idle
    }

    /// Scan without connecting, for the pairing screen.
    func browse(_ on: Bool) {
        browsing = on
        if on, central.state == .poweredOn {
            nearby = []
            central.scanForPeripherals(withServices: [Self.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        } else if !on, central.state == .poweredOn, !(wantsConnection && peripheral == nil) {
            central.stopScan()
        }
    }

    /// Remember a detector chosen on the pairing screen; logging connects to it.
    func remember(_ id: UUID) {
        knownDetector = id
        browse(false)
    }

    func forget() { disconnect(); knownDetector = nil }

    private func discover() {
        guard wantsConnection, central.state == .poweredOn else { return }
        if let p = peripheral {
            if p.state == .connected { p.discoverServices([Self.service]); return }
            if p.state == .connecting { return }
            attach(p); return
        }
        if let id = knownDetector, let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            attach(p); return
        }
        state = .searching
        central.scanForPeripherals(withServices: [Self.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func attach(_ p: CBPeripheral) {
        if !browsing { central.stopScan() }
        peripheral = p; p.delegate = self; state = .connecting
        central.connect(p, options: nil)
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: if state == .bluetoothOff || state == .unauthorized { state = .idle }; discover(); if browsing { browse(true) }
        case .poweredOff: state = .bluetoothOff
        case .unauthorized: state = .unauthorized
        default: break
        }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        onDiagnostic?("Core Bluetooth state restoration")
        guard let items = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = items.first else { return }
        wantsConnection = UserDefaults.standard.bool(forKey: "logging")
        guard wantsConnection else { return }
        peripheral = p; p.delegate = self
        readPending = false
        // Restoration runs before the manager is powered on; Core Bluetooth rejects
        // commands until then, so centralManagerDidUpdateState resumes via discover().
        if p.state == .connected { state = .connected; if c.state == .poweredOn { p.discoverServices([Self.service]) } }
        else { state = .connecting; discover() }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi RSSI: NSNumber) {
        if browsing {
            let minute = Self.advertisedMinute(ad[CBAdvertisementDataManufacturerDataKey] as? Data)
            let name = (ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? "MuonP4"
            if let i = nearby.firstIndex(where: { $0.id == p.identifier }) {
                nearby[i].rssi = RSSI.intValue; if minute != nil { nearby[i].lastMinute = minute }
            } else {
                nearby.append(Nearby(id: p.identifier, name: name, rssi: RSSI.intValue, lastMinute: minute))
            }
            return
        }
        guard wantsConnection, peripheral == nil else { return }
        rssi = RSSI.intValue
        attach(p)
    }

    /// CH01+CH02+CH12 from the scan-response manufacturer data, if present.
    static func advertisedMinute(_ d: Data?) -> Int? {
        guard let d, d.count >= 29, d[2] == 77, d[3] == 80, d[4] == 4 else { return nil }
        func u32(_ o: Int) -> Int { (0..<4).reduce(0) { $0 | Int(d[d.startIndex + o + $1]) << (8 * $1) } }
        return u32(17) + u32(21) + u32(25)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        knownDetector = p.identifier
        state = .connected; readPending = false
        p.delegate = self; p.discoverServices([Self.service]); p.readRSSI()
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { lost(p) }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { lost(p) }

    private func lost(_ p: CBPeripheral) {
        onDiagnostic?("BLE disconnected; reconnect requested")
        sampleChar = nil; commandChar = nil; responseChar = nil; readPending = false; controlsReady = false
        finishControl(.failure(LinkError("Bluetooth connection lost")))
        onDisconnect?()
        guard wantsConnection else { state = .idle; return }
        // A disconnect caused by Bluetooth turning off reconnects from centralManagerDidUpdateState.
        if central.state == .poweredOn { state = .connecting; central.connect(p, options: nil) }
    }

    func peripheral(_ p: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) { if error == nil { rssi = RSSI.intValue } }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let s = p.services?.first(where: { $0.uuid == Self.service }) else {
            problem = "This detector needs the protocol v4 firmware."; return
        }
        p.discoverCharacteristics([Self.sampleID, Self.controlID, Self.responseID], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard error == nil, let c = s.characteristics?.first(where: { $0.uuid == Self.sampleID }) else {
            problem = "Telemetry is unavailable on this detector."; return
        }
        sampleChar = c; p.setNotifyValue(true, for: c); read(p, c)
        commandChar = s.characteristics?.first { $0.uuid == Self.controlID }
        responseChar = s.characteristics?.first { $0.uuid == Self.responseID }
        if let r = responseChar { p.setNotifyValue(true, for: r) }
        controlsReady = commandChar != nil && responseChar != nil
    }

    private func read(_ p: CBPeripheral, _ c: CBCharacteristic) {
        if readPending, Date().timeIntervalSince(readStarted) <= 20 { return }
        if readPending { onDiagnostic?("Retrying stalled telemetry read") }
        readPending = true; readStarted = Date(); p.readValue(for: c)
    }

    /// Ask for the current telemetry now (e.g. when the app comes to the foreground).
    func refresh() { if let p = peripheral, let c = sampleChar, p.state == .connected { read(p, c); p.readRSSI() } }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        if c.uuid == Self.responseID { receiveControl(p, c, error); return }
        guard c.uuid == Self.sampleID else { return }
        if let error { onDiagnostic?("Telemetry read failed: \(error.localizedDescription)"); readPending = false; problem = "Read failed: \(error.localizedDescription)"; return }
        guard let data = c.value else { readPending = false; return }
        // 8-byte notify token "M N 04 …": read the full value.
        if data.count == 8, data[0] == 77, data[1] == 78, data[2] == 4 { read(p, c); return }
        readPending = false
        guard let t = Telemetry(data: data) else { problem = "Unsupported telemetry. Update the detector firmware."; return }
        problem = nil
        onSample?(t)
    }

    // MARK: commands (protocol v4 JSON)

    func command(_ op: String, _ values: [String: Any] = [:]) async throws -> [String: Any] {
        guard controlContinuation == nil else { throw LinkError("Another detector operation is running") }
        guard controlsReady, let p = peripheral, p.state == .connected, let c = commandChar else { throw LinkError("Connect to MuonP4 first") }
        requestID &+= 1; if requestID == 0 { requestID = 1 }
        var object = values; object["op"] = op; object["id"] = requestID
        let data = try JSONSerialization.data(withJSONObject: object)
        guard data.count <= 240 else { throw LinkError("Command is too long") }
        return try await withCheckedThrowingContinuation { continuation in
            controlContinuation = continuation
            let pending = requestID
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.controlContinuation != nil, self.requestID == pending else { return }
                self.finishControl(.failure(LinkError("No response. The command may still have run; check status before retrying.")))
            }
            controlTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: timeout)
            p.writeValue(data, for: c, type: .withResponse)
        }
    }

    func cancelCommand() { finishControl(.failure(CancellationError())) }

    private func pollControl() {
        let id = requestID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.controlContinuation != nil, self.requestID == id, let p = self.peripheral, let c = self.responseChar else { return }
            p.readValue(for: c)
        }
    }

    private func finishControl(_ result: Result<[String: Any], Error>) {
        controlTimeout?.cancel(); controlTimeout = nil
        let pending = controlContinuation; controlContinuation = nil
        pending?.resume(with: result)
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        guard c.uuid == Self.controlID else { return }
        if let error { finishControl(.failure(error)) } else { pollControl() }
    }

    private func receiveControl(_ p: CBPeripheral, _ c: CBCharacteristic, _ error: Error?) {
        guard controlContinuation != nil else { return }
        if let error { finishControl(.failure(error)); return }
        guard let data = c.value else { pollControl(); return }
        if data == Data([79, 75]) { p.readValue(for: c); return }   // "OK" token
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (obj["id"] as? NSNumber)?.uint32Value == requestID else { pollControl(); return }
        if obj["ok"] as? Bool == true { finishControl(.success(obj)) }
        else { finishControl(.failure(LinkError(obj["error"] as? String ?? "Detector rejected the command"))) }
    }

    // MARK: downloads

    /// Downloads an SD file in 240-byte chunks with a fixed limit, so a growing log ends at a coherent prefix.
    func download(name: String, progress: @escaping (Int, Int) -> Void) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let final = dir.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent)
        let part = final.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: part)
        FileManager.default.createFile(atPath: part.path, contents: nil)
        let file = try FileHandle(forWritingTo: part)
        defer { try? file.close(); try? FileManager.default.removeItem(at: part) }
        var offset = 0, limit: Int?
        while true {
            try Task.checkCancellation()
            var args: [String: Any] = ["name": name, "offset": offset]; if let limit { args["limit"] = limit }
            let r = try await command("file", args)
            guard let raw = r["data"] as? String, let data = Data(base64Encoded: raw), let next = r["next"] as? Int,
                  let size = r["limit"] as? Int, next == offset + data.count, limit == nil || limit == size else { throw LinkError("Invalid file response") }
            if limit == nil { limit = size }
            try file.write(contentsOf: data); offset = next; progress(offset, size)
            if r["eof"] as? Bool == true { break }
            guard !data.isEmpty else { throw LinkError("File transfer stalled") }
        }
        try file.synchronize(); try file.close()
        try? FileManager.default.removeItem(at: final)
        try FileManager.default.moveItem(at: part, to: final)
        return final
    }

    /// Immutable boot/sequence records. A cancelled row restarts; committed rows are never re-fetched.
    func readRecord(boot: String, sequence: Int) async throws -> String {
        var data = Data(), expectedLength: Int?, expectedHash: UInt32?
        repeat {
            try Task.checkCancellation()
            let reply = try await command("record", ["boot": boot, "seq": sequence, "offset": data.count])
            guard let raw = reply["data"] as? String, let part = Data(base64Encoded: raw),
                  let next = reply["next"] as? Int, next == data.count + part.count,
                  let length = reply["length"] as? Int, length > 0, length < 4096,
                  let hash = (reply["hash"] as? NSNumber)?.uint32Value,
                  expectedLength == nil || expectedLength == length, expectedHash == nil || expectedHash == hash,
                  !part.isEmpty, next <= length else { throw LinkError("Invalid recovery record") }
            expectedLength = length; expectedHash = hash; data.append(part)
            if reply["eof"] as? Bool == true {
                guard data.count == length, RecordIntegrity.hash(data) == hash,
                      let text = String(data: data, encoding: .utf8), text.hasSuffix("\n") else { throw LinkError("Incomplete recovery record") }
                return text
            }
        } while data.count < 4096
        throw LinkError("Recovery record too large")
    }

    func listFiles() async throws -> [(name: String, size: Int, modified: Date)] {
        var out: [(String, Int, Date)] = []
        for index in 0..<10_000 {
            try Task.checkCancellation()
            let r = try await command("files", ["index": index])
            if r["eof"] as? Bool == true { break }
            if let name = r["name"] as? String {
                out.append((name, r["size"] as? Int ?? 0, Date(timeIntervalSince1970: r["modified"] as? Double ?? 0)))
            }
        }
        return out.sorted { $0.2 > $1.2 }.map { (name: $0.0, size: $0.1, modified: $0.2) }
    }
}

struct LinkError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}
