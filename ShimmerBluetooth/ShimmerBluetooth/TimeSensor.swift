//
//  TimeSensor.swift
//  ShimmerBluetooth
//
//  Created by Shimmer Engineering on 20/11/2023.
//

import Foundation

public class TimeSensor : Sensor , SensorProcessing{
    public var packetIndexTimeStamp:Int = -1
    public static let TimeStamp = "Time Stamp"
    
    public func processData(sensorPacket: [UInt8], objectCluster: ObjectCluster) -> ObjectCluster {
        let desiredRange = Array(sensorPacket[packetIndexTimeStamp..<packetIndexTimeStamp+3])
        let rawData = ShimmerUtilities.parseSensorData(sensorData: desiredRange, dataType: SensorDataType.u24)
        /* The unwrap runs whether or not calibration is on. A record the
           firmware never stamped has no time either way, so `timestampValid`
           has to mean something in both modes - and a timeline that only
           advanced while someone was watching would jump by however much was
           missed the moment calibration was switched on mid-stream. */
        let calData = calibrateTimeStamp(timeStamp: Double(rawData!))
        if (calibrationEnabled){
            objectCluster.addData(sensorName: TimeSensor.TimeStamp, formatName: SensorFormats.Calibrated.rawValue, unitName: SensorUnits.milliSeconds.rawValue, value: calData)
            print("TimeStamp (mS) :  \(calData)")
        }
        /* A record the firmware never stamped keeps its sensor values and
           loses its time. Both Time Stamp signals are still added - the raw
           one is what the packet said, and the calibrated one repeats the
           previous packet - so a consumer reading by signal name is
           unaffected, and one that needs a true time axis has
           `timestampValid` to filter on. */
        objectCluster.timestampValid = !lastRecordRejected
        objectCluster.addData(sensorName: TimeSensor.TimeStamp, formatName: SensorFormats.Raw.rawValue, unitName: SensorUnits.noUnit.rawValue, value: Double(rawData!))
        return objectCluster
    }
    
    var LastReceivedTimeStamp:Double = 0
    var TimeStampPacketRawMaxTicks:Int = TimestampUnwrap.ticksMax3Byte
    var CurrentTimeStampCycle:Double = 0

    /// How far behind its predecessor a value may be and still be read as a
    /// reordered packet, in ticks. `0` disables the branch, which is what an
    /// unknown sampling rate has to mean; `Shimmer3Protocol` sets it from the
    /// inquiry response. See `TimestampUnwrap.reorderWindowTicks`.
    public var reorderWindowTicks: Double = 0.0

    /// True when the packet just processed carried no usable timestamp.
    public private(set) var lastRecordRejected = false

    /// Unwrap one packet's counter value and convert it to milliseconds.
    ///
    /// The rule is `TimestampUnwrap`, shared with every other Shimmer host API
    /// and checked against the same conformance vectors. What used to be here
    /// was "the value went down, so it wrapped", which charges a whole modulo -
    /// 512 seconds, permanently - for a reordered packet, a duplicated packet
    /// or a record the firmware never stamped.
    ///
    /// A rejected record leaves every piece of state where it is, so the next
    /// real sample is compared against the last value the firmware actually
    /// stamped and reads as the ordinary step forward it is.
    func calibrateTimeStamp(timeStamp: Double) -> Double {
        let result = TimestampUnwrap.unwrap(rawTicks: timeStamp,
                                            lastUnwrapped: LastReceivedTimeStamp,
                                            cycle: CurrentTimeStampCycle,
                                            maxTicks: TimeStampPacketRawMaxTicks,
                                            reorderWindowTicks: reorderWindowTicks)
        lastRecordRejected = result.rejected
        LastReceivedTimeStamp = result.unwrappedTicks
        CurrentTimeStampCycle = result.cycle

        let clockConstant:Double = 32768;
        let calibratedTimeStamp = LastReceivedTimeStamp / clockConstant * 1000;   // to convert into mS
        return calibratedTimeStamp
    }
    
    public func setInfoMem(infomem: [UInt8]) {
        
    }
    
    
}
