//
//  ConfigByteLayoutShimmer3.swift
//  ShimmerBluetooth
//
//  Created by Shimmer Engineering on 02/11/2023.
//

import Foundation

public class ConfigByteLayoutShimmer3{
    static let idxShimmerSamplingRate = 0
    static let idxBufferSize = 2
    public static let idxSensors0 = 3
    public static let idxSensors1 = 4
    public static let idxSensors2 = 5
    static let idxConfigSetupByte0 = 6
    static let idxConfigSetupByte1 = 7
    static let idxConfigSetupByte2 = 8
    static let idxConfigSetupByte3 = 9
    static let idxEXGADS1292RChip1Config1 = 10
    static let idxEXGADS1292RChip1Config2 = 11
    static let idxEXGADS1292RChip1LOff = 12
    static let idxEXGADS1292RChip1Ch1Set = 13
    static let idxEXGADS1292RChip1Ch2Set = 14
    static let idxEXGADS1292RChip1RldSens = 15
    static let idxEXGADS1292RChip1LOffSens = 16
    static let idxEXGADS1292RChip1LOffStat = 17
    static let idxEXGADS1292RChip1Resp1 = 18
    static let idxEXGADS1292RChip1Resp2 = 19
    static let idxEXGADS1292RChip2Config1 = 20
    static let idxEXGADS1292RChip2Config2 = 21
    static let idxEXGADS1292RChip2LOff = 22
    static let idxEXGADS1292RChip2Ch1Set = 23
    static let idxEXGADS1292RChip2Ch2Set = 24
    static let idxEXGADS1292RChip2RldSens = 25
    static let idxEXGADS1292RChip2LOffSens = 26
    static let idxEXGADS1292RChip2LOffStat = 27
    static let idxEXGADS1292RChip2Resp1 = 28
    static let idxEXGADS1292RChip2Resp2 = 29
    static let idxBtCommBaudRate = 30
    static let idxAnalogAccelCalibration = 31
    static let idxMPU9150GyroCalibration = 52
    static let idxLSM303DLHCMagCalibration = 76
    static let idxLIS3MDLAltMagCalibration = 285

    //static let idxLSM303DLHCAccelCalibration = 94 //94->114
    static let idxConfigSetupByte4 = 128+2;

    static let idxSDExperimentConfig0 =             128+89;
    static let idxSDExperimentConfig1 =             128+90;
    
    static let bitShiftGSRRange =                       1;
    static let maskGSRRange =                           0x07;
    
    static let bitShiftMPU9150GyroRange =               0;
    static let maskMPU9150GyroRange =                   0x03;
    
    static let bitShiftLSM6DSVyroRangeMSB =               2;
    static let maskLSM6DSVyroRangeMSB =                   0x01;
    
    static let bitShiftMPU9150AccelGyroSamplingRate =               0;
    static let maskMPU9150AccelGyroSamplingRate =                   0xFF;
    
    static let bitShiftLSM303DLHCAccelRange =            2;
    static let maskLSM303DLHCAccelRange =               0x03;
    
    static let bitShiftBMPX80PressureResolution =       4;
    static let maskBMPX80PressureResolution =           0x03;

    static let bitShiftBMP390PressureResolution =       0;
    static let maskBMP390PressureResolution =           0x01;
    
    static let bitShiftLSM303DLHCMagRange =            5;
    static let maskLSM303DLHCMagRange =               0x07;
    
    static let bitShiftMPU9150AccelRange =            6;
    static let maskMPU9150AccelRange =               0x03;
    
    static let bitShiftLSM303DLHCMagSamplingRate =         2;
    static let maskLSM303DLHCMagSamplingRate =          0x07;
    
    static let bitShiftLSM303DLHCAccelSamplingRate =         4;
    static let maskLSM303DLHCAccelSamplingRate =          0x0F;
    
    static let idxLSM6DSVAccelCalibration = 34;
    static let idxGyroCalibration = 55;
    static let idxLSM303DLHCAccelCalibration = 97;
    
    static let lengthGeneralCalibrationBytes = 21;
    
    static let bitShiftRTCError = 4;
    static let maskRTCError = 1;
}
