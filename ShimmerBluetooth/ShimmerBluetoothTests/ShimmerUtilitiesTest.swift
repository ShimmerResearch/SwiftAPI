//
//  ShimmerUtilitiesTest.swift
//  ShimmerBluetoothTests
//
//  Created by Shimmer Engineering on 20/11/2023.
//

import XCTest
@testable import ShimmerBluetooth

class ShimmerUtilitiesTest: XCTestCase {
    
    func testCalculateOnesComplement() {
        XCTAssertEqual(ShimmerUtilities.calculateOnesComplement(of: 5, bitWidth: 8), 0b11111010)
        XCTAssertEqual(ShimmerUtilities.calculateOnesComplement(of: 0, bitWidth: 8), 0b11111111)
        XCTAssertEqual(ShimmerUtilities.calculateOnesComplement(of: 1, bitWidth: 8), 0b11111110)
        XCTAssertEqual(ShimmerUtilities.calculateOnesComplement(of: 5, bitWidth: 4), 0b1010)
        XCTAssertEqual(ShimmerUtilities.calculateOnesComplement(of: 0, bitWidth: 4), 0b1111)
    }
    
    func testCalculateTwosComplement() {
        XCTAssertEqual(ShimmerUtilities.calculateTwosComplement(signedData: 14, bitLength: 8), 14, "Incorrect two's complement")
        XCTAssertEqual(ShimmerUtilities.calculateTwosComplement(signedData: 7, bitLength: 3), -1, "Incorrect two's complement")
        XCTAssertEqual(ShimmerUtilities.calculateTwosComplement(signedData: 0b1000, bitLength: 4), -8, "Incorrect two's complement")
        XCTAssertEqual(ShimmerUtilities.calculateTwosComplement(signedData: 7, bitLength: 4), 7, "Incorrect two's complement")
    }
    
    func testParseSensorDataForU8() {
        // Given
        let sensorData: [UInt8] = [127] // Example sensor data
        let dataType = SensorDataType.u8
        
        // When
        let result = ShimmerUtilities.parseSensorData(sensorData: sensorData, dataType: dataType)
        
        // Then
        XCTAssertEqual(result, 127, "Failed to parse sensor data for 'u8'")
    }
    
    func testParseSensorDataForI8() {
        // Given
        let sensorData: [UInt8] = [255] // Example sensor data for the value -1 in two's complement
        let dataType = SensorDataType.i8
        
        // When
        let result = ShimmerUtilities.parseSensorData(sensorData: sensorData, dataType: dataType)
        
        // Then
        XCTAssertEqual(result, -1, "Failed to parse sensor data for 'i8'")
    }
    
    func testParseSensorDataForU12() {
        // Given
        let sensorData: [UInt8] = [0xFF, 0x0F] // Example sensor data for a 12-bit unsigned value (4095)
        let dataType: SensorDataType = .u12
        
        // When
        let result = ShimmerUtilities.parseSensorData(sensorData: sensorData, dataType: dataType)
        
        // Then
        XCTAssertEqual(result, 4095, "Failed to parse sensor data for 'u12'")
    }
    
    func testParseSensorDataForU16() {
        // Given
        let sensorData: [UInt8] = [0x12, 0x34] // Example sensor data for a 16-bit unsigned value (0x3412 = 13330)
        let dataType: SensorDataType = .u16
        
        // When
        let result = ShimmerUtilities.parseSensorData(sensorData: sensorData, dataType: dataType)
        
        // Then
        XCTAssertEqual(result, 13330, "Failed to parse sensor data for 'u16'")
    }
    
    func testParseSensorDataForU16MSB() {
        // Given
        let sensorData: [UInt8] = [0x34, 0x12] // Example sensor data for a 16-bit unsigned value with MSB byte order (0x1234 = 4660)
        let dataType: SensorDataType = .u16MSB
        
        // When
        let result = ShimmerUtilities.parseSensorData(sensorData: sensorData, dataType: dataType)
        
        // Then
        XCTAssertEqual(result, 13330, "Failed to parse sensor data for 'u16MSB'")
    }
    
