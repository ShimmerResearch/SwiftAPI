import Foundation
import CoreBluetooth

public class BleByteRadio : NSObject, ByteCommunication {
   
    var RBL_SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    var RBL_CHAR_RX_UUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
    var RBL_CHAR_TX_UUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    private var bluetoothManager: BluetoothManager?
    public static let VERISENSE = "Verisense"
    public static let SHIMMER3 = "Shimmer3"
    public static let SHIMMER3R = "Shimmer3R"
    private var continuation: CheckedContinuation<Bool?, Never>?
    public static let VERISENSE_RBL_SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let VERISENSE_RBL_CHAR_RX_UUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let VERISENSE_RBL_CHAR_TX_UUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"

    public static let SHIMMER3_RBL_SERVICE_UUID = "49535343-FE7D-4AE5-8FA9-9FAFD205E455"
    public static let SHIMMER3_RBL_CHAR_RX_UUID = "49535343-1E4D-4BD9-BA61-23C647249616"
    public static let SHIMMER3_RBL_CHAR_TX_UUID = "49535343-8841-43F4-A8D4-ECBE34729BB3"
    
    public static let SHIMMER3R_RBL_SERVICE_UUID = "65333333-A115-11E2-9E9A-0800200CA100"
    public static let SHIMMER3R_RBL_CHAR_RX_UUID = "65333333-A115-11E2-9E9A-0800200CA102"
    public static let SHIMMER3R_RBL_CHAR_TX_UUID = "65333333-A115-11E2-9E9A-0800200CA101"
    
    
    public var deviceName: String?
    public var delegate: ByteCommunicationDelegate?

    private      var characteristics = [String : CBCharacteristic]()
    private      var data:             NSMutableData?
    private      var RSSICompletionHandler: ((NSNumber?, NSError?) -> ())?
    
    public       var activePeripheral: CBPeripheral?
    public private(set) var peripherals = [CBPeripheral]()
    
    public init(deviceName:String , cbperipheral:CBPeripheral, bluetoothManager:BluetoothManager) {
        super.init()
        self.deviceName = deviceName
        self.activePeripheral = cbperipheral
        self.bluetoothManager = bluetoothManager
        self.bluetoothManager!.delegates?[cbperipheral.name!] = self
        
        if let isActive = self.activePeripheral?.name?.contains(BleByteRadio.VERISENSE), isActive {
            RBL_SERVICE_UUID = BleByteRadio.VERISENSE_RBL_SERVICE_UUID
            RBL_CHAR_RX_UUID = BleByteRadio.VERISENSE_RBL_CHAR_RX_UUID
            RBL_CHAR_TX_UUID = BleByteRadio.VERISENSE_RBL_CHAR_TX_UUID
        } else if let isActive = self.activePeripheral?.name?.contains(BleByteRadio.SHIMMER3R), isActive {
            RBL_SERVICE_UUID = BleByteRadio.SHIMMER3R_RBL_SERVICE_UUID
            RBL_CHAR_RX_UUID = BleByteRadio.SHIMMER3R_RBL_CHAR_RX_UUID
            RBL_CHAR_TX_UUID = BleByteRadio.SHIMMER3R_RBL_CHAR_TX_UUID
        } else if let isActive = self.activePeripheral?.name?.contains(BleByteRadio.SHIMMER3), isActive {
            RBL_SERVICE_UUID = BleByteRadio.SHIMMER3_RBL_SERVICE_UUID
            RBL_CHAR_RX_UUID = BleByteRadio.SHIMMER3_RBL_CHAR_RX_UUID
            RBL_CHAR_TX_UUID = BleByteRadio.SHIMMER3_RBL_CHAR_TX_UUID
        }

        self.data = NSMutableData()
    }

    
    public func connect() async -> Bool? {
        // A connect CoreBluetooth failed or gave up on never reaches service discovery: return now
        // instead of waiting for characteristics that will not come.
        guard await self.bluetoothManager!.connect(activePeripheral: activePeripheral!) == true else {
            return false
        }
        
        /*
        if self.centralManager.state != .poweredOn {
            
            print("[ERROR] Couldn´t connect to peripheral")
            return false
        }
        
        print("[DEBUG] Connecting to peripheral: \(activePeripheral?.identifier.uuidString)")
        
        self.centralManager.connect(activePeripheral!, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey : NSNumber(value: true)])
        */
        var result = await withCheckedContinuation { continuation in
            if self.continuation == nil {
                // 2
                self.continuation = continuation
            }
        }
        
        return result
    }
    

