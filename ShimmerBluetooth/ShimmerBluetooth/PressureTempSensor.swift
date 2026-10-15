//
//  PressureTempSensor.swift
//  ShimmerBluetooth
//
//  Created by Shimmer Engineering on 21/02/2024.
//

import Foundation

public class PressureTempSensor: Sensor , SensorProcessing{
    public let HardwareVersion: Int
    required init(hwid: Int) {
            self.HardwareVersion = hwid
            super.init()
    }
    public enum Resolution: UInt8 {
            case RES_LOW = 0x0
            case RES_STANDARD = 0x1
            case RES_HIGH = 0x2
            case RES_ULTRAHIGH = 0x3
            
            public static func fromValue(_ value : UInt8) -> Resolution? {
                switch value{
                case 0:
                    return .RES_LOW
                case 1:
                    return .RES_STANDARD
                case 2:
                    return .RES_HIGH
                case 3:
                    return .RES_ULTRAHIGH
                default:
                    return nil
                }
            }
        }
        
    /// The pressure sensor fitted. The raw values are the sensor IDs the firmware
    /// sends in the 0xA6 reply to 0xA7 (PRESSURE_SENSOR_BMP180..BMP581).
    public enum PressureSensorType: UInt8 {
            case BMP180 = 0
            case BMP280 = 1
            case BMP390 = 2
            case BMP581 = 3

            /// Number of calibration coefficient bytes that follow the sensor ID in the 0xA6 reply.
            public var calibrationByteCount: Int {
                switch self {
                case .BMP180:
                    return 22
                case .BMP280:
                    return 24
                case .BMP390:
                    return 21
                case .BMP581:
                    return 0
                }
            }
        }

    /// Set from the 0xA6 reply, or from the SR-number rule when 0xA7 gets no usable reply.
    /// nil (not yet known) keeps the BMP390 path on a Shimmer3R.
    public var pressureSensorType: PressureSensorType? = nil

    /// BMP581 oversampling settings, indexed by the 3-bit pressure resolution field.
    public static let ListOfPressureResolutionBMP581 = ["Lowest Power", "Low", "Standard", "High", "High Res", "Very High Res", "Ultra High Res", "Highest Res"]

    static let FW_ID_LOGANDSTREAM = 3

    var CurrentResolution = Resolution.RES_LOW
    var pressureResolution = 0
    public static let TEMPERATURE = "Temperature"
    public static let PRESSURE = "Pressure"
    public var packetIndexTemp:Int = -1
    public var packetIndexPressure:Int = -1
    public var DIG_T1 = 27504.0;         // unsigned short
    public var DIG_T2 = 26435.0;         // signed short
    public var DIG_T3 = -1000.0;        // signed short
    public var DIG_P1 = 36477.0;        // unsigned short
    public var DIG_P2 = -10685.0;        // signed short
    public var DIG_P3 = 3024.0;            // signed short
    public var DIG_P4 = 2855.0;            // signed short
    public var DIG_P5 = 140.0;             // signed short
    public var DIG_P6 = -7.0;            // signed short
    public var DIG_P7 = 15500.0;        // signed short
    public var DIG_P8 = -14600.0;        // signed short
    public var DIG_P9 = 6000.0;            // signed short
    
    //3R COEFFICIENTS

    var bmp380_t1: UInt16 = 0
    var bmp380_t2: UInt16 = 0
    var bmp380_t3: Int8   = 0

    var bmp380_p1: Int16  = 0
    var bmp380_p2: Int16  = 0
    var bmp380_p3: Int8   = 0
    var bmp380_p4: Int8   = 0
    var bmp380_p5: UInt16 = 0
    var bmp380_p6: UInt16 = 0
    var bmp380_p7: Int8   = 0
    var bmp380_p8: Int8   = 0
    var bmp380_p9: Int16  = 0
    var bmp380_p10: Int16 = 0
    var bmp380_p11: Int8  = 0

