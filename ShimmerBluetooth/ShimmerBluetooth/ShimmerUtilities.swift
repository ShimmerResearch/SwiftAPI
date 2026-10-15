//
//  ShimmerUtilities.swift
//  ShimmerBluetooth
//
//  Created by Shimmer Engineering on 20/11/2023.
//

import Foundation

public class ShimmerUtilities{
    
    public static func calculateTwosComplement(signedData: Int,bitLength: Int) -> Int {
        let maxValue = 1 << (bitLength - 1)
        
        if signedData >= maxValue {
            return signedData - (1 << bitLength)
        } else {
            return signedData
        }
    }

    public static func calculateOnesComplement(of number: Int, bitWidth: Int) -> Int {
        // Calculate the mask based on the bit width
        let mask = (1 << bitWidth) - 1
        
        // Calculate the one's complement
        let onesComplement = ~number & mask
        
        // Return the result masked to the bit width
        return onesComplement
    }
    
    public static func divideMatrixElements(_ matrix: [[Double]], _ value: Double) -> [[Double]] {
        var result = matrix
        
        for i in 0..<matrix.count {
            for j in 0..<matrix[i].count {
                result[i][j] /= value
            }
        }
        
        return result
    }
    
    public static func matrixMultiplication(_ a: [[Double]], _ b: [[Double]]) -> [[Double]]? {
        let aRows = a.count
        let aColumns = a[0].count
        let bRows = b.count
        let bColumns = b[0].count
        
        // Check if matrix multiplication is possible
        guard aColumns == bRows else {
            return nil // Matrices cannot be multiplied
        }
        
        var resultant = Array(repeating: Array(repeating: 0.0, count: bColumns), count: aRows)
        
        for i in 0..<aRows {
            for j in 0..<bColumns {
                for k in 0..<aColumns {
                    resultant[i][j] += a[i][k] * b[k][j]
                }
            }
        }
        
        return resultant
    }
    
    public static func matrixInverse3x3(_ data: [[Double]]) -> [[Double]]? {
        guard data.count == 3 && data[0].count == 3 && data[1].count == 3 && data[2].count == 3 else {
            return nil // Invalid matrix size
        }
        
        let a = data[0][0]
        let b = data[0][1]
        let c = data[0][2]
        let d = data[1][0]
        let e = data[1][1]
        let f = data[1][2]
        let g = data[2][0]
        let h = data[2][1]
        let i = data[2][2]
        
        let deter = a * e * i + b * f * g + c * d * h - c * e * g - b * d * i - a * f * h
        
        guard deter != 0 else {
            return nil // Determinant is zero, matrix is not invertible
        }
        
        let invDeter = 1.0 / deter
        
        var answer = Array(repeating: Array(repeating: 0.0, count: 3), count: 3)
        
        answer[0][0] = invDeter * (e * i - f * h)
        answer[0][1] = invDeter * (c * h - b * i)
        answer[0][2] = invDeter * (b * f - c * e)
        answer[1][0] = invDeter * (f * g - d * i)
        answer[1][1] = invDeter * (a * i - c * g)
        answer[1][2] = invDeter * (c * d - a * f)
        answer[2][0] = invDeter * (d * h - e * g)
        answer[2][1] = invDeter * (g * b - a * h)
        answer[2][2] = invDeter * (a * e - b * d)
        
        return answer
    }
    
    public static func matrixMinus(_ a: [[Double]], _ b: [[Double]]) -> [[Double]]? {
        let aRows = a.count
        let aColumns = a[0].count
        let bRows = b.count
        let bColumns = b[0].count
        
        // Check if matrices have compatible dimensions for subtraction
        if aRows != bRows || aColumns != bColumns {
            return nil // Matrices have incompatible dimensions
        }
        
        var resultant = Array(repeating: Array(repeating: 0.0, count: aColumns), count: aRows)
        
        for i in 0..<aRows {
            for k in 0..<aColumns {
                resultant[i][k] = a[i][k] - b[i][k]
            }
        }
        
        return resultant
    }
    
    public static func intToUInt8Array(_ value: Int) -> [UInt8] {
        var intValue = value
        let size = MemoryLayout<Int>.size
        let byteMask: UInt8 = 255 // 0xFF
        
        var byteArray = [UInt8]()
        byteArray.reserveCapacity(size)

        for _ in 0..<size {
            let byte = UInt8(intValue & Int(byteMask))
            byteArray.insert(byte, at: 0)
            intValue >>= 8
        }

        return byteArray
    }
    
