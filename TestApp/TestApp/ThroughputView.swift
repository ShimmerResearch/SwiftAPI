//
//  ThroughputView.swift
//  TestApp
//
//  Scan for Shimmers, tick the ones to test, run the BLE-Throughput matrix on each in turn, and
//  save one CSV to the app's Documents folder (visible in Finder and the Files app).
//
import SwiftUI
#if os(iOS)
import UIKit
#endif

@MainActor
struct ThroughputView: View {
    @State private var runner = ThroughputRunner()
    @State private var found: [String] = []
    @State private var selected: Set<String> = []
    @State private var scanning = false
    @State private var running = false
    @State private var quick = true
    @State private var distance = "2.5 m"
    @State private var log: [String] = []
    @State private var status = ""
    @State private var statusSince = Date()
    @State private var csvURL: URL?

    var body: some View {
        NavigationView {
            List {
                if running {
                    Section {
                        // Ticks every second so a 60 s run visibly moves.
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(status).font(.headline)
                                Text("\(Int(context.date.timeIntervalSince(statusSince))) s").monospacedDigit()
                            }
                        }
                    } header: { Text("Now") }
                }
                Section {
                    Button(scanning ? "Scanning..." : "Scan for Shimmers") { Task { await scan() } }
                        .disabled(scanning || running)
                    ForEach(found, id: \.self) { name in
                        Button {
                            if selected.contains(name) { selected.remove(name) } else { selected.insert(name) }
                        } label: {
                            HStack {
                                Text(name)
                                Spacer()
                                if selected.contains(name) { Image(systemName: "checkmark") }
                            }
                        }
                        .disabled(running)
                    }
                } header: { Text("Devices") }

                Section {
                    Toggle("Quick check (10 s, 1 run)", isOn: $quick).disabled(running)
                    HStack {
                        Text("Distance")
                        TextField("2.5 m", text: $distance).multilineTextAlignment(.trailing).disabled(running)
                    }
                    Button(running ? "Running..." : "Run on \(selected.count) device(s)") { Task { await run() } }
                        .disabled(selected.isEmpty || running || scanning)
                    if let csvURL {
                        Text(csvURL.lastPathComponent).font(.footnote)
                        if #available(iOS 16.0, macOS 13.0, *) {
                            ShareLink(item: csvURL) { Label("Share CSV", systemImage: "square.and.arrow.up") }
                        }
                    }
                } header: { Text("Run") } footer: {
                    Text(quick ? "Quick check: a smoke test, not wiki results."
                               : "Full: 1 run x 60 s per CRC mode, retried if it fails, about 3 min per device.")
                }

                Section { ForEach(Array(log.enumerated().reversed()), id: \.offset) { Text($0.element).font(.footnote) } }
                    header: { Text("Log (newest first)") }
            }
            .navigationTitle("Throughput")
        }
        // Swiping the sheet away mid-run would leave the run going unseen, the phone kept awake,
        // and a second Run able to start against the same devices.
        .interactiveDismissDisabled(running)
    }

    private func scan() async {
        scanning = true
        found = await runner.scanShimmers()
        selected = selected.intersection(found)
        log.append(found.isEmpty ? "No Shimmers found. Is Bluetooth on and the device powered?"
                                 : "Found \(found.count): \(found.joined(separator: ", "))")
        scanning = false
    }

    private func run() async {
        running = true
        csvURL = nil
        setIdleTimerDisabled(true)   // a locked phone stops the run
        runner.onProgress = { line in
            log.append("\(Self.clock.string(from: Date()))  \(line)")
            status = line
            statusSince = Date()
        }

        var matrix = ThroughputRunner.wikiMatrix()
        if quick {
            matrix = matrix.map {
                ThroughputConfig(label: $0.label, sensorBitmap: $0.sensorBitmap, payloadBytes: $0.payloadBytes,
                                 rateHz: $0.rateHz, crc: $0.crc, seconds: 10, repeats: 1)
            }
        }
        let app = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let rows = await runner.run(deviceNames: selected.sorted(), matrix: matrix,
                                    appVersion: app, ios: osVersion(), phone: Self.phoneModel())
        csvURL = save(ThroughputRunner.csv(rows, distance: distance))
        log.append(csvURL.map { "Saved \($0.lastPathComponent)" } ?? "Could not save the CSV")

        setIdleTimerDisabled(false)
        running = false
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func save(_ csv: String) -> URL? {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd_HHmmss"
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = docs.appendingPathComponent("throughput_\(stamp.string(from: Date()))\(quick ? "_quick" : "").csv")
        return (try? csv.write(to: url, atomically: true, encoding: .utf8)) == nil ? nil : url
    }

    /// As the wiki writes it, e.g. "iOS 16.7.1".
    private func osVersion() -> String {
        #if os(iOS)
        return "iOS \(UIDevice.current.systemVersion)"
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }

    /// The wiki's Equipment cell, e.g. "iPhone X". A model not in the table below is written as its
    /// raw identifier (e.g. "iPhone18,3"), which is still exact: add it to the table when seen.
    static func phoneModel() -> String {
        let id = modelIdentifier()
        return phoneNames[id] ?? id
    }

    private static func modelIdentifier() -> String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim }
        #if os(iOS)
        var sys = utsname()
        uname(&sys)
        return withUnsafeBytes(of: &sys.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        #else
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)   // e.g. "Mac14,3"
        #endif
    }

    private static let phoneNames: [String: String] = [
        "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8", "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
        "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X",
        "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd gen)",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3rd gen)", "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,5": "iPhone 16e",
    ]

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}