    // Intermediate for compensation
    var bmp380_tLin: Double = 0.0
    
    // Quantized calibration (floating-point)
    var par_T1: Double = 0
    var par_T2: Double = 0
    var par_T3: Double = 0
    var par_P1: Double = 0
    var par_P2: Double = 0
    var par_P3: Double = 0
    var par_P4: Double = 0
    var par_P5: Double = 0
    var par_P6: Double = 0
    var par_P7: Double = 0
    var par_P8: Double = 0
    var par_P9: Double = 0
    var par_P10: Double = 0
    var par_P11: Double = 0

    // TLin used for pressure
    var quantized_TLin: Double = 0

    
    
    public func processData(sensorPacket: [UInt8], objectCluster: ObjectCluster) -> ObjectCluster {
        if self.HardwareVersion == Shimmer3Protocol.HardwareType.Shimmer3R.rawValue {
            let idxT = packetIndexTemp
            let idxP = packetIndexPressure

            let rawT = u24(sensorPacket[idxT],
                           sensorPacket[idxT+1],
                           sensorPacket[idxT+2])

            let rawP = u24(sensorPacket[idxP],
                           sensorPacket[idxP+1],
                           sensorPacket[idxP+2])

            objectCluster.addData(sensorName: PressureTempSensor.TEMPERATURE,
                                  formatName: SensorFormats.Raw.rawValue,
                                  unitName: SensorUnits.noUnit.rawValue,
                                  value: Double(rawT))

            objectCluster.addData(sensorName: PressureTempSensor.PRESSURE,
                                  formatName: SensorFormats.Raw.rawValue,
                                  unitName: SensorUnits.noUnit.rawValue,
                                  value: Double(rawP))

            if pressureSensorType == .BMP581 {
                // The BMP581 outputs compensated values, so there are no coefficients to apply
                let (pressurePa, temperatureC) = PressureTempSensor.calibratePressure581(rawP: Int(rawP),
                                                                                        rawT: Int(rawT))

                objectCluster.addData(sensorName: PressureTempSensor.TEMPERATURE,
                                      formatName: SensorFormats.Calibrated.rawValue,
                                      unitName: SensorUnits.degreescelcius.rawValue,
                                      value: temperatureC)

                objectCluster.addData(sensorName: PressureTempSensor.PRESSURE,
                                      formatName: SensorFormats.Calibrated.rawValue,
                                      unitName: SensorUnits.kpascal.rawValue,
                                      value: pressurePa / 1000.0)
                return objectCluster
            }

            let (compPress, tLin) = calibratePressure390(UP: Double(rawP),
                                                         UT: Double(rawT))

            let temperatureC = tLin
            let pressurekPa  = compPress / 1000.0

            objectCluster.addData(sensorName: PressureTempSensor.TEMPERATURE,
                                  formatName: SensorFormats.Calibrated.rawValue,
                                  unitName: SensorUnits.degreescelcius.rawValue,
                                  value: temperatureC)

            objectCluster.addData(sensorName: PressureTempSensor.PRESSURE,
                                  formatName: SensorFormats.Calibrated.rawValue,
                                  unitName: SensorUnits.kpascal.rawValue,
                                  value: pressurekPa)


                print("RawT=\(rawT) RawP=\(rawP)")
                print("Current temperature: \(temperatureC)")
                print("Current pressure: \(pressurekPa)")
                return objectCluster
            }
        else {
            let temperature = Array(sensorPacket[packetIndexTemp..<packetIndexTemp+3])
            let pressure = Array(sensorPacket[packetIndexPressure..<packetIndexPressure+3])
            
            var rawTemperature = Double(ShimmerUtilities.parseSensorData(sensorData: temperature, dataType: SensorDataType.u16MSB)!)
            var rawPressure = Double(ShimmerUtilities.parseSensorData(sensorData: pressure, dataType: SensorDataType.u24MSB)!)
            
            objectCluster.addData(sensorName: PressureTempSensor.TEMPERATURE, formatName: SensorFormats.Raw.rawValue, unitName: SensorUnits.noUnit.rawValue, value: Double(rawTemperature))
            objectCluster.addData(sensorName: PressureTempSensor.PRESSURE, formatName: SensorFormats.Raw.rawValue, unitName: SensorUnits.noUnit.rawValue, value: Double(rawPressure))
            
            if (calibrationEnabled){
                //for SensorBMP280
                rawTemperature = rawTemperature * pow(2,4)
                rawPressure = rawPressure/pow(2,4)
                
                let adc_T = rawTemperature;
                let adc_P = rawPressure;
                
                // Returns temperature in DegC, double precision. Output value of “51.23” equals 51.23 DegC.
                // t_fine carries fine temperature as global value
                var var1 = ((adc_T)/16384.0 - DIG_T1/1024.0) * DIG_T2;
                var var2 = (((adc_T)/131072.0 - DIG_T1/8192.0) * (adc_T/131072.0 - DIG_T1/8192.0)) * DIG_T3;
                let t_fine = var1 + var2;
                let T = t_fine / 5120.0;
                //double fTemp = T * 1.8 + 32; // Fahrenheit
                //T = T/100.0;
                // Returns pressure in Pa as double. Output value of “96386.2” equals 96386.2 Pa = 963.862 hPa
                var1 = (t_fine/2.0) - 64000.0;
                var2 = var1 * var1 * DIG_P6 / 32768.0;
                var2 = var2 + var1 * DIG_P5 * 2.0;
                var2 = (var2/4.0)+(DIG_P4 * 65536.0);
                var1 = (DIG_P3 * var1 * var1 / 524288.0 + DIG_P2 * var1) / 524288.0;
                var1 = (1.0 + var1 / 32768.0)*DIG_P1;
                if (var1 == 0.0) {
                    //   return 0; // avoid exception caused by division by zero
                }
                var p = 1048576.0 - adc_P;
                p = (p - (var2 / 4096.0)) * 6250.0 / var1;
                var1 = DIG_P9 * p * p / 2147483648.0;
                var2 = p * DIG_P8 / 32768.0;
                p = p + (var1 + var2 + DIG_P7) / 16.0;
                let calTemperature = T
                let calPressure = p
                
                
                objectCluster.addData(sensorName: PressureTempSensor.TEMPERATURE, formatName: SensorFormats.Calibrated.rawValue, unitName: SensorUnits.degreescelcius.rawValue, value: Double(calTemperature))
                objectCluster.addData(sensorName: PressureTempSensor.PRESSURE, formatName: SensorFormats.Calibrated.rawValue, unitName: SensorUnits.kpascal.rawValue, value: Double(calPressure/1000))
            }
        }
        return objectCluster
    }
    public func parseCalParamByteArray(pressureResoRes: [UInt8]) {
        print("Cal bytes count = \(pressureResoRes.count)")
        print("Cal bytes = \(pressureResoRes.map{ String(format: "%02X", $0) }.joined(separator: " "))")

        if (HardwareVersion == Shimmer3Protocol.HardwareType.Shimmer3R.rawValue){
            // Drop the first 2 header bytes (length + chipId), keep next 21
                    let b = Array(pressureResoRes.dropFirst(2).prefix(21))

                    func u16(_ i: Int) -> UInt16 {
                        // ConcatenateBytes(high, low) style
                        return (UInt16(b[i+1]) << 8) | UInt16(b[i])
                    }
                    func s16(_ i: Int) -> Int16 {
                        return Int16(bitPattern: u16(i))
                    }
                    func s8(_ i: Int) -> Int8 {
                        return Int8(bitPattern: b[i])
                    }

                    // Raw register values (same indices as C# / Java)
                    let regT1  = u16(0)
                    let regT2  = s16(2)
                    let regT3  = s8(4)

                    let regP1  = s16(5)
                    let regP2  = s16(7)
                    let regP3  = s8(9)
                    let regP4  = s8(10)
                    let regP5  = u16(11)
                    let regP6  = u16(13)
                    let regP7  = s8(15)
                    let regP8  = s8(16)
                    let regP9  = s16(17)
                    let regP10 = s8(19)
                    let regP11 = s8(20)

                    // Quantized conversions — EXACT C#/Java scaling

                    // 1 / 2^8
                    par_T1 = Double(regT1) / 0.00390625
                    // 2^30
                    par_T2 = Double(regT2) / 1073741824.0
                    // 2^48
                    par_T3 = Double(regT3) / 281474976710656.0

                    // 2^20
                    par_P1 = (Double(regP1) - 16384.0) / 1048576.0
                    // 2^29
                    par_P2 = (Double(regP2) - 16384.0) / 536870912.0
                    // 2^32
                    par_P3 = Double(regP3) / 4294967296.0
                    // 2^37
                    par_P4 = Double(regP4) / 137438953472.0

                    // 2^-3
                    par_P5 = Double(regP5) / 0.125
                    // 2^6
                    par_P6 = Double(regP6) / 64.0
                    // 2^8
                    par_P7 = Double(regP7) / 256.0
                    // 2^15
                    par_P8 = Double(regP8) / 32768.0

                    // 2^48
                    par_P9  = Double(regP9) / 281474976710656.0
                    par_P10 = Double(regP10) / 281474976710656.0
                    // 2^65
                    par_P11 = Double(regP11) / 36893488147419103232.0

                    print("par_T1 = \(par_T1)")
                    print("par_T2 = \(par_T2)")
                    print("par_T3 = \(par_T3)")
                    print("par_P1 = \(par_P1)")
                    print("par_P2 = \(par_P2)")
                    print("par_P3 = \(par_P3)")
                    print("par_P4 = \(par_P4)")
                    print("par_P5 = \(par_P5)")
                    print("par_P6 = \(par_P6)")
                    print("par_P7 = \(par_P7)")
                    print("par_P8 = \(par_P8)")
                    print("par_P9 = \(par_P9)")
                    print("par_P10 = \(par_P10)")
                    print("par_P11 = \(par_P11)")

                    return
            return
        } else {
            DIG_T1 = Double((Int(pressureResoRes[0]) + (Int(pressureResoRes[1]) << 8)))
            DIG_T2 = Double(ShimmerUtilities.calculateTwosComplement(signedData: Int((Int(pressureResoRes[2]) + (Int(pressureResoRes[3]) << 8))), bitLength: 16))
            DIG_T3 = Double(ShimmerUtilities.calculateTwosComplement(signedData: Int((Int(pressureResoRes[4]) + (Int(pressureResoRes[5]) << 8))), bitLength: 16))
            DIG_P1 = Double((Int(pressureResoRes[6]) + (Int(pressureResoRes[7]) << 8)))
            DIG_P2 = Double(ShimmerUtilities.calculateTwosComplement(signedData: Int((Int(pressureResoRes[8]) + (Int(pressureResoRes[9]) << 8))), bitLength: 16))
            DIG_P3 = Double(ShimmerUtilities.calculateTwosComplement(signedData: Int((Int(pressureResoRes[10]) + (Int(pressureResoRes[11]) << 8))), bitLength: 16))
            DIG_P4 = Double(ShimmerUtilities.calculateTwosComplement(signedData: Int((Int(pressureResoRes[12]) + (Int(pressureResoRes[13]) << 8))), bitLength: 16))
            DIG_P5 = Double(ShimmerUtilities.calculateTwosComplement(signedData: Int((Int(pressureResoRes[14]) + (Int(pressureResoRes[15]) << 8))), bitLength: 16))
            DIG_P6 = Double(ShimmerUtilities.calculateTwosComplement(signedData: Int((Int(pressureResoRes[16]) + (Int(pressureResoRes[17]) << 8))), bitLength: 16))
            DIG_P7 = Double(ShimmerUtilities.calculateTwosComplement(signedData: Int((Int(pressureResoRes[18]) + (Int(pressureResoRes[19]) << 8))), bitLength: 16))
            DIG_P8 = Double(ShimmerUtilities.calculateTwosComplement(signedData: Int((Int(pressureResoRes[20]) + (Int(pressureResoRes[21]) << 8))), bitLength: 16))
            DIG_P9 = Double(ShimmerUtilities.calculateTwosComplement(signedData: Int((Int(pressureResoRes[22]) + (Int(pressureResoRes[23]) << 8))), bitLength: 16))
        }
    }
    
