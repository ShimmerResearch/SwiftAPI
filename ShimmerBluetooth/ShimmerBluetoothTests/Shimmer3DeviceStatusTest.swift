//
//  Shimmer3DeviceStatusTest.swift
//  ShimmerBluetoothTests
//
//  Created by Shimmer Engineering on 04/10/2026.
//

import XCTest
@testable import ShimmerBluetooth

/// The unsolicited status push, `[0xFF] 0x8A 0x71 <status...> [crc...]`: log-and-stream-common
/// `docs/SHIMMER3_BT_COMMUNICATION_PROTOCOL.md` §3.2, §5.3 and §5.4.
class Shimmer3DeviceStatusTest: XCTestCase {

    /// A push as `ShimBt_instreamStatusRespSend` builds it: the ACK if prefixed, 0x8A 0x71, the
    /// status bytes, then the session CRC over all of that.
    func push(_ status: [UInt8], prefixed: Bool, crcBytes: Int) -> [UInt8] {
        var bytes: [UInt8] = prefixed ? [0xFF, 0x8A, 0x71] : [0x8A, 0x71]
        bytes.append(contentsOf: status)
        return bytes + Array(ShimmerUtilities.shimmerUartCrcCalc(bytes, bytes.count).prefix(crcBytes))
    }

    /// A bare ACK with the session CRC, which is how the reply to a waiting command starts.
    func bareAck(crcBytes: Int) -> [UInt8] {
        return [0xFF] + Array(ShimmerUtilities.shimmerUartCrcCalc([0xFF], 1).prefix(crcBytes))
    }

    func testDecodesEachBitOfTheFirstStatusByte() {
        // Bit 0 to bit 7, ShimBt_assembleStatusBytes (§5.3)
        let fields: [KeyPath<Shimmer3DeviceStatus, Bool>] = [\.docked, \.sensing, \.rtcSet, \.sdLogging, \.streaming, \.sdInserted, \.sdBadFile, \.redLedOn]
        for bit in 0..<8 {
            let status = Shimmer3DeviceStatus(statusBytes: [UInt8(1 << bit)])!
            for (index, field) in fields.enumerated() {
                XCTAssertEqual(status[keyPath: field], index == bit, "status bit \(bit), field \(index)")
            }
        }
    }

    func testOnlyASecondStatusByteReportsUsb() {
        XCTAssertNil(Shimmer3DeviceStatus(statusBytes: [0x21])!.usbPluggedIn, "one byte: not reported, which is not unplugged")
        XCTAssertEqual(Shimmer3DeviceStatus(statusBytes: [0x21, 0x00])!.usbPluggedIn, false)
        XCTAssertEqual(Shimmer3DeviceStatus(statusBytes: [0x21, 0x01])!.usbPluggedIn, true)
        XCTAssertEqual(Shimmer3DeviceStatus(statusBytes: [0x21, 0x01])!.raw, [0x21, 0x01])
        XCTAssertNil(Shimmer3DeviceStatus(statusBytes: []))
    }

    func testStatusPayloadBytes() {
        func width(_ hardware: Int, _ firmwareIdentifier: Int, _ major: Int, _ minor: Int, _ fwInternal: Int) -> Int? {
            return Shimmer3StatusPush.statusPayloadBytes(hardwareVersion: hardware, firmwareIdentifier: firmwareIdentifier, firmwareMajor: major, firmwareMinor: minor, firmwareInternal: fwInternal)
        }
        let shimmer3 = Shimmer3Protocol.HardwareType.Shimmer3.rawValue
        let shimmer3R = Shimmer3Protocol.HardwareType.Shimmer3R.rawValue
        let logAndStream = Shimmer3StatusPush.FW_IDENTIFIER_LOGANDSTREAM

        // Unknown until the versions are read.
        XCTAssertNil(width(-1, -1, -1, -1, -1))
        XCTAssertNil(width(shimmer3R, -1, -1, -1, -1))
        // No Shimmer3 sends a second byte, at any version, so its hardware is enough.
        XCTAssertEqual(width(shimmer3, -1, -1, -1, -1), 1)
        XCTAssertEqual(width(shimmer3, logAndStream, 1, 1, 6), 1)
        // Shimmer3R LogAndStream from v1.00.024.
        XCTAssertEqual(width(shimmer3R, logAndStream, 1, 0, 23), 1)
        XCTAssertEqual(width(shimmer3R, logAndStream, 1, 0, 24), 2)
        XCTAssertEqual(width(shimmer3R, logAndStream, 1, 0, 50), 2)
        XCTAssertEqual(width(shimmer3R, logAndStream, 1, 1, 0), 2, "minor 1 is after v1.00.024, whatever the internal number")
        XCTAssertEqual(width(shimmer3R, logAndStream, 0, 0, 30), 1, "major 0 is before v1.00.024, whatever the internal number")
        // Firmware other than LogAndStream (1 is BtStream).
        XCTAssertEqual(width(shimmer3R, 1, 1, 0, 30), 1)
    }

