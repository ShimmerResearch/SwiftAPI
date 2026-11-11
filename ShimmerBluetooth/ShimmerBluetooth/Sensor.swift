//
//  Sensor.swift
//  ShimmerBluetooth
//
//  Created by Shimmer Engineering on 17/11/2023.
//

import Foundation

public enum SensorDataType {
    case u8
    case i8
    case u12
    case i12
    case u16
    case u16MSB
    case i16
    case i16MSB
    case u24
    case u24MSB
    case i24MSB
    case i12MSB
}

public class Sensor: NSObject{


    public enum SensorFormats:String {
        case Calibrated = "Calibrated"
        case Raw = "Raw"
    }
    public enum SensorUnits:String {
        case noUnit = "noUnit"
        case milliSeconds = "mS"
        case meterPerSecondSquared = "m/s²"
        case degreepersecond = "deg/sec"
        case localflux = "localflux"
        case milliVolts = "mV"
        case kiloOhms = "kΩ"
        case microSiemens = "µS"
        case percent = "%"
        case kpascal = "kPa"
        case degreescelcius = "Degree Celsius"
        case decibelsA = "dB(A)"
    }
    public var sensorEnabled:Bool = false
    public var calibrationEnabled:Bool = true
    public func parseSensorCalibrationDump(bytes: [UInt8]){
        
    }
    
    func calibrateU12AdcValue(_ uncalibratedData : Double, _ offset: Double, _ vRefP : Double, _ gain : Double) -> Double
    {
        let calibratedData = (uncalibratedData - offset) * (((vRefP * 1000) / gain) / 4095);
        return calibratedData;
    }
    
}

public protocol SensorProcessing {
    func processData(sensorPacket: [UInt8], objectCluster: ObjectCluster) -> ObjectCluster
}

public protocol IMUProcessing {
    func parseIMUCalibrationParameters(bytes: [UInt8]) -> ([[Double]],[[Double]],[Double])
}