    /// Decodes the body of a 0xA6 reply, [len = 1 + n][sensorId][n coefficient bytes],
    /// with the ACK, response byte and CRC already removed.
    /// Returns nil when the sensor ID is unknown or len does not match it.
    public static func decodePressureCalibrationResponse(_ payload: [UInt8]) -> (sensorType: PressureSensorType, coefficients: [UInt8])? {
        guard payload.count >= 2, let sensorType = PressureSensorType(rawValue: payload[1]) else {
            return nil
        }
        let length = Int(payload[0])
        guard length == 1 + sensorType.calibrationByteCount, payload.count >= 1 + length else {
            return nil
        }
        return (sensorType, Array(payload[2..<(1 + length)]))
    }

    /// Stores the sensor type from a 0xA6 reply and parses its coefficients.
    /// Returns false, changing nothing, when the reply is malformed.
    public func applyPressureCalibrationResponse(_ payload: [UInt8]) -> Bool {
        guard let decoded = PressureTempSensor.decodePressureCalibrationResponse(payload) else {
            print("Invalid pressure calibration response: \(payload.map{ String(format: "%02X", $0) }.joined(separator: " "))")
            return false
        }
        pressureSensorType = decoded.sensorType
        print("Pressure sensor: \(decoded.sensorType)")
        if decoded.sensorType == .BMP390 {
            parseCalParamByteArray(pressureResoRes: payload)
        }
        // The BMP581 has no coefficients. BMP180/BMP280 coefficients are read with their own commands.
        return true
    }

