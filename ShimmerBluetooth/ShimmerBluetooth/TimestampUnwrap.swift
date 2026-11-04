//
//  TimestampUnwrap.swift
//  ShimmerBluetooth
//
//  Created by Shimmer Engineering on 17/09/2026.
//

import Foundation

/// Turning a device's wrapping sample counter into a monotonic clock.
///
/// The counter runs at 32768 Hz in 24 bits, so it returns to zero every 512
/// seconds exactly. Undoing that is a matter of counting the roll-overs, and
/// the obvious rule — "the value went down, so it wrapped" — is wrong three
/// different ways:
///
/// - A **reordered** packet steps backwards without the counter having wrapped.
/// - A **duplicated** packet does the same with a step of zero.
/// - An **unstamped** record carries `0x000000`. Firmware stamps a packet when
///   the sample tick starts it and does not publish a packet it never stamped,
///   so a timestamp field of exactly zero marks an invalid record rather than
///   the counter reaching its origin. LogAndStream v1.00.x–v1.01.003 could
///   produce one under SD write back-pressure.
///
/// Each of those adds a whole modulo — 512 seconds — to every later sample, for
/// the rest of the session. A recording of 9 minutes 30 seconds containing four
/// unstamped records was reported as 43 minutes 38.
///
/// This is one of five implementations of the same rule, and the only one whose
/// correctness is not a matter of opinion: the vectors in
/// `TimestampUnwrapVectorsTest` are generated from a reference implementation in
/// the firmware repository, where the rule is specified, and the Java, C#,
/// Python and TypeScript APIs run the same set. They drifted apart once already
/// — the same defect, in all five, for years — because each was reviewed on its
/// own against prose. Change the rule here and the vectors will say so.
///
/// Mirrors `TimestampUnwrap.cs` and `TimestampUnwrap.java` method for method,
/// with one deliberate difference: both of those keep an overload that infers
/// "no previous sample" from the state being `(0, 0)`, for callers written
/// before that turned out to be ambiguous. This file is new, so it has no such
/// callers and asks outright instead.
public enum TimestampUnwrap {

    /// The 3-byte counter's range. The only width this API's packet parser
    /// reads (`Shimmer3Protocol.TimeStampPacketByteSize`), but the rule is
    /// written against a modulo so that the shared vectors can exercise the
    /// 2-byte counter older firmware used.
    public static let ticksMax3Byte = 1 << 24

    /// How close to the top of the range the previous sample must have been for
    /// a drop to exactly zero to be believed as a roll-over.
    ///
    /// One second. A genuine wrap onto zero means the counter advanced to its
    /// very last tick, so its predecessor is within a sample or two of the
    /// maximum; a second is a generous allowance for a gap in the data, and
    /// orders of magnitude away from the mid-range predecessors the unstamped
    /// records have.
    public static let wrapWindowTicks = 32768

    /// How many sample periods behind its predecessor a value may be and still
    /// be read as a reordered packet.
    ///
    /// A reorder swaps packets that are adjacent in time, so it spans a handful
    /// of sample periods; a dropout spans whatever the link lost. Eight periods
    /// sits orders of magnitude clear of both at any rate the hardware offers.
    public static let reorderPeriods = 8

    /// The real-time clock the packet counter runs on.
    ///
    /// **Not** a TCXO sampling clock (312500 Hz, or 255765.625 Hz), which some
    /// firmware uses to derive the rate. Sizing the window in that domain makes
    /// it 9.5x too wide.
    public static let rtcTicksPerSecond = 32768.0

    /// The largest fraction of the counter's range a window may occupy.
    ///
    /// At 1 Hz on the 2-byte counter eight sample periods is four whole
    /// modulos, and a window at or above the modulo leaves no backward step
    /// large enough to be a roll-over — the unwrap would stop counting them
    /// altogether.
    public static let maxWindowDivisor = 8

    /// One sample's place on the timeline.
    public struct Result {
        /// The counter with its roll-overs added back. **Not monotonic**: a
        /// reordered packet reports the position it actually holds, which is
        /// behind the sample before it.
        public let unwrappedTicks: Double
        /// How many whole modulos `unwrappedTicks` is above the counter's
        /// origin. Carried as state by the caller; it may dip by one for a
        /// packet arriving late from before a boundary.
        public let cycle: Double
        /// True when the record carried no usable timestamp. The timeline is
        /// held where it was, so `unwrappedTicks` and `cycle` repeat the
        /// previous sample's and say nothing about when this one was taken.
        /// The sensor values are real; only the time is missing.
        public let rejected: Bool

        public init(unwrappedTicks: Double, cycle: Double, rejected: Bool) {
            self.unwrappedTicks = unwrappedTicks
            self.cycle = cycle
            self.rejected = rejected
        }
    }