    func testProcessSensorDataForI16() {
        // Given
        let sensorData: [UInt8] = [0xFF, 0xFF] // Example sensor data for a signed 16-bit value (-1)
        let dataType: SensorDataType = .i16
        
        // When
        let result = ShimmerUtilities.parseSensorData(sensorData: sensorData, dataType: dataType)
        // Then
        XCTAssertEqual(result, -1, "Failed to process sensor data for 'i16'")
    }
    
    func testIntToUInt8Conversion() {
        let testCases: [(input: Int, expectedOutput: [UInt8])] = [
            (input: 0, expectedOutput: [0,0,0,0,0, 0, 0, 0]),
            (input: 255, expectedOutput: [0,0,0,0,0, 0, 0, 255]),
            (input: 511, expectedOutput: [0,0,0,0,0, 0, 1, 255]),
            (input: 1234567890, expectedOutput: [0,0,0,0,73, 150, 2, 210])
            // Add more test cases as needed
        ]

        for testCase in testCases {
            let result = ShimmerUtilities.intToUInt8Array(testCase.input)
            assert(result == testCase.expectedOutput, "Test failed for input \(testCase.input)")
        }

        print("All tests passed successfully.")
    }
    
    func testProcessSensorDataForI16_2() {
        // Given
        let sensorData: [UInt8] = [0x00, 0x80] // Example sensor data for a signed 16-bit value (-1)
        let dataType: SensorDataType = .i16
        
        // When
        let result = ShimmerUtilities.parseSensorData(sensorData: sensorData, dataType: dataType)
        // Then
        XCTAssertEqual(result, -32768, "Failed to process sensor data for 'i16'")
    }
    
    func testU24Conversion() {
        let data: [UInt8] = [0xAB, 0xCD, 0xEF] // Example data for u24 type
        let dataType = SensorDataType.u24
        let result = ShimmerUtilities.parseSensorData(sensorData: data,dataType: dataType)
        
        XCTAssertEqual(result, 0xEFCDAB) // Provide the expected value after conversion
    }
    
    func testParseSensorDataForU24MSB() {
        // Given
        let sensorData: [UInt8] = [0xAB, 0xCD, 0xEF] // Example data for u24msb type
        let dataType: SensorDataType = .u24MSB
        
        // When
        let result = ShimmerUtilities.parseSensorData(sensorData: sensorData, dataType: dataType)
        
        // Then
        XCTAssertEqual(result, 0xABCDEF, "Failed to parse sensor data for 'u24MSB'")
    }
    
    func testParseSensorDataForI24MSB() {
        // Given
        let sensorData: [UInt8] = [0xAB, 0xCD, 0xEF] // Example data for u24msb type
        let dataType: SensorDataType = .i24MSB
        
        // When
        let result = ShimmerUtilities.parseSensorData(sensorData: sensorData, dataType: dataType)
        
        // Then
        XCTAssertEqual(result, -5517841, "Failed to parse sensor data for 'i24MSB'")
    }
    
    func testMatrixSubtraction() {
            let matrixA: [[Double]] = [
                [1, 2],
                [3, 4]
            ]
            
            let matrixB: [[Double]] = [
                [5, 6],
                [7, 8]
            ]
            
            let expectedResult: [[Double]] = [
                [-4, -4],
                [-4, -4]
            ]
            
            guard let result = ShimmerUtilities.matrixMinus(matrixA, matrixB) else {
                XCTFail("Matrices have incompatible dimensions")
                return
            }
            
            XCTAssertEqual(result, expectedResult, "Matrix subtraction result is incorrect")
        }
    
