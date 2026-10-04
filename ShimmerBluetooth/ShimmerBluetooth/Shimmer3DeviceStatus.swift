//
//  Shimmer3DeviceStatus.swift
//  ShimmerBluetooth
//
//  Created by Shimmer Engineering on 04/10/2026.
//

import Foundation

/// What a Shimmer3 or Shimmer3R says it is doing: the status bytes of a STATUS_RESPONSE (0x71).
///
/// The firmware pushes them unasked whenever its state changes for a reason the host did not
/// cause: a dock, an undock, the user button, a trial-duration expiry or a low-battery stop. The
/// bits are in log-and-stream-common `docs/SHIMMER3_BT_COMMUNICATION_PROTOCOL.md` §5.3 and the push
/// in §5.4; `Shimmer3StatusPush` finds one in the byte stream.
public struct Shimmer3DeviceStatus: Equatable {
    /// Sitting in a dock.
    public let docked: Bool
    /// Sensing, for a stream, an SD recording or both.
    public let sensing: Bool
    /// The real-world clock has been set this power cycle. False on firmware too old to report it.
    public let rtcSet: Bool
    /// Logging to the SD card.
    public let sdLogging: Bool
    /// Streaming over Bluetooth.
    public let streaming: Bool
    /// An SD card is in the slot. False on firmware too old to report it.
    public let sdInserted: Bool
    /// The SD card or its file is unusable. False on firmware too old to report it.
    public let sdBadFile: Bool
    /// The red LED's state, as TOGGLE_LED_COMMAND flips it. False on firmware too old to report it.
    public let redLedOn: Bool
    /// USB plugged in, from the second status byte, which only a Shimmer3R sends, from LogAndStream
    /// v1.00.024. nil where that byte is absent, so "not reported" is never read as "unplugged".
    public let usbPluggedIn: Bool?
    /// The status bytes as they arrived.
    public let raw: [UInt8]

    /// Decodes the status bytes alone, the ones after 0x8A 0x71. nil when there are none.
    public init?(statusBytes: [UInt8]) {
        guard let byte0 = statusBytes.first else {
            return nil
        }
        // ShimBt_assembleStatusBytes, log-and-stream-common Comms/shimmer_bt_uart.c
        docked = (byte0 & 0x01) != 0
        sensing = (byte0 & 0x02) != 0
        rtcSet = (byte0 & 0x04) != 0
        sdLogging = (byte0 & 0x08) != 0
        streaming = (byte0 & 0x10) != 0
        sdInserted = (byte0 & 0x20) != 0
        sdBadFile = (byte0 & 0x40) != 0
        redLedOn = (byte0 & 0x80) != 0
        if (statusBytes.count >= 2){
            usbPluggedIn = (statusBytes[1] & 0x01) != 0
        } else {
            usbPluggedIn = nil
        }
        raw = statusBytes
    }
}

/// Finds an unsolicited status push at the head of the receive buffer, and sizes it.
///
/// A push is `[0xFF] 0x8A 0x71 <status...> [crc...]` (§3.2, §5.4):
///
/// - The leading ACK is on by default. SET_INSTREAM_RESPONSE_ACK_PREFIX_STATE (0xA3) turns it off,
///   and the firmware turns it back on at every disconnect. This API never turns it off, so with no
///   CRC an ACK followed at once by an unprefixed push would read as one prefixed push.
/// - The status is 1 byte, or 2 on a Shimmer3R from LogAndStream v1.00.024 (`statusPayloadBytes`).
/// - The session CRC, 0 to 2 bytes, covers everything before it, the ACK included
///   (`ShimBt_instreamStatusRespSend`, log-and-stream-common `Comms/shimmer_bt_uart.c`).
///
/// A host must take one at any time, between a command and its reply too, whether or not it is
/// streaming, and must not take its 0xFF for the ACK of the command it is waiting on (§5.4, rules 1
/// and 2). So `Shimmer3Protocol` asks here before anything else reads the buffer.
enum Shimmer3StatusPush {

    /// What the receive buffer starts with.
    enum Head: Equatable {
        /// Not a status push.
        case notAPush
        /// The start of one: wait for the rest.
        case incomplete
        /// A whole push, `length` bytes from its first byte to its last CRC byte. `crcValid` is false
        /// when the session CRC does not match, and then `statusBytes` cannot be trusted.
        case push(length: Int, statusBytes: [UInt8], crcValid: Bool)
    }

