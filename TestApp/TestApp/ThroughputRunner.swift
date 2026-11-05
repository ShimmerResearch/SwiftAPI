//
//  ThroughputRunner.swift
//  TestApp
//
//  Not yet run against a Shimmer. See docs/THROUGHPUT_AUTOMATION.md.
//
//  Runs the BLE-Throughput wiki matrix against one or more Shimmer3 / Shimmer3R, found by name, one
//  device after another: scan, connect, record versions, then for each config set CRC -> rate ->
//  sensors, stream, count, stop. Writes the wiki table as CSV for tools/throughput/update_wiki.py.
//
import Foundation
import CoreBluetooth
import ShimmerBluetooth

struct ThroughputConfig {
    let label: String            // "LN Accel, GSR, PPG"
    let sensorBitmap: UInt32     // for sendSetSensorsCommand
    let payloadBytes: Int        // sensor bytes excluding start byte, timestamp and CRC (the check)
    let rateHz: Double
    let crc: Shimmer3Protocol.BTCRCMode
    let seconds: Int
    let repeats: Int
}

struct ThroughputRow {
    var device = "", fw = "", hw = "", radio = "", expBoard = "", ios = "", app = "", phone = ""
    var config = "", crc = 0, rateHz = 0.0, seconds = 0, run = 0
    var attempts = 0             // 1 if the first try was ok; up to 1 + maxRetries
    var packetBytes = 0, expectedPacketBytes = 0
    var received = 0, expected = 0
    var prrApi = 0.0             // the API's own trial PRR, clamped to 100
    var prrRaw = 0.0             // received / expected, NOT clamped, so >100% is visible
    var wallSeconds = 0.0
    var status = "ok"            // ok | connect-failed | config-failed | size-mismatch | stalled | disconnected | device-stopped | stop-timeout | stop-failed
}

/// Whichever of an operation and its timer finishes first resumes; the other does nothing.
@MainActor
private final class TimeoutOnce { var done = false }

@MainActor
final class ThroughputRunner: NSObject, ShimmerProtocolDelegate, BluetoothManagerDelegate {
    private let central = CBCentralManager()
    private lazy var manager = BluetoothManager(centralmanager: central)
    private var radio: BleByteRadio?
    private var proto: Shimmer3Protocol?
    private var scanContinuation: CheckedContinuation<Void, Never>?
    /// False once the link drops or a command goes unanswered; the next run reconnects first.
    /// Shimmer3Protocol has no command timeout, so a reply that never comes leaves its pending
    /// command suspended and refuses every later one on that instance.
    private var linkUp = false
    private var deviceStreaming = false   // false once the device reports it left STREAMING
    /// Called with a one-line status as the run moves on (device, config, run number).
    var onProgress: ((String) -> Void)?
    /// A run that is not ok is tried again up to this many times; only the last try is recorded.
    var maxRetries = 3

    // MARK: matrix (mirrors wiki Test Results 3 and 4)
    static func wikiMatrix() -> [ThroughputConfig] {
        let bitmap = Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_LN_ACCEL.rawValue
            | Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_GSR.rawValue
            | Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_INT_A1.rawValue   // PPG (A13) - VERIFY bit
        // 6 accel + 2 GSR + 2 PPG = 10 payload bytes (the wiki's 15 / 16 bytes = 1 start + 3 ts + 10 + CRC)
        return [Shimmer3Protocol.BTCRCMode.ONE_BYTE, Shimmer3Protocol.BTCRCMode.TWO_BYTE].map {
            ThroughputConfig(label: "LN Accel, GSR, PPG", sensorBitmap: bitmap, payloadBytes: 10,
                             rateHz: 128, crc: $0, seconds: 60, repeats: 3)
        }
    }

    // MARK: scan for every Shimmer in range
    /// Names of the Shimmers advertising within `seconds`, sorted. Empty if Bluetooth is off.
    func scanShimmers(seconds: Double = 8) async -> [String] {
        manager.delegate = self
        guard manager.startScanning(timeout: seconds) else { return [] }
        await withCheckedContinuation { scanContinuation = $0 }    // resumed by scanCompleted()
        let names = manager.getDiscoveredPeripherals().compactMap { $0.name }.filter { $0.hasPrefix("Shimmer") }
        return Array(Set(names)).sorted()
    }