    /// True when the expansion board SR number is one that carries the BMP581 on a Shimmer3R,
    /// following the firmware's ShimBrd_isBmp581PresentPerSrNumber(). ">=" compares rev, then special rev.
    public static func isBmp581PresentPerSrNumber(hardwareVersion: Int, expansionBoardId: Int, expansionBoardRev: Int, expansionBoardRevSpecial: Int) -> Bool {
        // An unprogrammed daughter card reads 0x00 or 0xFF
        if hardwareVersion != Shimmer3Protocol.HardwareType.Shimmer3R.rawValue
            || expansionBoardId == 0x00 || expansionBoardId == 0xFF {
            return false
        }
        func isSrNumberGte(_ id: Shimmer3Protocol.ExpansionBoardDetectShimmer3, _ rev: Int, _ revSpecial: Int) -> Bool {
            return expansionBoardId == id.rawValue
                && (expansionBoardRev > rev || (expansionBoardRev == rev && expansionBoardRevSpecial >= revSpecial))
        }
        // SR48 has two BMP581 ranges, 7.2 to 7.x and 8.2 onwards: SR48-8.0 and 8.1 are BMP390
        return isSrNumberGte(.SHIMMER3, 11, 2)
            || isSrNumberGte(.EXPANSION_PROTO3_DELUXE, 4, 2)
            || isSrNumberGte(.EXP_BRD_EXG_UNIFIED, 8, 2)
            || (isSrNumberGte(.EXP_BRD_GSR_UNIFIED, 7, 2) && !isSrNumberGte(.EXP_BRD_GSR_UNIFIED, 8, 0))
            || isSrNumberGte(.EXP_BRD_GSR_UNIFIED, 8, 2)
            || isSrNumberGte(.EXP_BRD_BR_AMP_UNIFIED, 4, 2)
    }