    func testFramesTheFirmwareReferenceCrcVectors() {
        // CRCs from log-and-stream-common Extras/python_scripts/Shimmer_common/shimmer_crc.py, not from this API.
        XCTAssertEqual(Shimmer3StatusPush.frame([0xFF, 0x8A, 0x71, 0x31, 0xC5, 0xBA], statusBytes: 1, crcBytes: 2), .push(length: 6, statusBytes: [0x31], crcValid: true))
        XCTAssertEqual(Shimmer3StatusPush.frame([0xFF, 0x8A, 0x71, 0x31, 0x01, 0x1E, 0x4B], statusBytes: 2, crcBytes: 2), .push(length: 7, statusBytes: [0x31, 0x01], crcValid: true))
        XCTAssertEqual(Shimmer3StatusPush.frame([0x8A, 0x71, 0x31, 0xE8, 0x7C], statusBytes: 1, crcBytes: 2), .push(length: 5, statusBytes: [0x31], crcValid: true))
        XCTAssertEqual(Shimmer3StatusPush.frame([0x8A, 0x71, 0x31, 0x01, 0xC9], statusBytes: 2, crcBytes: 1), .push(length: 5, statusBytes: [0x31, 0x01], crcValid: true))
    }

    func testFramesAPushWithAndWithoutPrefixInEveryCrcMode() {
        for prefixed in [true, false] {
            for crcBytes in 0...2 {
                for status: [UInt8] in [[0x21], [0x21, 0x01]] {
                    let bytes = push(status, prefixed: prefixed, crcBytes: crcBytes)
                    let expected = Shimmer3StatusPush.Head.push(length: bytes.count, statusBytes: status, crcValid: true)
                    let context = "prefixed \(prefixed), CRC \(crcBytes), status \(status)"
                    XCTAssertEqual(Shimmer3StatusPush.frame(bytes, statusBytes: status.count, crcBytes: crcBytes), expected, context)
                    // Whatever follows is left alone: here, the reply to the command that was waiting.
                    XCTAssertEqual(Shimmer3StatusPush.frame(bytes + bareAck(crcBytes: crcBytes), statusBytes: status.count, crcBytes: crcBytes), expected, context)
                }
            }
        }
    }

    func testWaitsForTheRestOfAPush() {
        for prefixed in [true, false] {
            for crcBytes in 0...2 {
                let bytes = push([0x21, 0x01], prefixed: prefixed, crcBytes: crcBytes)
                for count in 1..<bytes.count {
                    // A lone 0xFF is an ACK until more bytes say otherwise.
                    let expected: Shimmer3StatusPush.Head = (prefixed && count == 1) ? .notAPush : .incomplete
                    XCTAssertEqual(Shimmer3StatusPush.frame(Array(bytes.prefix(count)), statusBytes: 2, crcBytes: crcBytes), expected, "prefixed \(prefixed), CRC \(crcBytes), \(count) bytes")
                }
            }
        }
    }

    func testLeavesEverythingElseAlone() {
        for crcBytes in 0...2 {
            for statusBytes: Int? in [1, 2, nil] {
                func frame(_ bytes: [UInt8]) -> Shimmer3StatusPush.Head {
                    return Shimmer3StatusPush.frame(bytes, statusBytes: statusBytes, crcBytes: crcBytes)
                }
                XCTAssertEqual(frame([]), .notAPush)
                XCTAssertEqual(frame(bareAck(crcBytes: crcBytes)), .notAPush, "an ACK's CRC is F4 65, never 8A 71")
                XCTAssertEqual(frame([0xFE, 0xC5, 0x56]), .notAPush, "a NACK")
                XCTAssertEqual(frame([0x00, 0x01, 0x02, 0x03, 0x04]), .notAPush, "a data packet")
                XCTAssertEqual(frame([0xFF, 0x2F, 0x03, 0x00, 0x01, 0x00, 0x18, 0x00]), .notAPush, "an ACK and its reply")
                XCTAssertEqual(frame([0xFF, 0x8A, 0x94, 0x00, 0x08, 0x00]), .notAPush, "the battery reply, also behind 0x8A")
                XCTAssertEqual(frame([0xFF, 0xFF, 0x8A, 0x71, 0x21]), .notAPush, "an ACK ahead of a push goes first")
            }
        }
    }

    func testFramesAPushWhoseCrcDoesNotMatch() {
        var bytes = push([0x21, 0x01], prefixed: true, crcBytes: 2)
        bytes[bytes.count - 1] ^= 0xFF
        XCTAssertEqual(Shimmer3StatusPush.frame(bytes, statusBytes: 2, crcBytes: 2), .push(length: 7, statusBytes: [0x21, 0x01], crcValid: false), "still sized, so the stream stays aligned")
    }

    func testTellsTheWidthBeforeTheVersionsAreRead() {
        // Every first status byte, both widths, both prefix states and every CRC mode, followed by
        // what comes next during connect(): the reply to the command that is waiting. The CRC is
        // what makes this hard. A one-byte push's CRC low byte is 0x00 or 0x01, as a second status
        // byte would be, for 0x52 and 0x71 prefixed and for 0x1F and 0x96 unprefixed.
        for prefixed in [true, false] {
            for crcBytes in 0...2 {
                for byte0 in 0...255 {
                    for status: [UInt8] in [[UInt8(byte0)], [UInt8(byte0), 0x00], [UInt8(byte0), 0x01]] {
                        let bytes = push(status, prefixed: prefixed, crcBytes: crcBytes)
                        XCTAssertEqual(Shimmer3StatusPush.frame(bytes + bareAck(crcBytes: crcBytes), statusBytes: nil, crcBytes: crcBytes),
                                       .push(length: bytes.count, statusBytes: status, crcValid: true),
                                       "prefixed \(prefixed), CRC \(crcBytes), status \(status)")
                    }
                }
            }
        }
        // With no CRC, a one-byte status cannot be told from the first of two until the next byte arrives.
        XCTAssertEqual(Shimmer3StatusPush.frame([0xFF, 0x8A, 0x71, 0x21], statusBytes: nil, crcBytes: 0), .incomplete)
    }
}