    // MARK: connect by name
    func connect(deviceName: String, scanSeconds: Double = 15) async -> Bool {
        manager.delegate = self
        guard manager.startScanning(deviceName: deviceName, timeout: scanSeconds) else { return false }
        await withCheckedContinuation { scanContinuation = $0 }    // resumed by scanCompleted()
        guard let peripheral = manager.getPeripheral(deviceName: deviceName) else { return false }
        let radio = BleByteRadio(deviceName: deviceName, cbperipheral: peripheral, bluetoothManager: manager)
        let proto = Shimmer3Protocol(radio: radio)
        proto.delegate = self
        self.radio = radio; self.proto = proto
        linkUp = await withTimeout(45) { await proto.connect() } ?? false
        return linkUp
    }
    func disconnect() async {
        if linkUp, let p = proto { _ = await withTimeout(10) { await p.disconnect() } }
        else { _ = await radio?.disconnect() }   // drop the link without waiting for any reply
        linkUp = false
    }

    /// `op`'s result, or nil if it has not finished within `seconds`. Swift cannot cancel a
    /// suspended continuation, so on timeout `op` is left suspended and the link is marked down.
    private func withTimeout<T>(_ seconds: Double, _ op: @escaping @MainActor () async -> T) async -> T? {
        let once = TimeoutOnce()
        let result: T? = await withCheckedContinuation { c in
            Task { @MainActor in
                let v = await op()
                if !once.done { once.done = true; c.resume(returning: v) }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if !once.done { once.done = true; c.resume(returning: nil) }
            }
        }
        if result == nil { linkUp = false }
        return result
    }

    // MARK: run
    /// Runs the matrix on each device in turn. A device that fails to connect gives one
    /// connect-failed row and the run moves on to the next.
    func run(deviceNames: [String], matrix: [ThroughputConfig], appVersion: String, ios: String, phone: String) async -> [ThroughputRow] {
        var rows: [ThroughputRow] = []
        for name in deviceNames {
            rows += await run(deviceName: name, matrix: matrix, appVersion: appVersion, ios: ios, phone: phone)
        }
        return rows
    }

