# SwiftAPI

The Swift host API — the fifth native implementation of the Shimmer3 wire format, alongside Java, C#,
Python and TypeScript. Packet parsing is one class per sensor in
`ShimmerBluetooth/ShimmerBluetooth/*Sensor.swift`, dispatched from `Shimmer3Protocol.swift`, with the
configuration byte map in `ConfigByteLayoutShimmer3.swift`.

This is the live Swift repo. Two others in the org — `Shimmer-Swift-API` and `ShimmerSwiftAPI` — are
private and stale (last pushed 2024-05 and 2023-10). Check `pushedAt` before believing a search hit.

## CI is the only way to compile this

Most of the team is on Windows, where there is no Swift toolchain and no Xcode, so nothing here can
be built or run locally. `.github/workflows/swift.yml` runs `xcodebuild test -scheme
ShimmerBluetoothTests` on `macos-latest`, for pushes to `main` and PRs into it.

**A PR's first CI run is the first time the code is executed.** Say so rather than implying a change
has been tested.

The loop is cheap — roughly two minutes queue-to-result — and it genuinely runs XCTest rather than
only compiling. The step is named "Build", which is misleading. To confirm the tests actually ran:

```
gh run view <id> --log
```

and look for `** TEST SUCCEEDED **` and per-case `passed` lines. A green check alone does not prove
execution.

## Adding a file needs four hand-written pbxproj entries

`project.pbxproj` is `objectVersion = 56` — classic groups, not synchronized folders — so Xcode's
automatic file membership does not apply. Every new source file needs all four of:

1. `PBXBuildFile`
2. `PBXFileReference`
3. the `PBXGroup` child entry
4. the target's `PBXSourcesBuildPhase` entry

Mirror an existing file's four. Miss one and the file either does not compile or is silently excluded
from the target, which CI reports as an unrelated symbol error.

## The protocol class cannot be unit tested

`Shimmer3Protocol.init` takes a concrete `BleByteRadio`, which needs a live `CBPeripheral`. No unit
test can construct it, and none does — `ShimmerBluetoothTests` covers the sensor classes and
utilities instead.

Anything you wire *inside* `Shimmer3Protocol` is therefore untestable until that initialiser accepts
a `ByteCommunication` abstraction. Prefer putting logic in a sensor class or a utility that tests can
reach, and be explicit in the PR about what CI did and did not exercise.

## Sibling implementations

A parsing, protocol, calibration or timestamp fix here almost always applies to the Java, C#, Python
and TypeScript APIs, and to `ASM_BaseStation`'s separate 2025E parser. Nothing links them and nothing
tests them together — the DEV-1023 timestamp-unwrap defect was the same rule, wrong the same way, in
four of them. Check the others and say which need it, including "none", so the check is visible.
