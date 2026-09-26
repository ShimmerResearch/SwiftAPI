//
//  GSRSensor.swift
//  ShimmerBluetooth
//
//  Created by Shimmer Engineering on 22/11/2023.
//

import Foundation

public class GSRSensor: Sensor , SensorProcessing{
    
    public var packetIndex:Int = -1
    public var gsrRange:Int = -1
    public static let GSR = "GSR"
    public static let GSR_SKIN_RESISTANCE = "GSR Skin Resistance"
    public static let GSR_SKIN_CONDUCTANCE = "GSR Skin Conductance"
    public static let SHIMMER3_GSR_REF_RESISTORS_KOHMS:[Double] = [
                40.200,     //Range 0
                287.000,     //Range 1
                1000.000,     //Range 2
                3300.000];  //Range 3
    // Equation breaks down below 683 on every range: 683 is the first code above the 0.5 V
    // amplifier reference at 3.0 V (see calibrateGsrDataToResistanceWithOpenCircuitLimit)
    
    
    public static let SHIMMER3_GSR_RESISTANCE_MIN_MAX_KOHMS : [[Double]] = [
                [8.0, 63.0],         //Range 0
                [63.0, 220.0],         //Range 1
                [220.0, 680.0],     //Range 2
                [680.0, 4700.0]]     //Range 3
    
    public static let GSR_UNCAL_LIMIT_RANGE3:Double = 683;
    
    public func processData(sensorPacket: [UInt8], objectCluster: ObjectCluster) -> ObjectCluster {
        let x = Array(sensorPacket[packetIndex..<packetIndex+2])
        let rawDataX = Double(ShimmerUtilities.parseSensorData(sensorData: x, dataType: SensorDataType.u16)!)
        if (calibrationEnabled){
            var newGSRRange = gsrRange
            let gsrData = Double((Int(rawDataX) & 4095));
            var gsrResistanceKOhms: Double = 0
            if (gsrRange == 4)
            {
                newGSRRange = (49152 & Int(rawDataX)) >> 14;
            }
            if (gsrRange == 0 || newGSRRange == 0)
            {
                gsrResistanceKOhms = calibrateGsrDataToResistanceWithOpenCircuitLimit(gsrData, 0);
            }
            else if (gsrRange == 1 || newGSRRange == 1)
            {
                
                gsrResistanceKOhms = calibrateGsrDataToResistanceWithOpenCircuitLimit(gsrData, 1);
            }
            else if (gsrRange == 2 || newGSRRange == 2)
            {
                
                gsrResistanceKOhms = calibrateGsrDataToResistanceWithOpenCircuitLimit(gsrData, 2);
            }
            else if (gsrRange == 3 || newGSRRange == 3)
            {
                
                gsrResistanceKOhms = calibrateGsrDataToResistanceWithOpenCircuitLimit(gsrData, 3);
            }
            gsrResistanceKOhms = NudgeGsrResistance(gsrResistanceKOhms, gsrRange)
            print("GSR (kOhms): \(gsrResistanceKOhms)")
            objectCluster.addData(sensorName: GSRSensor.GSR_SKIN_RESISTANCE, formatName: SensorFormats.Calibrated.rawValue, unitName: SensorUnits.kiloOhms.rawValue, value: gsrResistanceKOhms)
             
            let gsrConductanceUS = gsrResistanceKOhms > 0 ? (1000.0 / gsrResistanceKOhms) : 0.0
            objectCluster.addData(sensorName: GSRSensor.GSR_SKIN_CONDUCTANCE, formatName: SensorFormats.Calibrated.rawValue, unitName: SensorUnits.microSiemens.rawValue, value: gsrConductanceUS)
        }
        objectCluster.addData(sensorName: GSRSensor.GSR, formatName: SensorFormats.Raw.rawValue, unitName: SensorUnits.noUnit.rawValue, value: rawDataX)
        return objectCluster
    }
    
