//
//  ShimmerBluetoothTests.swift
//  ShimmerBluetoothTests
//
//  Created by Shimmer Engineering on 19/10/2023.
//

import XCTest
@testable import ShimmerBluetooth

class ShimmerBluetoothTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

    func testStrongestSafeCRCMode() {
        func mode(_ hardware: Int, _ firmwareIdentifier: Int, _ major: Int, _ minor: Int, _ fwInternal: Int) -> Shimmer3Protocol.BTCRCMode {
            return Shimmer3Protocol.strongestSafeCRCMode(hardwareVersion: hardware, firmwareIdentifier: firmwareIdentifier, firmwareMajor: major, firmwareMinor: minor, firmwareInternal: fwInternal)
        }
        let shimmer3 = Shimmer3Protocol.HardwareType.Shimmer3.rawValue
        let shimmer3R = Shimmer3Protocol.HardwareType.Shimmer3R.rawValue
        let logAndStream = Shimmer3Protocol.FW_IDENTIFIER_LOGANDSTREAM

        // Shimmer3R LogAndStream before v1.00.011 turns the CRC off whenever sensing stops.
        XCTAssertEqual(mode(shimmer3R, logAndStream, 0, 0, 2), .OFF)
        XCTAssertEqual(mode(shimmer3R, logAndStream, 0, 0, 30), .OFF, "major 0 is before v1.00.011, whatever the internal number")
        XCTAssertEqual(mode(shimmer3R, logAndStream, 1, 0, 10), .OFF)
        // From v1.00.011 the CRC survives a stop, and until v1.00.024 the push has one status byte, so two CRC bytes fit.
        XCTAssertEqual(mode(shimmer3R, logAndStream, 1, 0, 11), .TWO_BYTE)
        XCTAssertEqual(mode(shimmer3R, logAndStream, 1, 0, 23), .TWO_BYTE)
        // v1.00.024 to v1.00.049: two status bytes in a six-byte push leave room for one CRC byte (DEV-621).
        XCTAssertEqual(mode(shimmer3R, logAndStream, 1, 0, 24), .ONE_BYTE)
        XCTAssertEqual(mode(shimmer3R, logAndStream, 1, 0, 49), .ONE_BYTE)
        // v1.00.050 made room for two.
        XCTAssertEqual(mode(shimmer3R, logAndStream, 1, 0, 50), .TWO_BYTE)
        XCTAssertEqual(mode(shimmer3R, logAndStream, 1, 1, 30), .TWO_BYTE, "minor 1 is after v1.00.049, whatever the internal number")
        // Shimmer3 version numbers overlap both ranges, and no Shimmer3 release has either problem.
        XCTAssertEqual(mode(shimmer3, logAndStream, 1, 0, 10), .TWO_BYTE)
        XCTAssertEqual(mode(shimmer3, logAndStream, 1, 0, 30), .TWO_BYTE)
        // Firmware other than LogAndStream (1 is BtStream) keeps the 2-byte CRC it always had.
        XCTAssertEqual(mode(shimmer3R, 1, 1, 0, 30), .TWO_BYTE)
        // No CRC until both versions have been read.
        XCTAssertEqual(mode(-1, logAndStream, 1, 0, 30), .OFF)
        XCTAssertEqual(mode(shimmer3R, -1, -1, -1, -1), .OFF)
    }
    

    

}
