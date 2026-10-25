//
//  HighGAccel.swift
//  ShimmerBluetooth
//
//  Created by Shimmer Engineering on 04/06/2025.
//

import Foundation

public class HighGAccelSensor : IMUSensor , SensorProcessing{
    
    
    public var packetIndexHighGAccelX:Int = -1
    public var packetIndexHighGAccelY:Int = -1
    public var packetIndexHighGAccelZ:Int = -1
    public static let HIGHG_ACCEL_X = "HighG Accel X"
    public static let HIGHG_ACCEL_Y = "HighG Accel Y"
    public static let HIGHG_ACCEL_Z = "HighG Accel Z"
    var highGAccelRange = 0
    var CALIBRATION_ID = 40
    var AlignmentMatrix : [[Double]] = [[0,1,0],[1,0,0],[0,0,-1]]
    var SensitivityMatrix : [[Double]] = [[1,0,0],[0,1,0],[0,0,1]]
    var OffsetVector : [Double] = [10,10,10]
    
    public func processData(sensorPacket: [UInt8], objectCluster: ObjectCluster) -> ObjectCluster {
        let x = Array(sensorPacket[packetIndexHighGAccelX..<packetIndexHighGAccelX+2])
        let y = Array(sensorPacket[packetIndexHighGAccelY..<packetIndexHighGAccelY+2])
        let z = Array(sensorPacket[packetIndexHighGAccelZ..<packetIndexHighGAccelZ+2])
        // 0x14-0x16 are big-endian on both generations, in different encodings
        // (log-and-stream-common docs/SHIMMER3_STREAMING_DATA_FORMAT.md section 5).
        // A Shimmer3R sends the ADXL371's 12-bit value, left-justified. A Shimmer3
        // sends its MPU9x50/ICM-20948 accelerometer as a plain int16; decoding that
        // as 12 bits read it at a sixteenth of its value (DEV-1338).
        let dataType = HardwareVersion == Shimmer3Protocol.HardwareType.Shimmer3.rawValue ? SensorDataType.i16MSB : SensorDataType.i12MSB
        let rawDataX = Double(ShimmerUtilities.parseSensorData(sensorData: x, dataType: dataType)!)
        let rawDataY = Double(ShimmerUtilities.parseSensorData(sensorData: y, dataType: dataType)!)
        let rawDataZ = Double(ShimmerUtilities.parseSensorData(sensorData: z, dataType: dataType)!)
        if (calibrationEnabled && AlignmentMatrix.count == 3 && SensitivityMatrix.count == 3 && OffsetVector.count == 3){
            let data:[Double] = [rawDataX,rawDataY,rawDataZ]

            let(calData)=IMUSensor.calibrateInertialSensorData(data,AlignmentMatrix,SensitivityMatrix,OffsetVector)
            objectCluster.addData(sensorName: HighGAccelSensor.HIGHG_ACCEL_X, formatName: SensorFormats.Calibrated.rawValue, unitName: SensorUnits.meterPerSecondSquared.rawValue, value: calData![0])
            objectCluster.addData(sensorName: HighGAccelSensor.HIGHG_ACCEL_Y, formatName: SensorFormats.Calibrated.rawValue, unitName: SensorUnits.meterPerSecondSquared.rawValue, value: calData![1])
            objectCluster.addData(sensorName: HighGAccelSensor.HIGHG_ACCEL_Z, formatName: SensorFormats.Calibrated.rawValue, unitName: SensorUnits.meterPerSecondSquared.rawValue, value: calData![2])
            print("HG X : \(calData![0]) ,  HG Y : \(calData![1]),  HG Z : \(calData![2])")
        }
        print("HGR X : \(rawDataX) ,  HGR Y : \(rawDataY),  HGR Z : \(rawDataZ)")
        objectCluster.addData(sensorName: HighGAccelSensor.HIGHG_ACCEL_X, formatName: SensorFormats.Raw.rawValue, unitName: SensorUnits.meterPerSecondSquared.rawValue, value: rawDataX)
        objectCluster.addData(sensorName: HighGAccelSensor.HIGHG_ACCEL_Y, formatName: SensorFormats.Raw.rawValue, unitName: SensorUnits.meterPerSecondSquared.rawValue, value: rawDataY)
        objectCluster.addData(sensorName: HighGAccelSensor.HIGHG_ACCEL_Z, formatName: SensorFormats.Raw.rawValue, unitName: SensorUnits.meterPerSecondSquared.rawValue, value: rawDataZ)
        
        return objectCluster
    }
    
    public override func parseSensorCalibrationDump(bytes: [UInt8]){
        var sensorID = Int(bytes[0]) + (Int(bytes[1])<<8)
        if bytes[0] == CALIBRATION_ID {
            var range = bytes[2]
            var calbytes = bytes
            calbytes.removeFirst(12)
            if ShimmerUtilities.isAllFF(calbytes) || ShimmerUtilities.isAllZeros(calbytes) {
                print("HighGAccel calibration invalid — keeping default calibration")
                return
            }
            (AlignmentMatrix,SensitivityMatrix,OffsetVector) = parseIMUCalibrationParameters(bytes: calbytes)
        }
    }
    
    public func setInfoMem(infomem: [UInt8]) {
        
        var enabled = Int(infomem[ConfigByteLayoutShimmer3.idxSensors2]>>6) & 1
        
        if (enabled == 1){
            sensorEnabled = true
        } else {
            sensorEnabled = false
        }
    }
    
    
}
