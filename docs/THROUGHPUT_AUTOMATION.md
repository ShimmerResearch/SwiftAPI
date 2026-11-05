# BLE throughput test automation (draft)

Goal: fill the wiki's BLE-Throughput tables for a new Shimmer3 / Shimmer3R firmware with one command
and almost no human steps. Status: TestApp builds with the runner (checked locally on a Mac with Xcode 26.6). **Not yet run
against a Shimmer.**

## Human steps (all that remain)
1. Flash the firmware under test (Shimmer3 v1.01.009, Shimmer3R v1.01.025) and power the board on.
2. Plug in and unlock the iPhone; put the board about 2.5 m away. Tap Allow on the first-launch
   Bluetooth prompt, once per install.
3. In TestApp tap **Throughput Test**, then **Scan for Shimmers**, tick one or more devices, and tap
   **Run**. Devices are tested one after another into one CSV.
4. Run `tools/throughput/update_wiki.py` (below), read the diff, then push the wiki yourself.

## Automated
- Scan lists every advertising device whose name starts with `Shimmer`; connect by BLE name
  (`BluetoothManager.startScanning(deviceName:)`), one retry.
- Record FW, hardware, Bluetooth radio (`0xA1` -> e.g. `RN4678 v1.23`, `IF820 v01.04.16.16`),
  expansion board, iOS and app version from the device, not from typing.
- For each config and each of N repeats: set CRC, then rate, then sensors, stream, count, stop.
- Write the wiki table itself as CSV: the wiki's 12 columns, one row per device and CRC setting.
  Packet Reception Rate is the median of the runs' API PRR when every run ended ok, otherwise
  `incomplete (n/m ok: reasons)`. Per-run detail (received counts, raw PRR, retries) is only in the
  app's log, not the CSV.
- `tools/throughput/update_wiki.py` copies the publishable rows into new wiki tables.

## Accuracy rules
- **Order is CRC, rate, sensors.** `PacketSize` includes the CRC and is fixed at inquiry, and
  `sendSetSensorsCommand` re-runs inquiry. Setting CRC last would leave a stale size.
- **Packet-size gate.** Wire size must equal `1 + 3 + payload + CRC` (15 / 16 bytes for LN Accel +
  GSR + PPG, as on the wiki). A mismatch means the wrong sensors are on, and the run is rejected, not
  reported.
- **Repeats and median.** 3 runs per config. The wiki notes a +/-8% tolerance at high throughput; one
  run is not a result.
- **Retries.** A run that is not `ok` is tried again up to 3 times (`maxRetries`), reconnecting
  first if the link dropped. Only the last try counts; if every try failed, the setting's PRR cell
  says `incomplete`, never a number.
- **Wall time recorded** next to the nominal duration.

## Required API change (in this branch)
`Shimmer3Protocol` keeps `CurrentSamplingRate` and `PacketSize` internal, and `connect()` always
picks the strongest safe CRC. The wiki rows need 1-byte and 2-byte CRC, which the runner sets with
the existing `setCRCMode` / `getCRCMode`. Added: `currentSamplingRate`, `packetSizeBytes`, and
`numberOfPackets` is now `public private(set)`.

Note: Shimmer3R v1.01.025 is above v1.00.050, so 2-byte is its strongest safe CRC and 1-byte is
allowed. Shimmer3 always allows 2-byte.

## To finish
- Check that a CRC change after connect survives `sendSetSensorsCommand`'s inquiry on both boards
  (a run with the wrong CRC is caught by the packet-size gate and written as `size-mismatch`).
- A connect that fails at the CoreBluetooth level never resumes `BluetoothManager.connect`, so the
  run hangs rather than writing `connect-failed`. Kill the app and untick that device.

Checked: `SENSOR_INT_A1` (0x0100) enables channel `InternalAdc1` (0x12), which is internal ADC A13,
the wiki's PPG channel. 6 accel + 2 GSR + 2 PPG = 10 payload bytes.

## Run
Open `Shimmer.xcworkspace`, select the **TestApp** scheme and the iPhone, set a team under Signing &
Capabilities, and Run. **Quick check** (on by default) does 10 s x 1 run per CRC mode as a smoke test;
turn it off for the wiki matrix (3 x 60 s per CRC mode, about 7 min per device). The phone is kept
awake during a run.

The CSV is saved as `throughput_<date>_<time>.csv` in the app's Documents folder. Get it with **Share
CSV** (AirDrop to the Mac), or Finder > iPhone > Files > TestApp.

## Wiki update (`tools/throughput/update_wiki.py`)
Python 3, stdlib only, runs on the Mac. Adds one table per hardware per release, above `# Notes`:
`# Test Results N ... (Shimmer3, ShimmerSwiftAPI_vX.Y.Z)`. Old tables are never touched. A hidden
marker comment per table makes a re-run replace that table instead of duplicating it.

```
python tools/throughput/update_wiki.py --csv results.csv --release ShimmerSwiftAPI_v1.1.0
```
- Every cell comes from the app. Equipment is the phone model from the iOS model identifier
  (e.g. `iPhone10,3` -> "iPhone X"), Radio Type is read from the device (`0xA1`), and Distance is the
  app's Distance field (default 2.5 m).
- Rows are skipped with a warning when PRR is not a percentage (incomplete, connect failed), the
  duration is not 60 s (a quick check), or the phone is a raw identifier missing from the app's table.
- CSVs from before this format (per-run columns) are refused.
- Dry run by default: prints the diff, changes nothing. `--commit` commits in the local wiki clone.
  **It never pushes.** Review the diff, then `git -C <wiki> push` yourself.
- `--wiki <clone>` uses an existing clone (must be clean); otherwise it clones to a temp folder.
- Checked on the Mac against the live wiki with the 2026-11-05 results converted to this format:
  no change to tables 5 and 6; incomplete and quick-check rows skipped.
