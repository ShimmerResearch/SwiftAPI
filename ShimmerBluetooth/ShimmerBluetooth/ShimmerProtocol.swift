//
//  ShimmerProtocol.swift
//  ShimmerBluetooth
//
//  Created by Shimmer Engineering on 24/10/2023.
//

import Foundation

public protocol ShimmerProtocol{
    
    var REV_HW_MAJOR:Int {get set}
    var REV_HW_MINOR:Int {get set}
    var REV_FW_MAJOR:Int {get set}
    var REV_FW_MINOR:Int {get set}
    
    func connect() async ->Bool;
    func disconnect() async ->Bool;
    
}
public protocol ShimmerProtocolDelegate {
    func shimmerProtocolNewMessage(message:String)
    func shimmerProtocolNewObjectCluster(message:ObjectCluster)
    func shimmerBTStateChange(message:Shimmer3Protocol.Shimmer3BTState)
    /// A status the device pushed unasked: it was docked or undocked, its button was pressed, or a
    /// trial duration or low battery stopped it.
    func shimmerProtocolNewDeviceStatus(message:Shimmer3DeviceStatus)
}
public extension ShimmerProtocolDelegate {
    /// Optional: a delegate written before status pushes were handled goes on compiling, and ignores them.
    func shimmerProtocolNewDeviceStatus(message:Shimmer3DeviceStatus) {}
}