    /// LogAndStream's firmware identifier in the GET_FW_VERSION_COMMAND reply (`REV_FW_IDENTIFIER`).
    static let FW_IDENTIFIER_LOGANDSTREAM = 3

    /// How many status bytes this device sends: 2 on a Shimmer3R running LogAndStream v1.00.024 or
    /// later, 1 on anything else, and nil while the versions that decide it are unread (they are -1
    /// until then).
    ///
    /// The second byte came with log-and-stream-common 8377afc, first released in
    /// LogAndStream_Shimmer3R_v1.00.024 (§5.3 and Appendix A). It is compiled only for SHIMMER3R, so
    /// the hardware decides first: Shimmer3 LogAndStream reaches the same version numbers and never
    /// sends it.
    static func statusPayloadBytes(hardwareVersion: Int, firmwareIdentifier: Int, firmwareMajor: Int, firmwareMinor: Int, firmwareInternal: Int) -> Int? {
        if (hardwareVersion < 0){
            return nil
        }
        if (hardwareVersion != Shimmer3Protocol.HardwareType.Shimmer3R.rawValue){
            return 1
        }
        if (firmwareIdentifier < 0){
            return nil
        }
        if (firmwareIdentifier != FW_IDENTIFIER_LOGANDSTREAM){
            return 1
        }
        return (firmwareMajor, firmwareMinor, firmwareInternal) >= (1, 0, 24) ? 2 : 1
    }

    /// What `buffer` starts with: a whole status push, the start of one, or something else.
    ///
    /// A lone 0xFF is not taken for the start of a push. It is an ACK until more bytes say otherwise,
    /// which is how the receive loop reads the first byte of every other frame too.
    ///
    /// - Parameters:
    ///   - statusBytes: 1 or 2, from `statusPayloadBytes`, or nil while that is unknown.
    ///   - crcBytes: the session CRC's length: 0, 1 or 2.
    static func frame(_ buffer: [UInt8], statusBytes: Int?, crcBytes: Int) -> Head {
        let header: Int // up to and including the 0x71
        if (buffer.first == Shimmer3Protocol.PacketTypeShimmer.instreamCmdResponse.rawValue){
            header = 2
        } else if (buffer.count >= 2 && buffer[0] == Shimmer3Protocol.PacketTypeShimmer.ackCommand.rawValue && buffer[1] == Shimmer3Protocol.PacketTypeShimmer.instreamCmdResponse.rawValue){
            header = 3
        } else {
            return .notAPush
        }
        if (buffer.count < header){
            return .incomplete
        }
        if (buffer[header - 1] != Shimmer3Protocol.PacketTypeShimmer.statusResponse.rawValue){
            return .notAPush // a different 0x8A message, and this API asks for none of them
        }

        let width: Int
        if let knownWidth = statusBytes {
            width = knownWidth
        } else {
            // Unknown until connect() has read both versions, so the bytes have to say. A second
            // status byte is 0x00 or 0x01: bit 0 is usbPluggedIn and bits 1-7 are zero (§5.3).
            // With no CRC, a single status byte is followed by the next message, which starts 0xFF,
            // 0xFE or 0x8A; 0x00 starts only a data packet, and no stream runs before the versions
            // are read. With a CRC, a single status byte is followed by the CRC's low byte, which
            // can be 0x00 or 0x01 as well, so there the CRC decides.
            if (buffer.count < header + 2){
                return .incomplete
            }
            if (buffer[header + 1] > 0x01){
                width = 1
            } else if (crcBytes == 0){
                width = 2
            } else if (buffer.count < header + 2 + crcBytes){
                return .incomplete
            } else if (!crcMatches(buffer, covering: header + 2, crcBytes: crcBytes) && crcMatches(buffer, covering: header + 1, crcBytes: crcBytes)){
                width = 1
            } else {
                width = 2
            }
        }

        let length = header + width + crcBytes
        if (buffer.count < length){
            return .incomplete
        }
        return .push(length: length, statusBytes: Array(buffer[header..<(header + width)]), crcValid: crcMatches(buffer, covering: header + width, crcBytes: crcBytes))
    }

    /// Whether the `crcBytes` bytes after `buffer[0..<length]` are its CRC. True with no CRC.
    private static func crcMatches(_ buffer: [UInt8], covering length: Int, crcBytes: Int) -> Bool {
        if (crcBytes == 0){
            return true
        }
        let crc = ShimmerUtilities.shimmerUartCrcCalc(buffer, length)
        for i in 0..<crcBytes {
            if (buffer[length + i] != crc[i]){
                return false
            }
        }
        return true
    }
}