    /// True for LogAndStream v1.01.006 onwards, the first firmware that can drive a BMP581.
    public static func isBmp581SupportedByFirmware(firmwareIdentifier: Int, major: Int, minor: Int, internalVersion: Int) -> Bool {
        if firmwareIdentifier != PressureTempSensor.FW_ID_LOGANDSTREAM {
            return false
        }
        if major != 1 {
            return major > 1
        }
        if minor != 1 {
            return minor > 1
        }
        return internalVersion >= 6
    }

    /// BMP581 conversion: pressure is unsigned, Pa = raw / 64; temperature is signed, degC = raw / 65536.
    /// Returns (Pa, degC). No clamp is applied.
    public static func calibratePressure581(rawP: Int, rawT: Int) -> (Double, Double) {
        let pressurePa = Double(rawP & 0xFFFFFF) / 64.0
        let temperatureC = Double(signExtend24(rawT)) / 65536.0
        return (pressurePa, temperatureC)
    }

    /// Reads a 24-bit field as two's complement. Masks to 24 bits first, so an
    /// already sign-extended value passes through unchanged.
    public static func signExtend24(_ raw: Int) -> Int {
        let bits = raw & 0xFFFFFF
        return (bits & 0x800000) != 0 ? bits - 0x1000000 : bits
    }

