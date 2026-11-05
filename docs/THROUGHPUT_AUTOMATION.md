# BLE throughput test automation

Fills the wiki's [BLE-Throughput](https://github.com/ShimmerResearch/SwiftAPI/wiki/BLE-Throughput)
page from a run of TestApp on an iPhone. Status: run on an iPhone X (iOS 16.7.16) against a
Shimmer3 (L&S v1.01.009, RN4678) and a Shimmer3R (L&S v1.01.025, IF820), 2026-11-04 and -05.

## Steps
1. **Build:** open `Shimmer.xcworkspace`, pick the **TestApp** scheme and the iPhone, set a team
   under Signing & Capabilities (do not commit it), and press Run (Cmd+R). Tap Allow on the
   Bluetooth prompt, once per install.
2. **Devices:** flash the firmware under test, power the boards on, and put them about 2.5 m from the
   phone.
3. **Run:** in TestApp tap **Throughput Test**, **Scan for Shimmers**, tick the devices, turn
   **Quick check** off, set **Distance** if it is not 2.5 m, and tap **Run** (about 3 min per
   device). Keep the app open; the phone stays awake by itself.
4. **CSV:** tap **Share CSV** and AirDrop it to the Mac (it lands in `~/Downloads`). Every PRR cell
   should be a percentage; a cell saying `failed after n tries` means that setting never passed, so
   re-run that device before publishing.
5. **Publish:** from the repo root,
   ```
   python3 tools/throughput/update_wiki.py ~/Downloads/throughput_<date>_<time>.csv --push
   ```
   Check the printed API release and table, then answer `y`. Details under *Wiki update* below.

## Automated
- Scan lists every advertising device whose name starts with `Shimmer`; connect by BLE name
  (`BluetoothManager.startScanning(deviceName:)`), one retry.
- Record FW, hardware, Bluetooth radio (`0xA1` -> e.g. `RN4678 v1.23`, `IF820 v01.04.16.16`),
  expansion board and iOS version, and the phone model, from the devices, not from typing.
- For each config (one run, retried if it fails): set CRC, then rate, then sensors, stream, count, stop.
- Write the wiki table itself as CSV: the wiki's 12 columns, one row per device and CRC setting.
  Packet Reception Rate is the API PRR of the ok run, otherwise `failed after n tries: reasons`.
  Per-run detail (received counts, raw PRR, retries) is only in the app's log, not the CSV.
- `tools/throughput/update_wiki.py` copies the publishable rows into new wiki tables.

## Accuracy rules
- **Order is CRC, rate, sensors.** `PacketSize` includes the CRC and is fixed at inquiry, and
  `sendSetSensorsCommand` re-runs inquiry. Setting CRC last would leave a stale size.
- **Packet-size gate.** Wire size must equal `1 + 3 + payload + CRC` (15 / 16 bytes for LN Accel +
  GSR + PPG, as on the wiki). A mismatch means the wrong sensors are on, and the run is rejected, not
  reported.
- **One ok run per config.** Each setting is run once for 60 s; a failed run is retried (below) and
  only the ok run is reported. The runner still supports `repeats` > 1, in which case the PRR is the
  median and every run must be ok.
- **Retries.** A run that is not `ok` is tried again up to 3 times (`maxRetries`), reconnecting
  first if the link dropped, or the device stopped streaming by itself, or a stop was refused. Only
  the ok try counts; if every try failed, the setting's PRR cell says `failed after n tries`, never a
  number.

## Required API change (in this branch)
`Shimmer3Protocol` keeps `CurrentSamplingRate` and `PacketSize` internal, and `connect()` always
picks the strongest safe CRC. The wiki rows need 1-byte and 2-byte CRC, which the runner sets with
the existing `setCRCMode` / `getCRCMode`. Added: `currentSamplingRate`, `packetSizeBytes`, and
`numberOfPackets` is now `public private(set)`.

Note: Shimmer3R v1.01.025 is above v1.00.050, so 2-byte is its strongest safe CRC and 1-byte is
allowed. Shimmer3 always allows 2-byte.

## Known issues
- Shimmer3R with 1-byte CRC has dropped the link mid-run on some runs (2026-11-04, and on every retry
  of one run on 2026-11-05 with v1.1.0). Cause not found yet.
- `Shimmer3Protocol` has no command timeout of its own; the runner wraps each command in one and
  reconnects when one expires.

Checked: `SENSOR_INT_A1` (0x0100) enables channel `InternalAdc1` (0x12), which is internal ADC A13,
the wiki's PPG channel. 6 accel + 2 GSR + 2 PPG = 10 payload bytes.

## Run
**Quick check** (on by default) does 10 s x 1 run per CRC mode as a smoke test; its rows are never
published. Turn it off for wiki results: 1 x 60 s per CRC mode, retried if it fails, about 3 min per
device.

The CSV is saved as `throughput_<date>_<time>.csv` (`_quick` for a quick check) in the app's
Documents folder. Get it with **Share CSV** (AirDrop to the Mac), or Finder > iPhone > Files >
TestApp.

## Wiki update (`tools/throughput/update_wiki.py`)
Python 3, stdlib only, runs on the Mac. One table per API release, numbered after the last one on
the page and placed above `# Notes`: `# Test Results N ... (Shimmer3, Shimmer3R)`. The wiki table has
the CSV's columns plus **API Release** after Equipment, filled from `--release`, since the app does
not know which release it was built from. A later run for the same release
(another phone, another firmware) adds its rows to that table, grouped by device; a re-run of the same
setting on the same phone and firmware replaces that row in place, so a setting never shows two
results. A new release starts the next number. Other tables are never touched.

```
python3 tools/throughput/update_wiki.py ~/Downloads/throughput_<date>_<time>.csv           # dry run
python3 tools/throughput/update_wiki.py ~/Downloads/throughput_<date>_<time>.csv --push    # publish
```
- `--push` clones the live wiki fresh, prints the change, asks `Publish this to the GitHub wiki? [y/N]`,
  then commits and pushes with plain `git push`. Anything but `y` publishes nothing. Run it in
  Terminal: where nothing can be typed (e.g. `!` in Claude Code) it cancels, and `--push --yes`
  skips the question once the printed change has been checked.
- Pushing needs command-line git to have a GitHub credential (GitHub Desktop's sign-in is not shared
  with it). One-time setup: create a classic personal access token with the `public_repo` scope
  (GitHub > Settings > Developer settings > Personal access tokens > Tokens (classic)). At the first
  push, in Terminal, git asks for a username (your GitHub username) and a password (paste the
  token); the macOS keychain (`credential.helper osxkeychain`) remembers it for later pushes.
- The API release defaults to the latest `ShimmerSwiftAPI_v*` tag on GitHub (printed);
  `--release ShimmerSwiftAPI_vX.Y.Z` names another.
- Every cell comes from the app. Equipment is the phone model from the iOS model identifier
  (e.g. `iPhone10,3` -> "iPhone X"), Radio Type is read from the device (`0xA1`), and Distance is the
  app's Distance field (default 2.5 m).
- Rows are skipped with a warning when PRR is not a percentage (incomplete, connect failed), the
  duration is not 60 s (a quick check), or the phone is a raw identifier missing from the app's table.
- CSVs from before this format (per-run columns) are refused.
- Without `--push` it is a dry run. `--commit --wiki <clone>` commits in a clone without pushing.
- Checked on the Mac against the live wiki with the 2026-11-05 results: a new release becomes the next
  table, a re-run adds rows to its release's table, republishing changes nothing, incomplete and
  quick-check rows are skipped, and answering `n` at the prompt publishes nothing. An actual push
  has not been run yet.