    public func setInfoMem(infomem: [UInt8]) {
        gsrRange = (Int(infomem[ConfigByteLayoutShimmer3.idxConfigSetupByte3])>>ConfigByteLayoutShimmer3.bitShiftGSRRange) & ConfigByteLayoutShimmer3.maskGSRRange
        var enabled = Int(infomem[ConfigByteLayoutShimmer3.idxSensors0]>>2) & 1
        if (enabled == 1){
            sensorEnabled = true
        } else {
            sensorEnabled = false
        }
    }
    
    func nudgeDouble(_ valToNudge: Double,_ minVal: Double,_ maxVal: Double) -> Double {
        return max(minVal, min(maxVal, valToNudge))
    }
    
    /// Clamp a fixed range to its own window; floor auto-range at 8 kOhm, the smallest resistance any
    /// range can measure, as the Java driver and the C# API do (ASM-2156). Any other setting (-1 before
    /// the InfoMem is read, or 5-7 from the 3-bit mask) has no window, and passes through rather than
    /// trapping on the array index.
    func NudgeGsrResistance(_ gsrResistanceKOhms : Double,_ gsrRangeSetting: Int) ->Double
            {
                if (gsrRangeSetting == 4)
                {
                    return max(GSRSensor.SHIMMER3_GSR_RESISTANCE_MIN_MAX_KOHMS[0][0], gsrResistanceKOhms);
                }
                if (gsrRangeSetting >= 0 && gsrRangeSetting < GSRSensor.SHIMMER3_GSR_RESISTANCE_MIN_MAX_KOHMS.count)
                {
                    return nudgeDouble(gsrResistanceKOhms, GSRSensor.SHIMMER3_GSR_RESISTANCE_MIN_MAX_KOHMS[gsrRangeSetting][0], GSRSensor.SHIMMER3_GSR_RESISTANCE_MIN_MAX_KOHMS[gsrRangeSetting][1]);
                }
                return gsrResistanceKOhms;
            }
    
    /// calibrateGsrDataToResistanceFromAmplifierEq, reading an open circuit as open on every range
    /// (DEV-1070).
    ///
    /// The amplifier equation has no positive solution at or below the amplifier's 0.5 V reference: no
    /// skin resistance can pull the output under it, so a code there means the electrodes are open.
    /// Range 3 has long raised such a code to GSR_UNCAL_LIMIT_RANGE3, the first code above the
    /// reference, so that an open circuit decodes as thousands of MOhm. Ranges 0-2 did not, and in
    /// auto-range they see these codes too. When the electrodes come off, the device climbs one range
    /// at a time and repeats the sample that triggered each switch through the 80 ms settling time,
    /// tagged with the range it was measured on. On ranges 0-2 the equation gave those samples a
    /// negative resistance.
    ///
    /// So a code below the limit decodes as range 3 at the limit, whatever range it was measured on,
    /// and an open circuit reads the same on every range as the settled range 3 does. Codes at or above
    /// the limit decode on their own range, as before. The Java driver and the C# API apply the same
    /// rule.
    func calibrateGsrDataToResistanceWithOpenCircuitLimit(_ gsrUncalibratedData : Double, _ range : Int) -> Double
            {
                if (gsrUncalibratedData < GSRSensor.GSR_UNCAL_LIMIT_RANGE3)
                {
                    return calibrateGsrDataToResistanceFromAmplifierEq(GSRSensor.GSR_UNCAL_LIMIT_RANGE3, 3);
                }
                return calibrateGsrDataToResistanceFromAmplifierEq(gsrUncalibratedData, range);
            }
    
    func calibrateGsrDataToResistanceFromAmplifierEq(_ gsrUncalibratedData : Double, _ range : Int) -> Double
            {
                let rFeedback = GSRSensor.SHIMMER3_GSR_REF_RESISTORS_KOHMS[range];
                let volts = calibrateMspAdcChannel(gsrUncalibratedData) / 1000.0;
                let rSource = rFeedback / ((volts / 0.5) - 1.0);
                return rSource;
            }
    
    func calibrateMspAdcChannel(_ unCalData: Double) -> Double
    {
        let offset = 0.0; let vRefP = 3.0; let gain = 1.0;
        let calData = calibrateU12AdcValue(unCalData, offset, vRefP, gain);
        return calData;
    }
    

}