    /// The 3-bit pressure resolution (oversampling) setting read from InfoMem.
    /// On a BMP581 it indexes ListOfPressureResolutionBMP581.
    public func getPressureResolutionIndex() -> Int {
        return pressureResolution
    }

    public func updateInfoMemPressureResolution(infomem: [UInt8],res: Resolution) -> [UInt8]{
        var infomemtoupdate = infomem
        print("oriinfomem: \(infomemtoupdate)")
        if(HardwareVersion == Shimmer3Protocol.HardwareType.Shimmer3.rawValue){
            var pressReso = 0
            if (res == Resolution.RES_LOW){
                pressReso = 0
            } else if (res == Resolution.RES_STANDARD){
                pressReso = 1
            } else if (res == Resolution.RES_HIGH){
                pressReso = 2
            } else if (res == Resolution.RES_ULTRAHIGH){
                pressReso = 3
            }
            let orivalue = infomemtoupdate[ConfigByteLayoutShimmer3.idxConfigSetupByte3]
            let value = infomemtoupdate[ConfigByteLayoutShimmer3.idxConfigSetupByte3] & ~UInt8(ConfigByteLayoutShimmer3.maskBMPX80PressureResolution<<ConfigByteLayoutShimmer3.bitShiftBMPX80PressureResolution)
            let resolution = UInt8(pressReso<<ConfigByteLayoutShimmer3.bitShiftBMPX80PressureResolution)
         
            print("orivalue range: \(orivalue)")
            print("value: \(value)")
            print("resolution: \(resolution)")

            infomemtoupdate[ConfigByteLayoutShimmer3.idxConfigSetupByte3] = value | resolution
            print("updatedinfomem: \(infomemtoupdate)")

        }
       return infomemtoupdate
        
       }
        
       public func getResolution()->Resolution{
           return CurrentResolution
       }
    