    public static func parseSensorData(sensorData : [UInt8],dataType : SensorDataType) -> Int?{
        if dataType == SensorDataType.u8 {
            return Int(sensorData[0])
        } else if dataType == SensorDataType.i8 {
            return calculateTwosComplement(signedData: Int(sensorData[0]), bitLength: 8)
        } else if dataType == SensorDataType.u12 {
            return Int((Int(sensorData[0]) + (Int(sensorData[1]) << 8)))
        } else if dataType == SensorDataType.u16 {
            return Int((Int(sensorData[0]) + (Int(sensorData[1]) << 8)))
        } else if dataType == SensorDataType.u16MSB {
            return Int((Int(sensorData[1]) + (Int(sensorData[0]) << 8)))
        } else if dataType == SensorDataType.i16 {
            return calculateTwosComplement(signedData: Int((Int(sensorData[0]) + (Int(sensorData[1]) << 8))), bitLength: 16)
        } else if dataType == SensorDataType.i16MSB {
            return calculateTwosComplement(signedData: Int((Int(sensorData[1]) + (Int(sensorData[0]) << 8))), bitLength: 16)
        } else if dataType ==  SensorDataType.u24 {
            let xmsb = Int(sensorData[2] & 0xFF) << 16
            let msb = Int(sensorData[1] & 0xFF) << 8
            let lsb = Int(sensorData[0] & 0xFF)
            return (xmsb + msb + lsb)
        }else if dataType ==  SensorDataType.u24MSB {
            let xmsb = Int(sensorData[0] & 0xFF) << 16
            let msb = Int(sensorData[1] & 0xFF) << 8
            let lsb = Int(sensorData[2] & 0xFF)
            return (xmsb + msb + lsb)
        }else if dataType == SensorDataType.i24MSB{
            let xmsb = Int(sensorData[0] & 0xFF) << 16
            let msb = Int(sensorData[1] & 0xFF) << 8
            let lsb = Int(sensorData[2] & 0xFF)
            return calculateTwosComplement(signedData: (Int(xmsb + msb + lsb)), bitLength: 24)
        }else if dataType == SensorDataType.i12MSB{
            return calculateTwosComplement(signedData: Int(Int(sensorData[0] & 0xFF) << 4 | Int(sensorData[1] & 0xFF) >> 4), bitLength: 12)
        }
        
        return nil
    }
    
    public static func isAllFF(_ bytes: [UInt8]) -> Bool {
        return bytes.allSatisfy { $0 == 0xFF }
    }
     
    public static func isAllZeros(_ bytes: [UInt8]) -> Bool {
        return bytes.allSatisfy { $0 == 0x00 }
    }

    /// The Bluetooth link CRC over `msg[0..<len]`: a CRC-16 seeded with 0xB0CA, an odd length padded
    /// with one 0x00 that is not sent. Returns [LSB, MSB]; a 1-byte CRC is the LSB alone.
    /// log-and-stream-common `docs/SHIMMER3_BT_COMMUNICATION_PROTOCOL.md` §3.3, and its reference
    /// `Extras/python_scripts/Shimmer_common/shimmer_crc.py`.
    public static func shimmerUartCrcCalc(_ msg: [UInt8], _ len: Int) -> [UInt8] {
        let CRC_INIT: Int = 0xB0CA
        var crcCalc = shimmerUartCrcByte(CRC_INIT, msg[0])
        var i = 1

        while i < len {
            crcCalc = shimmerUartCrcByte(crcCalc, msg[i])
            i += 1
        }

        if len % 2 > 0 {
            crcCalc = shimmerUartCrcByte(crcCalc, 0x00)
        }

        let crcCalcArray: [UInt8] = [
            UInt8(crcCalc & 0xFF),    // CRC LSB
            UInt8((crcCalc >> 8) & 0xFF)   // CRC MSB
        ]

        return crcCalcArray
    }

    static func shimmerUartCrcByte(_ crc: Int, _ b: UInt8) -> Int {
        var crcValue = crc & 0xFFFF
        crcValue = (crcValue >> 8) | (crcValue << 8)
        crcValue ^= Int(b) & 0xFF
        crcValue ^= (crcValue & 0xFF) >> 4
        crcValue ^= crcValue << 12
        crcValue ^= (crcValue & 0xFF) << 5
        crcValue &= 0xFFFF
        return crcValue
    }
}
