//
//  SoundLevelSensor.swift
//  ShimmerBluetooth
//
//  The Shimmer3R's sound level channel, 0x38.
//

import Foundation

/// The A-weighted sound level the Shimmer3R firmware computes from its microphone: channel 0x38,
/// an int16, little-endian, in 0.01 dB(A) steps. LogAndStream_Shimmer3R v1.01.026 is the first
/// release with it.
///
/// - `-32768` means no level: the firmware sends it before its first level after the microphone
///   capture starts, and while the capture is not running. It calibrates to NaN, not -327.68 dB.
/// - Each value covers 128 ms of audio and repeats until the next one. The middle of those 128 ms
///   is 64 to 192 ms before the packet's timestamp.
/// - The level is nominal: the firmware works it out from the microphone's datasheet, not from a
///   calibrated meter.
///
/// The channel has no enabled-sensors bit; the firmware turns it on from configuration byte 233
/// bit 4. So it is enabled here when the inquiry response lists it.
public class SoundLevelSensor: Sensor, SensorProcessing {
    public static let SOUND_LEVEL = "Sound Level"
    /// The raw value that means the firmware has no level to report.
    public static let NO_LEVEL: Int = -32768

    public var packetIndex: Int = -1

    /// A raw sound level in dB(A): raw / 100, or NaN for `NO_LEVEL`.
    public static func calibrate(raw: Int) -> Double {
        return raw == NO_LEVEL ? Double.nan : Double(raw) / 100.0
    }

    public func processData(sensorPacket: [UInt8], objectCluster: ObjectCluster) -> ObjectCluster {
        let bytes = Array(sensorPacket[packetIndex..<packetIndex+2])
        let raw = ShimmerUtilities.parseSensorData(sensorData: bytes, dataType: SensorDataType.i16)!
        objectCluster.addData(sensorName: SoundLevelSensor.SOUND_LEVEL, formatName: SensorFormats.Raw.rawValue, unitName: SensorUnits.noUnit.rawValue, value: Double(raw))
        if (calibrationEnabled) {
            objectCluster.addData(sensorName: SoundLevelSensor.SOUND_LEVEL, formatName: SensorFormats.Calibrated.rawValue, unitName: SensorUnits.decibelsA.rawValue, value: SoundLevelSensor.calibrate(raw: raw))
        }
        return objectCluster
    }
}