    public func setInfoMom(infomem: [UInt8]) {
        var enabled = Int(infomem[ConfigByteLayoutShimmer3.idxSensors2]>>2) & 1
        if (enabled == 1){
            sensorEnabled = true
        } else {
            sensorEnabled = false
        }
        pressureResolution = (Int(infomem[ConfigByteLayoutShimmer3.idxConfigSetupByte3]>>ConfigByteLayoutShimmer3.bitShiftBMPX80PressureResolution) & ConfigByteLayoutShimmer3.maskBMPX80PressureResolution)
        if (HardwareVersion == Shimmer3Protocol.HardwareType.Shimmer3R.rawValue && infomem.count > ConfigByteLayoutShimmer3.idxConfigSetupByte4){
            // The BMP390/BMP581 setting is 3 bits: its MSB is ConfigSetupByte4 bit 0
            let msb = Int(infomem[ConfigByteLayoutShimmer3.idxConfigSetupByte4]>>ConfigByteLayoutShimmer3.bitShiftBMP390PressureResolution) & ConfigByteLayoutShimmer3.maskBMP390PressureResolution
            pressureResolution = pressureResolution | (msb << 2)
        }
        
        if (pressureResolution == 0){
            CurrentResolution = Resolution.RES_LOW
        } else if (pressureResolution == 1){
            CurrentResolution = Resolution.RES_STANDARD
        } else if (pressureResolution == 2){
            CurrentResolution = Resolution.RES_HIGH
        } else if (pressureResolution == 3){
            CurrentResolution = Resolution.RES_ULTRAHIGH
        }
    }
    
    @inline(__always)
    func u24(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8) -> Int32 {
        return Int32(b2) << 16 | Int32(b1) << 8 | Int32(b0)
    }
    
    @inline(__always)
    private func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        return UInt16(b[i]) | (UInt16(b[i+1]) << 8)
    }

    @inline(__always)
    private func s16(_ b: [UInt8], _ i: Int) -> Int16 {
        return Int16(bitPattern: u16(b, i))
    }

    @inline(__always)
    private func u8(_ b: [UInt8], _ i: Int) -> UInt8 {
        return b[i]
    }

    @inline(__always)
    private func s8(_ b: [UInt8], _ i: Int) -> Int8 {
        return Int8(bitPattern: b[i])
    }
    
    func compensateBMP390_T(rawT: Int32) -> Double {

        let uncompTemp = Double(rawT)

        let partial1 = uncompTemp - par_T1
        let partial2 = partial1 * par_T2

        quantized_TLin = partial2 + partial1 * partial1 * par_T3

        // clamp like Java
        quantized_TLin = max(-40.0, min(85.0, quantized_TLin))

        return quantized_TLin
    }


    func compensateBMP390_P(rawP: Int32) -> Double {

        let UP = Double(rawP)
        let T = quantized_TLin

        // Direct port of Java:
        let part1 = par_P6 * T
        let part2 = par_P7 * (T * T)
        let part3 = par_P8 * (T * T * T)
        let out1 = par_P5 + part1 + part2 + part3

        let part4 = par_P2 * T
        let part5 = par_P3 * (T * T)
        let part6 = par_P4 * (T * T * T)
        let out2 = UP * (par_P1 + part4 + part5 + part6)

        let up2 = UP * UP
        let part7 = par_P9 + par_P10 * T
        let part8 = up2 * part7
        let part9 = (UP * UP * UP) * par_P11

        var pressure = out1 + out2 + part8 + part9

        // clamp like Java
        pressure = max(30000.0, min(125000.0, pressure))

        return pressure
    }

    func calibratePressure390(UP: Double, UT: Double) -> (Double, Double) {

        var partialT1 = UT - par_T1
        var partialT2 = partialT1 * par_T2

        quantized_TLin = partialT2 + (partialT1 * partialT1 * par_T3)

        // clamp
        if quantized_TLin < -40 { quantized_TLin = -40 }
        if quantized_TLin > 85 { quantized_TLin = 85 }

        let T = quantized_TLin

        // pressure
        let p1 = par_P6 * T
        let p2 = par_P7 * (T * T)
        let p3 = par_P8 * (T * T * T)
        let out1 = par_P5 + p1 + p2 + p3

        let q1 = par_P2 * T
        let q2 = par_P3 * (T * T)
        let q3 = par_P4 * (T * T * T)
        let out2 = UP * (par_P1 + q1 + q2 + q3)

        let up2 = UP * UP
        let r = up2 * (par_P9 + par_P10 * T)
        let s = (UP * UP * UP) * par_P11

        var pressure = out1 + out2 + r + s

        pressure = max(30000.0, min(125000.0, pressure))

        return (pressure, T)
    }


}
