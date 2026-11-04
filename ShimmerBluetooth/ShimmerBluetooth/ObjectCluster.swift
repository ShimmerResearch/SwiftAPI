//
//  ObjectCluster.swift
//  ShimmerBluetooth
//
//  Created by Shimmer Engineering on 17/11/2023.
//

import Foundation

public class ObjectCluster {
    var DeviceName = ""
    public var SignalNames : [String] = []
    public var SignalData : [Double] = []
    let Seperator = "_"
    public var PacketReceptionRate = -1
    /// False when the packet carried no usable timestamp - see
    /// `TimestampUnwrap`. The sensor values on this cluster are real; only its
    /// time is missing, and the Time Stamp signals repeat the previous
    /// packet's. Drop the cluster if you need a true time axis.
    public var timestampValid = true
    public func addData(sensorName:String,formatName:String,unitName:String,value:Double){
        let newName = [sensorName,Seperator,formatName,Seperator,unitName].joined()
        SignalNames.append(newName)
        SignalData.append(value)
    }
        
    public init(deviceName:String){
        DeviceName = deviceName
    }
    
}