    func run(deviceName: String, matrix: [ThroughputConfig], appVersion: String, ios: String, phone: String) async -> [ThroughputRow] {
        var rows: [ThroughputRow] = []
        var base = ThroughputRow(); base.device = deviceName; base.ios = ios; base.app = appVersion; base.phone = phone
        var connected = false
        onProgress?("\(deviceName): connecting")
        for attempt in 0..<2 where !connected {   // one retry
            if attempt > 0 {
                await disconnect()   // drop the first attempt, or the retry finds the peripheral half-connected
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
            connected = await connect(deviceName: deviceName)
        }
        guard connected, var p = proto else {
            onProgress?("\(deviceName): connect failed")
            base.status = "connect-failed"; return [base]
        }
        base.fw = "\(p.REV_FW_MAJOR).\(p.REV_FW_MINOR).\(p.REV_FW_INTERNAL)"
        base.hw = p.REV_HW_MAJOR == Shimmer3Protocol.HardwareType.Shimmer3R.rawValue ? "Shimmer3R" : "Shimmer3"
        base.expBoard = "SR\(p.EXPANSION_BOARD_ID)-\(p.EXPANSION_BOARD_REV).\(p.EXPANSION_BOARD_REV_SPECIAL)"
        if await withTimeout(10, { await p.sendReadBtFwVersionCommand() == true }) == true {
            base.radio = ShimmerUtilities.btModuleDisplayName(p.btModuleVersion)
        }
        onProgress?("\(deviceName): \(base.hw) FW \(base.fw), radio \(base.radio.isEmpty ? "not read" : base.radio)")

        for cfg in matrix {
            for run in 1...cfg.repeats {
                var template = base
                template.config = cfg.label; template.crc = Int(cfg.crc.rawValue); template.rateHz = cfg.rateHz
                template.seconds = cfg.seconds; template.run = run
                var r = template
                for attempt in 1...(1 + maxRetries) {
                    r = template
                    r.attempts = attempt
                    let tryLabel = attempt == 1 ? "" : " (retry \(attempt - 1)/\(maxRetries))"
                    if !linkUp {
                        onProgress?("\(deviceName): link lost, reconnecting")
                        await disconnect()
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        guard await connect(deviceName: deviceName), let p2 = proto else {
                            onProgress?("\(deviceName): reconnect failed\(tryLabel)")
                            r.status = "connect-failed"
                            continue
                        }
                        p = p2
                    }
                    onProgress?("\(deviceName): \(cfg.crc.rawValue)-byte CRC, run \(run)/\(cfg.repeats), \(cfg.seconds) s\(tryLabel)")
                    r = await runOne(p, cfg, r)
                    onProgress?("\(deviceName): \(r.status), PRR \(String(format: "%.1f", r.prrApi))%")
                    if r.status == "ok" { break }
                }
                rows.append(r)   // the ok try, or the last failure if every try failed
                if r.status == "connect-failed" {
                    onProgress?("\(deviceName): unreachable, skipping the rest of this device")
                    await disconnect()
                    return rows
                }
            }
        }
        await disconnect()
        return rows
    }

    private func runOne(_ p: Shimmer3Protocol, _ cfg: ThroughputConfig, _ rowIn: ThroughputRow) async -> ThroughputRow {
        var r = rowIn
        // Order matters: PacketSize is fixed at inquiry and includes the CRC, so the CRC goes first
        // and the sensor command (which re-runs inquiry) goes last.
        guard await withTimeout(15, { await p.setCRCMode(cfg.crc) }) == true,
              await withTimeout(15, { await p.sendSetSamplingRateCommand(samplingRate: cfg.rateHz) == true }) == true,
              await withTimeout(15, { await p.sendSetSensorsCommand(sensorBitmap: cfg.sensorBitmap) }) == true else {
            r.status = linkUp ? "config-failed" : "disconnected"; return r
        }
        // Accuracy gate: the packet on the wire must be the size the config implies.
        r.expectedPacketBytes = 1 + p.TimeStampPacketByteSize + cfg.payloadBytes + Int(cfg.crc.rawValue)
        r.packetBytes = p.packetSizeBytes
        guard r.packetBytes == r.expectedPacketBytes, p.getCRCMode() == cfg.crc,
              p.currentSamplingRate == cfg.rateHz else {
            r.status = "size-mismatch"; return r      // wrong sensors enabled: do not report a PRR
        }

        let t0 = Date()
        guard await withTimeout(15, { await p.sendStartStreamingCommand() == true }) == true else {
            r.status = linkUp ? "config-failed" : "disconnected"; return r
        }
        deviceStreaming = true
        // One-second steps so a dropped link, or the device ending the stream, ends the run now.
        while linkUp && deviceStreaming && Date().timeIntervalSince(t0) < Double(cfg.seconds) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        r.wallSeconds = Date().timeIntervalSince(t0)
        r.received = p.numberOfPackets
        r.prrApi = p.packetReceptionRateOverall
        if !linkUp {
            r.status = "disconnected"   // counts so far are kept, but the row is not a result
        } else if !deviceStreaming {
            r.status = "device-stopped" // docked, button, low battery: a partial run, not a result
        } else {
            switch await withTimeout(10, { await p.sendStopStreamingCommand() }) {
            case nil:  r.status = "stop-timeout"   // the stream ran its full time, but the stop was never ACKed
            case .some(.some(true)): break
            default:                               // refused: the device may still be streaming
                r.status = "stop-failed"; linkUp = false   // reconnect before the next run
            }
        }

        // Same expectation the API uses (device timestamps), but kept unclamped.
        r.expected = Int(Double(cfg.seconds) * cfg.rateHz)
        r.prrRaw = r.expected > 0 ? Double(r.received) / Double(r.expected) * 100 : 0
        if r.received == 0 && r.status == "ok" { r.status = "stalled" }
        try? await Task.sleep(nanoseconds: 2_000_000_000)   // settle between runs
        return r
    }

    // MARK: output
    /// The wiki's BLE-Throughput columns, in its order. One row per device and setting.
    static let wikiColumns = ["Equipment", "Shimmer Device", "FW Version", "Radio Type", "Sensors Enabled",
                              "CRC Bytes", "Number of Bytes", "Sampling Rate", "Streaming Duration",
                              "Packet Reception Rate", "OS Version", "Distance between devices (approximate)"]

    /// The wiki table as CSV. Each setting's runs become one row: Packet Reception Rate is the
    /// median of the runs' API PRR when every run ended ok, otherwise "incomplete (n/m ok)" or the
    /// failure, so a setting that did not finish can never pass for a result.
    static func csv(_ rows: [ThroughputRow], distance: String) -> String {
        var order: [String] = []
        var groups: [String: [ThroughputRow]] = [:]
        for r in rows {
            let key = "\(r.device)|\(r.config)|\(r.crc)|\(r.rateHz)|\(r.seconds)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(r)
        }
        let lines = order.map { key -> String in
            let g = groups[key]!, first = g[0]
            let ok = g.filter { $0.status == "ok" }
            let prr: String
            if first.status == "connect-failed" && g.count == 1 && first.config.isEmpty {
                prr = "connect failed"
            } else if ok.count == g.count {
                let v = ok.map(\.prrApi).sorted()
                let median = v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
                prr = "\(Int(median.rounded()))%"
            } else {
                let reasons = Set(g.map(\.status)).subtracting(["ok"]).sorted().joined(separator: ", ")
                prr = "incomplete (\(ok.count)/\(g.count) ok: \(reasons))"
            }
            let bytes = (ok.first ?? first).packetBytes
            let cells = [
                first.phone,
                first.hw.isEmpty ? first.device : first.hw,
                fwCell(hw: first.hw, fw: first.fw),
                first.radio,
                first.config,
                first.crc == 0 ? "" : "\(first.crc) byte\(first.crc == 1 ? "" : "s")",
                bytes == 0 ? "" : "\(bytes) bytes",
                first.rateHz == 0 ? "" : "\(Int(first.rateHz)) Hz",
                first.seconds == 0 ? "" : "\(first.seconds) s",
                prr,
                first.ios,
                distance,
            ]
            return cells.map(quote).joined(separator: ",")
        }
        return ([wikiColumns.map(quote).joined(separator: ",")] + lines).joined(separator: "\n")
    }

    /// "1.1.9" on a Shimmer3 -> "L&S Shimmer3 v1.01.009", as the wiki writes it.
    private static func fwCell(hw: String, fw: String) -> String {
        let n = fw.split(separator: ".").compactMap { Int($0) }
        guard n.count == 3 else { return fw }
        return "L&S \(hw) v\(n[0]).\(String(format: "%02d", n[1])).\(String(format: "%03d", n[2]))"
    }

    private static func quote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

    // MARK: delegates
    // nonisolated: Shimmer3Protocol calls these from its background processing queue, not the
    // main thread, so they must not touch main-actor state directly.
    nonisolated func scanCompleted() {
        Task { @MainActor in self.scanContinuation?.resume(); self.scanContinuation = nil }
    }
    nonisolated func isConnected() {}
    nonisolated func isDisconnected() {}
    nonisolated func shimmerProtocolNewMessage(message: String) {}
    nonisolated func shimmerProtocolNewObjectCluster(message: ObjectCluster) {}
    nonisolated func shimmerBTStateChange(message: Shimmer3Protocol.Shimmer3BTState) {
        Task { @MainActor in
            if message == .DISCONNECTED { self.linkUp = false }
            if message != .STREAMING { self.deviceStreaming = false }   // e.g. a status push ended the stream
        }
    }
}
