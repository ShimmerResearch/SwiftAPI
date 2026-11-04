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
                               : "Full: 3 runs x 60 s per CRC mode, about 7 min per device.")
                }

                Section { ForEach(Array(log.enumerated().reversed()), id: \.offset) { Text($0.element).font(.footnote) } }
                    header: { Text("Log (newest first)") }
            }
            .navigationTitle("Throughput")
        }
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
                                    appVersion: app, ios: osVersion())
        csvURL = save(ThroughputRunner.csv(rows))
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

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}
