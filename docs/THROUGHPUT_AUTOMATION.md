# BLE throughput test automation (draft)

Goal: fill the wiki's BLE-Throughput tables for a new Shimmer3 / Shimmer3R firmware with one command
and almost no human steps. Status: **draft, never compiled or run.** This repo only compiles in CI
(`AGENTS.md`), and `ThroughputRunner.swift` is not yet in `project.pbxproj`.

## Human steps (all that remain)
1. Flash the firmware under test (Shimmer3 v1.01.009, Shimmer3R v1.01.025) and power the board on.
2. Plug in and unlock the iPhone; put the board about 2.5 m away. Tap Allow on the first-launch
   Bluetooth prompt, once per install.
3. Run the command below with the device name.
4. Run `tools/throughput/update_wiki.py` (below), read the diff, then push the wiki yourself.

## Automated
- Scan and connect by BLE name (`BluetoothManager.startScanning(deviceName:)`), one retry.
- Record FW, hardware, expansion board, iOS and app version from the device, not from typing.
- For each config and each of N repeats: set CRC, then rate, then sensors, stream, count, stop.
- Write a CSV with every run.
- `tools/throughput/update_wiki.py` turns the CSV into new wiki tables (median of the runs).

## Accuracy rules
- **Order is CRC, rate, sensors.** `PacketSize` includes the CRC and is fixed at inquiry, and
  `sendSetSensorsCommand` re-runs inquiry. Setting CRC last would leave a stale size.
- **Packet-size gate.** Wire size must equal `1 + 3 + payload + CRC` (15 / 16 bytes for LN Accel +
  GSR + PPG, as on the wiki). A mismatch means the wrong sensors are on, and the run is rejected, not
  reported.
- **Unclamped PRR.** The API clamps PRR to 100%. The CSV also keeps received, expected and the raw
  ratio, so over-100% (a timing or rate fault) is visible.
- **Repeats and median.** 3 runs per config. The wiki notes a +/-8% tolerance at high throughput; one
  run is not a result.
- **Failures are rows.** Connect, config and stall failures are written with a status, never dropped.
- **Wall time recorded** next to the nominal duration.

## Required API change (in this branch)
`Shimmer3Protocol` keeps `sendCRCCommand`, `CRCMode`, `CurrentSamplingRate` and `PacketSize` private
or internal, and `connect()` always picks the strongest safe CRC. The wiki rows need 1-byte and
2-byte CRC. Added: `sendSetCRCMode`, `currentCRCMode`, `currentSamplingRate`, `packetSizeBytes`,
and `numberOfPackets` is now `public private(set)`.

Note: Shimmer3R v1.01.025 is above v1.00.050, so 2-byte is its strongest safe CRC and 1-byte is
allowed. Shimmer3 always allows 2-byte.

## To finish
- Add `ThroughputRunner.swift` to the TestApp target (four hand-written pbxproj entries).
- A `ThroughputUITests` XCUITest that reads the device name from `launchEnvironment`, calls the
  runner, and writes the CSV to the test attachments.
- Verify the PPG sensor bit (`SENSOR_INT_A1`) gives the wiki's A13 PPG channel, and the payload
  size of 10 bytes.
- Radio version (RN4678 / IF820) is not read by the API; pass it in as a launch argument.
- Keep the phone awake: set `UIApplication.shared.isIdleTimerDisabled = true` for the run.
- Check that a CRC change after connect survives `sendSetSensorsCommand`'s inquiry on both boards.

## Run
```
xcodebuild test -project TestApp/TestApp.xcodeproj -scheme TestApp \
  -destination 'platform=iOS,name=<iPhone name>' \
  -only-testing:TestAppUITests/ThroughputUITests \
  SHIMMER_DEVICE_NAME=Shimmer3R-XXXX
```

## Wiki update (`tools/throughput/update_wiki.py`)
Python 3, stdlib only, runs on the Mac. Adds one table per hardware per release, above `# Notes`:
`# Test Results N ... (Shimmer3, ShimmerSwiftAPI_vX.Y.Z)`. Old tables are never touched. A hidden
marker comment per table makes a re-run replace that table instead of duplicating it.

```
python tools/throughput/update_wiki.py --csv results.csv --release ShimmerSwiftAPI_v1.1.0   --phone "iPhone 12" --radio Shimmer3="RN4678 v1.23" --radio Shimmer3R="IF820 v01.04.16.16"
```
- Dry run by default: prints the diff, changes nothing. `--commit` commits in the local wiki clone.
  **It never pushes.** Review the diff, then `git -C <wiki> push` yourself.
- Only `ok` runs count. Each config needs `--min-runs` (default 3) ok runs, and the runs must agree on
  firmware and packet size. Anything skipped is listed as a warning.
- `--wiki <clone>` uses an existing clone (must be clean); otherwise it clones to a temp folder.
- Tested on Windows against a copy of the real wiki with a made-up CSV: dry run, commit, no-op re-run
  and in-place replace all behave. It has not seen real runner output yet.