    public func disconnect() async -> Bool? {
        return await self.bluetoothManager!.disconnect(activePeripheral: activePeripheral!)
    }
    
    public func read() {
        
        guard let char = self.characteristics[RBL_CHAR_TX_UUID] else { return }
        
        self.activePeripheral?.readValue(for: char)
    }
    
    public func writeBytes(bytes: [UInt8])->Bool {
        let data = Data(bytes)
        guard let char = self.characteristics[RBL_CHAR_TX_UUID] else { return false}
//        print("Write Data \(bytes)")
//        print(char.uuid.uuidString)
        self.activePeripheral?.writeValue(data, for: char, type: .withResponse)
        return true
    }
    
    public func writeData(data: Data) ->Bool {
        guard let char = self.characteristics[RBL_CHAR_TX_UUID] else { return false}
//        print("[DEBUG] Write Data \(data)")
//        print(char.uuid.uuidString)
        self.activePeripheral?.writeValue(data, for: char, type: .withResponse)
        return true
    }
    
    public func enableNotifications(enable: Bool) {
        
        guard let char = self.characteristics[RBL_CHAR_RX_UUID] else { return }
        print("Notifications Enabled")
        self.activePeripheral?.setNotifyValue(enable, for: char)
    }
}

extension BleByteRadio: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    }
    
    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        
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
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: NSError?) {
        print("[ERROR] Could not connecto to peripheral \(peripheral.identifier.uuidString) error: \(error!.description)")
        self.delegate?.byteCommunicationDisconnected(connectionloss: false)
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        print("[DEBUG] Connected to peripheral \(peripheral.identifier.uuidString)")
        
        self.activePeripheral = peripheral
        
        self.activePeripheral?.delegate = self
        self.activePeripheral?.discoverServices([CBUUID(string: RBL_SERVICE_UUID)])
        
       

    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        
        var text = "[DEBUG] Disconnected from peripheral: \(peripheral.identifier.uuidString)"
        
        if error != nil {
            //text += ". Error: \(error!.description)"
        }
        
        print(" \(text) \(activePeripheral?.name)")
        
        self.activePeripheral?.delegate = nil
        self.activePeripheral = nil
        self.characteristics.removeAll(keepingCapacity: false)
        
        self.delegate?.byteCommunicationDisconnected(connectionloss: false)
    }
}

extension BleByteRadio : BluetoothManagerDelegate{
    public func isDisconnected() {
        print("DISCONNECTED : \(activePeripheral!.name!)" )
        self.delegate?.byteCommunicationDisconnected(connectionloss: false)
    }
    
    public func scanCompleted() {
    
    }
    
    public func isConnected() {
        print("CONNECTED : \(activePeripheral!.name!)" )
        self.activePeripheral?.delegate = self
        self.activePeripheral?.discoverServices([CBUUID(string: RBL_SERVICE_UUID)])
    }
    
}

extension BleByteRadio : CBPeripheralDelegate {
    /*public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ){
        print("Discovered")
    }*/
    
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        
        if error != nil {
            print("[ERROR] Error discovering services.")
            return
        }
        
        print("[DEBUG] Found services for peripheral: \(peripheral.identifier.uuidString)")
        
        
        for service in peripheral.services! {
            let theCharacteristics = [CBUUID(string: RBL_CHAR_RX_UUID), CBUUID(string: RBL_CHAR_TX_UUID)]
            
            peripheral.discoverCharacteristics(theCharacteristics, for: service)
        }
    }
    /*
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ){
        print("disc char")
    }*/
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ){
        
        if error != nil {
            print("[ERROR] Error discovering characteristics.")
            return
        }
        
        print("[DEBUG] Found characteristics for peripheral: \(peripheral.identifier.uuidString)")
        
        for characteristic in service.characteristics! {
            self.characteristics[characteristic.uuid.uuidString] = characteristic
        }
        
        enableNotifications(enable: true)
        self.continuation?.resume(returning: true)
        self.continuation = nil
        self.delegate?.byteCommunicationConnected()
    }
    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ){
        //print("Updated")
    }
    /*public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ){
        print("RX")
    }*/
    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if error != nil {
            
            print("[ERROR] Error updating value.")
            return
        }
        
        if characteristic.uuid.uuidString == RBL_CHAR_RX_UUID {
            if let data = characteristic.value {
                //self.processData(data)
//                print(data)
                self.delegate?.byteCommunicationDataReceived(data: data, deviceName: (deviceName ?? ""))
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: NSError?) {
        self.RSSICompletionHandler?(RSSI, error)
        self.RSSICompletionHandler = nil
    }
}