    /// The reorder window for a stream at a known sampling rate, in ticks.
    ///
    /// Sized in **sample periods**, not as a fraction of the counter's range.
    /// The two are easy to confuse and behave very differently: a reorder swaps
    /// adjacent packets, whereas a dropout that happens to span the wrap point
    /// is most of a modulo. Sizing the window by the modulo puts the boundary
    /// between them in the middle of ordinary dropout territory — at 2^16 every
    /// gap between 1.75 s and 2.0 s reads as a reorder and the roll-over is
    /// silently lost. Eight sample periods shrinks that misread band to about
    /// 16 ms.
    ///
    /// `0` — the branch disabled — when the rate is not a usable number. Never
    /// guess: an unknown rate must not become an infinite window, which would
    /// read every backward step as a reorder and lose every roll-over. That is
    /// a worse failure than no reorder detection at all, because the recording
    /// still looks plausible.
    ///
    /// - Parameters:
    ///   - samplingRateHz: Samples per second, in the 32768 Hz tick domain.
    ///   - maxTicks: The counter's range.
    public static func reorderWindowTicks(samplingRateHz: Double, maxTicks: Int) -> Double {
        if samplingRateHz.isNaN || samplingRateHz.isInfinite || samplingRateHz <= 0.0 {
            return 0.0
        }
        let window = Double(reorderPeriods) * rtcTicksPerSecond / samplingRateHz
        return min(window, Double(maxTicks) / Double(maxWindowDivisor))
    }

    /// The rule, with reorder detection disabled.
    ///
    /// `hasPreviousSample` is asked for here too. Defaulting it would be a quiet
    /// way to get the first sample of a stream wrong, and there is no caller
    /// older than this file to keep compatible - unlike the C# and Java copies,
    /// which keep an overload that infers it from `(0, 0)` for exactly that
    /// reason.
    public static func unwrap(rawTicks: Double, lastUnwrapped: Double, cycle: Double,
                              maxTicks: Int, hasPreviousSample: Bool) -> Result {
        return unwrap(rawTicks: rawTicks, lastUnwrapped: lastUnwrapped, cycle: cycle,
                      maxTicks: maxTicks, reorderWindowTicks: 0.0,
                      hasPreviousSample: hasPreviousSample)
    }

    /// Place one sample on the timeline.
    ///
    /// Every decision is made on the **modular forward distance** from the
    /// previous sample — never by comparing candidate unwrapped values, which
    /// looks equivalent and is not. A packet arriving late from just before a
    /// boundary has a candidate *above* its predecessor, so a comparison
    /// accepts it as forward motion of nearly a whole modulo and then reads the
    /// next real sample as a second roll-over: `[2^24 - 10, 5, 2^24 - 10, 70]`
    /// lands at 33554502, two modulos out, from one out-of-order packet.
    ///
    /// Forward motion is the **default**, which is what keeps a roll-over
    /// preceded by a long dropout classified as a roll-over: however much was
    /// lost, the counter still wrapped. A rule that defaults the other way —
    /// "a backward step is corrupt unless it clears some threshold" — fails
    /// exactly there.
    ///
    /// - Parameters:
    ///   - rawTicks: The counter value out of the packet.
    ///   - lastUnwrapped: The previous accepted sample's unwrapped value.
    ///   - cycle: The previous accepted sample's cycle.
    ///   - maxTicks: The counter's range.
    ///   - reorderWindowTicks: From `reorderWindowTicks(samplingRateHz:maxTicks:)`.
    ///   - hasPreviousSample: False only before the first sample of a stream.
    ///     Asked outright rather than inferred from `(0, 0)`, which is the reset
    ///     state *and* a state this rule can reach: a reorder that lands exactly
    ///     on the counter's origin leaves both at zero in the middle of a
    ///     stream, after which the next packet is read as a first sample and
    ///     passed through - so one arriving from just before the origin is
    ///     placed a whole modulo late rather than a few ticks behind. The
    ///     conformance vector
    ///     `reorder-onto-origin-then-earlier-packet-24bit` is that sequence.
    ///     Hosts that keep the previous raw value instead of a cycle count, as
    ///     the web SDK and pyshimmer do, never had the ambiguity.
    public static func unwrap(rawTicks: Double, lastUnwrapped: Double, cycle: Double,
                              maxTicks: Int, reorderWindowTicks: Double,
                              hasPreviousSample: Bool) -> Result {
        if !hasPreviousSample {
            // No predecessor to measure against. Taking the reset state as a real
            // sample at zero would let a first raw value near the top of the range
            // read as a packet reordered across a boundary, placing a whole
            // recording one modulo early.
            return Result(unwrappedTicks: rawTicks, cycle: 0.0, rejected: false)
        }

        let modulo = Double(maxTicks)
        let lastRaw = lastUnwrapped - (modulo * cycle)
        var forward = rawTicks - lastRaw
        if forward < 0 { forward += modulo }
        let backwards = modulo - forward

        let candidate: Double
        if forward == 0.0 {
            // A duplicate: hold the timeline where it is.
            candidate = lastUnwrapped
        } else if backwards <= reorderWindowTicks {
            // Reordered, on either side of a boundary. Placed where it was
            // actually taken, which is below its predecessor — honest rather
            // than monotonic.
            candidate = lastUnwrapped - backwards
        } else if maxTicks == ticksMax3Byte && rawTicks == 0.0
                    && lastRaw < modulo - Double(wrapWindowTicks) {
            // A record the firmware never stamped. Nothing about it moves the
            // state, so the next real sample reads as the ordinary step forward
            // it is rather than as a second roll-over.
            return Result(unwrappedTicks: lastUnwrapped, cycle: cycle, rejected: true)
        } else {
            candidate = lastUnwrapped + forward
        }

        return Result(unwrappedTicks: candidate,
                      cycle: (candidate / modulo).rounded(.down),
                      rejected: false)
    }
}
