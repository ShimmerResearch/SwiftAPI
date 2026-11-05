//
//  BluetoothManager.swift
//  ShimmerBluetooth
//
//  Created by Shimmer Engineering on 19/10/2023.
//
import CoreBluetooth
import Foundation

public protocol BluetoothManagerDelegate {
    func scanCompleted()
    func isConnected()
    func isDisconnected()
}

public class BluetoothManager: NSObject {
    private      var centralManager:   CBCentralManager!
    public private(set) var peripherals = [CBPeripheral]()
    public var delegate: BluetoothManagerDelegate?
    public var delegates: [String: BluetoothManagerDelegate?]? = [:]
    var timer: Timer?
    var deviceName: String = ""
    private var continuation: CheckedContinuation<Bool?, Never>?
    
    public func sayHello(){
        print("Hello from BluetoothManager")
    }
    
    public init(centralmanager:CBCentralManager) {
        super.init()
        self.centralManager = centralmanager
        self.centralManager.delegate = self
    }
    
    @objc private func scanTimeout() {
        print("[DEBUG] Scanning stopped")
        self.centralManager.stopScan()
        self.delegate?.scanCompleted()
    }
        
    public func startScanning(uuid:String, timeout: Double) -> Bool {
        deviceName = ""
        if self.centralManager.state != .poweredOn {
            
            print("[ERROR] Couldn´t start scanning")
            return false
        }
        
        print("[DEBUG] Scanning started")
        
        // CBCentralManagerScanOptionAllowDuplicatesKey
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(timeInterval: timeout, target: self, selector: #selector(BluetoothManager.scanTimeout), userInfo: nil, repeats: false)
        }
        self.centralManager.scanForPeripherals(withServices: [CBUUID(string: uuid)], options: nil)
        //self.centralManager.scanForPeripherals(withServices: nil, options: nil)
        print(self.centralManager.isScanning)
        return true
    }
    
    public func startScanning(timeout: Double) -> Bool {
        deviceName = ""
        if self.centralManager.state != .poweredOn {
            
            print("[ERROR] Couldn´t start scanning")
            return false
        }
        
        print("[DEBUG] Scanning started")
        
        // CBCentralManagerScanOptionAllowDuplicatesKey
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(timeInterval: timeout, target: self, selector: #selector(BluetoothManager.scanTimeout), userInfo: nil, repeats: false)
        }
        //self.centralManager.scanForPeripherals(withServices: [CBUUID(string: uuid)], options: nil)
        self.centralManager.scanForPeripherals(withServices: nil, options: nil)
        print(self.centralManager.isScanning)
        return true
    }
    
    public func startScanning(deviceName:String,timeout: Double) -> Bool {
        self.deviceName = deviceName
        if self.centralManager.state != .poweredOn {
            
            print("[ERROR] Couldn´t start scanning")
            return false
        }
        
        print("[DEBUG] Scanning started")
        
        // CBCentralManagerScanOptionAllowDuplicatesKey
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(timeInterval: timeout, target: self, selector: #selector(BluetoothManager.scanTimeout), userInfo: nil, repeats: false)
        }
        //self.centralManager.scanForPeripherals(withServices: [CBUUID(string: uuid)], options: nil)
        self.centralManager.scanForPeripherals(withServices: nil, options: nil)
        print(self.centralManager.isScanning)
        return true
    }
    
    public func connect(activePeripheral:CBPeripheral) async -> Bool? {
        
        if self.centralManager.state != .poweredOn {
            
            print("[ERROR] Couldn´t connect to peripheral")
            return false
        }
        
        print("[DEBUG] Connecting to peripheral: \(activePeripheral.identifier.uuidString)")
        
        self.centralManager.connect(activePeripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey : NSNumber(value: true)])
        return await withCheckedContinuation { continuation in
            // A connect that never completed (CoreBluetooth never times one out) is given up on
            // here, so it cannot take this attempt's didConnect.
            self.continuation?.resume(returning: false)
            self.continuation = continuation
        }
    }
    
    public func disconnect(activePeripheral:CBPeripheral) async -> Bool? {
        
        if self.centralManager.state != .poweredOn {
            
            print("[ERROR] Couldn´t disconnect from peripheral")
            return false
        }
        
        self.centralManager.cancelPeripheralConnection(activePeripheral)
        
        return true
    }
    
    
    
    public func getDiscoveredPeripherals() -> [CBPeripheral] {
        return peripherals
    }
    
    public func getPeripheral(deviceName:String) -> CBPeripheral? {
        for peripheral in peripherals {
            if peripheral.name == deviceName {
                return peripheral
            }
        }
        return nil
    }
}
extension BluetoothManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print(central.state)
        print(central.isScanning)
    }
    
    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        print("[DEBUG] Find device : \(peripheral.identifier.uuidString) RSSI: \(RSSI)")
        print("Found", peripheral.name ?? "Unknown")
            let index = peripherals.firstIndex(where: { $0.identifier.uuidString == peripheral.identifier.uuidString })
        
            if let index = index {
                peripherals[index] = peripheral
            } else {
                peripherals.append(peripheral)
            }
        if(peripheral.name==deviceName){
            print("[DEBUG] Scanning stopped")
            self.centralManager.stopScan()
            self.delegate?.scanCompleted()
            timer?.invalidate()
        }
    }
     
    /*
    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ){
        print(peripheral.name)
    }*/
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[ERROR] Could not connecto to peripheral \(peripheral.identifier.uuidString)")
        self.continuation?.resume(returning: false)
        self.continuation = nil
        let pname = peripheral.name
        delegates![pname!]!?.isDisconnected()
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connect received from BluetoothManager")
        self.continuation?.resume(returning: true)
        self.continuation = nil
        let pname = peripheral.name
        delegates![pname!]!?.isConnected()
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnect received from BluetoothManager")
        let pname = peripheral.name
        delegates![pname!]!?.isDisconnected()
    }
}