    func testMatrixSubtraction2() {
            let matrixA: [[Double]] = [
                [1],
                [3],
                [4],
            ]
            
            let matrixB: [[Double]] = [
                 [1],
                 [3],
                 [4],
            ]
            
            let expectedResult: [[Double]] = [
                [0],
                [0],
                [0],
            ]
            
            guard let result = ShimmerUtilities.matrixMinus(matrixA, matrixB) else {
                XCTFail("Matrices have incompatible dimensions")
                return
            }
            
            XCTAssertEqual(result, expectedResult, "Matrix subtraction result is incorrect")
        }
    
    func testMatrixMultiplication() {
            let matrixA: [[Double]] = [
                [1, 2, 3],
                [4, 5, 6]
            ]
            
            let matrixB: [[Double]] = [
                [7, 8],
                [9, 10],
                [11, 12]
            ]
            
            let expectedResult: [[Double]] = [
                [58, 64],
                [139, 154]
            ]
            
        guard let result = ShimmerUtilities.matrixMultiplication(matrixA, matrixB) else {
                XCTFail("Matrices cannot be multiplied")
                return
            }
            
            XCTAssertEqual(result, expectedResult, "Matrix multiplication result is incorrect")
        }
    
    
    func testDivideMatrixElements() {
            let originalMatrix: [[Double]] = [
                [10, 20, 30],
                [40, 50, 60],
                [70, 80, 90]
            ]
            
            let divisor: Double = 5.0
            
            let expectedResult: [[Double]] = [
                [2, 4, 6],
                [8, 10, 12],
                [14, 16, 18]
            ]
            
        let dividedMatrix = ShimmerUtilities.divideMatrixElements(originalMatrix, divisor)
            
            XCTAssertEqual(dividedMatrix, expectedResult, "Matrix elements were not divided as expected")
        }
    
    func testMatrixInverse() {
            let inputMatrix: [[Double]] = [
                [4, 7, 3],
                [2, 6, 1],
                [5, 9, 8]
            ]
            
            let expectedResult: [[Double]] = [
                [0.907, -0.674, -0.256],
                [-0.256, 0.395, 0.047],
                [-0.279, -0.023, 0.233]
            ]
            
        guard let result = ShimmerUtilities.matrixInverse3x3(inputMatrix) else {
                XCTFail("Invalid input matrix or matrix is not invertible")
                return
            }
            
            for i in 0..<3 {
                for j in 0..<3 {
                    XCTAssertEqual(result[i][j], expectedResult[i][j], accuracy: 0.001, "Matrix inversion result is incorrect")
                }
            }
        }
    
    func testShimmerUartCrcCalcMatchesTheFirmwareReference() {
        // [LSB, MSB] from log-and-stream-common Extras/python_scripts/Shimmer_common/shimmer_crc.py
        XCTAssertEqual(ShimmerUtilities.shimmerUartCrcCalc([0xFF], 1), [0xF4, 0x65], "a bare ACK, odd length so padded")
        XCTAssertEqual(ShimmerUtilities.shimmerUartCrcCalc([0xFE], 1), [0xC5, 0x56], "a bare NACK")
        XCTAssertEqual(ShimmerUtilities.shimmerUartCrcCalc([0xFF, 0x8A, 0x71, 0x31], 4), [0xC5, 0xBA], "even length, not padded")
        XCTAssertEqual(ShimmerUtilities.shimmerUartCrcCalc([0xFF, 0x8A, 0x71, 0x31, 0x01], 5), [0x1E, 0x4B])
        XCTAssertEqual(ShimmerUtilities.shimmerUartCrcCalc([0x8A, 0x71, 0x31], 3), [0xE8, 0x7C])
        XCTAssertEqual(ShimmerUtilities.shimmerUartCrcCalc([0x8A, 0x71, 0x31, 0x01], 4), [0xC9, 0x6C])
        XCTAssertEqual(ShimmerUtilities.shimmerUartCrcCalc([0xFF, 0x8A, 0x71, 0x52, 0xAA], 4), [0x00, 0xE6], "only the first len bytes count")
    }

}
