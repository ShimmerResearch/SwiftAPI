import Combine
import CoreBluetooth
import ShimmerBluetooth
//let radio = BLEByteRadio(deviceType: DeviceType.verisense, deviceName: "Verisense-21082701B799")
//private let radio = BleByteRadio(deviceName: "Verisense-21082701B799")

enum EXGMode: String, CaseIterable, Identifiable {
    case none = "None"
    case ecg = "ECG"
    case emg = "EMG"
    case exgTest = "EXG Test"
    var id: String { self.rawValue }
}

private var pendingData=[Data]()
@available(macOS 10.15, *)
@MainActor
class ViewModel: NSObject, ObservableObject {

    enum PPGInputOption: String, CaseIterable {
        case intA1 = "Int A1"
        case intA0 = "Int A0"

        var sensorBitmap: UInt32 {
            switch self {
            case .intA1:
                return Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_INT_A1.rawValue
            case .intA0:
                return Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_INT_A0.rawValue
            }
        }
    }

    private var radio: BleByteRadio?
    public var shimmer3Protocol: Shimmer3Protocol?
    private var shimmer3SpeedTestProtocol: Shimmer3SpeedTestProtocol?
    private var bluetoothManager: BluetoothManager?
    private var centralManager: CBCentralManager?
    public var signal1 : [Double] = []
    public var signal2 : [Double] = []
    public var signal3 : [Double] = []
    @Published var pickerData = ["No Signal"]
    @Published var pickerProtocol = ["LogAndStream","SpeedTest"]
    @Published var pickerDevices = ["Please scan"]
    @Published var lnAccelRange = ["2G", "4G", "8G", "16G"]
    @Published var wrRange = ["2G", "4G", "8G", "16G"]
    @Published var gyroRange = ["250DPS", "500DPS", "1000DPS", "2000DPS"]
    @Published var altMagRange3R = ["4Ga", "8Ga", "12Ga", "16Ga"]
    @Published var gyroRange3R = ["125DPS","250DPS", "500DPS", "1000DPS", "2000DPS","4000DPS"]
    @Published var exgGain = ["1", "2", "3", "4", "6", "8", "12"]
    @Published var exgResolution = ["16 BIT", "24 BIT"]
    @Published var pressResolution = ["LOW", "STANDARD", "HIGH", "ULTRAHIGH"]
    @Published var samplingRate = ["1Hz", "10.2Hz", "51.2Hz", "102.4Hz", "204.8Hz", "256Hz", "512Hz", "1024Hz"]
    @Published var stateText = "Disconnected"
    @Published var crcModes = ["Off", "1 Byte", "2 Byte"]
    @Published var crcModeIndex = 2 // Initial value, matches the API default (TWO_BYTE)
    @Published var currentCRCModeText = "-"
    @Published var packetReceptionRate = -1
    @Published var ppgInputOptions = PPGInputOption.allCases.map(\.rawValue)
    @Published var ppgInputSelectionIndex = 0
    @Published var lnAccelEnabled = false
    @Published var magEnabled = false
    @Published var gyroEnabled = false
    @Published var wrAccelEnabled = false
    @Published var altMagEnabled = false
    @Published var highGAccelEnabled = false
    @Published var gsrPpgEnabled = false
    @Published var exgMode: EXGMode = .none
    @Published var isSensorCommandInFlight = false
    private var updatedPicker = false;
    public var delegate: ViewModelDelegate?
    var count = 1
    @Published var lnAccelRangeIndex = 0 // Initial value
    @Published var wrRangeIndex = 0 // Initial value
    @Published var gyroRangeIndex = 0 // Initial value
    @Published var gyroRange3RIndex = 0 // Initial value
    @Published var pressResIndex = 0 // Initial value
    @Published var exgGainIndex = 0 // Initial value
    @Published var exgResIndex = 0 // Initial value
    @Published var samplingRateIndex = 0 // Initial value
    @Published var altMagRange3RIndex = 0 // Initial value
    public var startIndex = 0
    public var protocolShimmer3 = 0
    public var numberOfSignals = 1
    public var deviceIndex = 0
    private var currentShimmer3RSensorBitmap: UInt32?
    var signal1Label: String {
        return pickerData.indices.contains(startIndex) ? pickerData[startIndex] : "Value1"
    }
    var signal2Label: String {
        return pickerData.indices.contains(startIndex+1) ? pickerData[startIndex+1] : "Value2"
    }
    var signal3Label: String {
        return pickerData.indices.contains(startIndex+2) ? pickerData[startIndex+2] : "Value3"
    }
    
    @Published var isScanning = false
    public override init() {
        super.init()
        self.centralManager = CBCentralManager()//(delegate: self, queue: nil)
        //self.radio = BleByteRadio(deviceName: "Verisense-21082701B799",cbcentralmanager: centralManager!)
        self.bluetoothManager = BluetoothManager(centralmanager: self.centralManager!)
        bluetoothManager?.delegate = self
        //radio.delegate = self
    }
    func test(){
        //let printer = Test()
        //let printer = BluetoothManager()
        //printer.sayHello();
        
        
        //radio.startScanningAndConnectifFound(timeout: 20000)
        //820702820702radio!.startScanning(timeout: 20000)
        bluetoothManager?.startScanning(uuid: BleByteRadio.VERISENSE_RBL_SERVICE_UUID, timeout: 2)
        
        
    }
    
    private func applyShimmer3RSensorBitmap(_ sensorBitmap: UInt32) async {
        currentShimmer3RSensorBitmap = sensorBitmap
        await shimmer3Protocol?.sendSetSensorsCommand(sensorBitmap: sensorBitmap)
        refreshUISettings()
    }
    
    func scanShimmer3(){
        //bluetoothManager?.startScanning(deviceName: "Shimmer3-3E36",timeout: 10)
        pickerDevices = ["Scanning"]
        bluetoothManager?.startScanning(timeout: 3)
    }
    
    func refreshUISettings(){
        lnAccelRangeIndex = Int((shimmer3Protocol?.lnAccelSensor.getRange().rawValue)!)
        wrRangeIndex = Int((shimmer3Protocol?.wrAccelSensor.getRange().rawValue)!)
        gyroRangeIndex = Int((shimmer3Protocol?.gyroSensor.getRange().rawValue)!)
        gyroRange3RIndex = Int((shimmer3Protocol?.gyroSensor.get3RRange().rawValue)!)
        pressResIndex = Int((shimmer3Protocol?.pressureTempSensor.getResolution().rawValue)!)
        exgGainIndex = Int((shimmer3Protocol?.exgSensor.getGain().rawValue)!)
        exgResIndex = Int((shimmer3Protocol?.exgSensor.getResolution().rawValue)!)
        samplingRateIndex = Int((shimmer3Protocol?.getSamplingRateIndex())!)
        altMagRange3RIndex = Int((shimmer3Protocol?.altMagSensor.get3RRange().rawValue)!)
     
        // Sync checkbox state from the device's actual current sensor-enabled bitmap
        lnAccelEnabled = shimmer3Protocol?.lnAccelSensor.sensorEnabled ?? false
        magEnabled = shimmer3Protocol?.magSensor.sensorEnabled ?? false
        gyroEnabled = shimmer3Protocol?.gyroSensor.sensorEnabled ?? false
        wrAccelEnabled = shimmer3Protocol?.wrAccelSensor.sensorEnabled ?? false
        altMagEnabled = shimmer3Protocol?.altMagSensor.sensorEnabled ?? false
        highGAccelEnabled = shimmer3Protocol?.highGAccelSensor.sensorEnabled ?? false
        gsrPpgEnabled = shimmer3Protocol?.gsrSensor.sensorEnabled ?? false
     
        self.updatedPicker = false
    }
    
    func connectDev2() async{
        let deviceName = pickerDevices[deviceIndex]
        guard let peripheral = bluetoothManager?.getPeripheral(deviceName: deviceName) else {
            print("[ERROR] No scanned peripheral found for device name: \(deviceName)")
            return
        }
        self.radio = BleByteRadio(deviceName: deviceName,cbperipheral: peripheral,bluetoothManager: bluetoothManager!)
        if (protocolShimmer3==0){
            shimmer3Protocol = Shimmer3Protocol(radio: self.radio!)
            shimmer3Protocol?.delegate = self
            await shimmer3Protocol?.connect()
            refreshCRCModeText()
            refreshUISettings()
        } else {
            shimmer3SpeedTestProtocol = Shimmer3SpeedTestProtocol(radio: self.radio!)
            //shimmer3SpeedTestProtocol?.delegate = self
            await shimmer3SpeedTestProtocol?.connect()
            shimmer3SpeedTestProtocol?.startSpeedTest()
        }
    
    }
    private func selectedCRCMode() -> Shimmer3Protocol.BTCRCMode {
        return Shimmer3Protocol.BTCRCMode(rawValue: UInt8(crcModeIndex)) ?? .TWO_BYTE
    }
    
    func refreshCRCModeText() {
        guard let mode = shimmer3Protocol?.getCRCMode() else {
            currentCRCModeText = "-"
            return
        }
        currentCRCModeText = crcModes[Int(mode.rawValue)]
    }
    
    func setCRCModeDev2() async {
        isSensorCommandInFlight = true
        let ok = await shimmer3Protocol?.setCRCMode(selectedCRCMode()) ?? false
        print("Set CRC mode \(selectedCRCMode()) result: \(ok)")
        refreshCRCModeText()
        isSensorCommandInFlight = false
    }
    
    func disconnectDev2() async{
        if (shimmer3Protocol==nil){
            await shimmer3SpeedTestProtocol!.disconnect()
        } else {
            await shimmer3Protocol!.disconnect()
        }
    }
    
    func sendInquiryCommandDev2() async {
        
    }
    
    func sendStartStreamingCommandDev2() async {
        isSensorCommandInFlight = true
        await shimmer3Protocol?.sendStartStreamingCommand()
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        isSensorCommandInFlight = false
    }
     
    func sendStopStreamingCommandDev2() async {
        isSensorCommandInFlight = true
        _ = await shimmer3Protocol?.sendStopStreamingCommand()
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        isSensorCommandInFlight = false
    }
    
    func sendS3InfoMemConfigUpdate() async {
        var infomem =  shimmer3Protocol?.getInfoMemByteArray()
        
        if(shimmer3Protocol?.wrAccelSensor.sensorEnabled != false){
            let wrAccel = shimmer3Protocol?.wrAccelSensor
            infomem = wrAccel?.updateInfoMemAccelRange(infomem: infomem!, range: WRAccelSensor.Range.fromValue(UInt8(wrRangeIndex))!)
        }
        
        if(shimmer3Protocol?.gyroSensor.sensorEnabled != false){
            let gyro = shimmer3Protocol?.gyroSensor
            infomem = gyro?.updateInfoMemGyroRange(infomem: infomem!, range: GyroSensor.Range.fromValue(UInt8(gyroRangeIndex))!)
        }
        if(shimmer3Protocol?.pressureTempSensor.sensorEnabled != false){
            let press = shimmer3Protocol?.pressureTempSensor
            infomem = press?.updateInfoMemPressureResolution(infomem: infomem!, res: PressureTempSensor.Resolution.fromValue(UInt8(pressResIndex))!)
        }
        
        if(shimmer3Protocol?.exgSensor.sensorEnabled != false){
            infomem = shimmer3Protocol?.exgSensor.updateInfoMemExgGain(infomem: infomem!, gain: EXGSensor.Gain.fromValue(UInt8(exgGainIndex))!)
            infomem = shimmer3Protocol?.exgSensor.updateInfoMemExgResolution(infomem: infomem!, resolution: EXGSensor.Resolution.fromValue(UInt8(exgResIndex))!)
        }
         
        await shimmer3Protocol?.writeShimmer3InfoMem(infoMem: infomem!)
        //refreshUISettings()
    }
    
    func sendS3RInfoMemConfigUpdate() async {
        var infomem = shimmer3Protocol?.getInfoMemByteArray()
        guard infomem != nil else { return }

        if let lnAccel = shimmer3Protocol?.lnAccelSensor,
           let range = LNAccelSensor.Range.fromValue(UInt8(lnAccelRangeIndex)) {
            infomem = lnAccel.updateInfoMemLNAccelRange(infomem: infomem!, range: range)
        }

        if let mag = shimmer3Protocol?.altMagSensor,
           let range = AltMagSensor.Range3R.fromValue(UInt8(altMagRange3RIndex)) {
            infomem = mag.updateInfoMem3RAltMagRange(infomem: infomem!, range: range)
        }

        if let gyro = shimmer3Protocol?.gyroSensor,
           let range = GyroSensor.Range3R.fromValue(UInt8(gyroRange3RIndex)) {
            infomem = gyro.updateInfoMem3RGyroRange(infomem: infomem!, range: range)
        }

        if let wrAccel = shimmer3Protocol?.wrAccelSensor,
           let range = WRAccelSensor.Range.fromValue(UInt8(wrRangeIndex)) {
            infomem = wrAccel.updateInfoMemAccelRange(infomem: infomem!, range: range)
        }

        await shimmer3Protocol?.writeShimmer3InfoMem(infoMem: infomem!)

        if let sensorBitmap = currentShimmer3RSensorBitmap {
            await shimmer3Protocol?.sendSetSensorsCommand(sensorBitmap: sensorBitmap)

            if (sensorBitmap & Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_GSR.rawValue) != 0 &&
               ((sensorBitmap & Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_INT_A1.rawValue) != 0 ||
                (sensorBitmap & Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_INT_A0.rawValue) != 0) {
                await shimmer3Protocol?.sendInternalExpPower(1)
            }
        }

        refreshUISettings()
    }
    
    func sendInfoMemSamplingRate() async {
        var infomem =  shimmer3Protocol?.getInfoMemByteArray()
        var samplingRate = Shimmer3Protocol.SamplingRate.fromValue(Double(samplingRateIndex))?.rawValue

        infomem = shimmer3Protocol?.updateInfoMemSamplingRate(infomem: infomem!,samplingRateFreq: samplingRate!)
        infomem = shimmer3Protocol?.exgSensor.updateInfoMemExgRate(infomem: infomem!,samplingRateFreq: samplingRate!)
        let updatedSensors = shimmer3Protocol?.isShimmer3withUpdatedSensors()
        var mag = shimmer3Protocol?.magSensor
        infomem = mag?.setLowPowerMag(enable:false, isShimmer3withUpdatedSensors: updatedSensors!, isShimmer3Sensor: (shimmer3Protocol?.isShimmer3Sensor())!, samplingRate: samplingRate!, infomem: infomem!)

        var wrAccel = shimmer3Protocol?.wrAccelSensor
        infomem = wrAccel?.setLowPowerWRAccel(enable:false, isShimmer3withUpdatedSensors: updatedSensors!, samplingRate: samplingRate!, infomem: infomem!)
        
        var gyro = shimmer3Protocol?.gyroSensor
        infomem = gyro?.setLowPowerGyro(enable:false, samplingRate: samplingRate!, infomem: infomem!)
        await shimmer3Protocol?.writeShimmer3InfoMem(infoMem: infomem!)

    }
    
    func setShimmerSamplingRate() async{
        var samplingRate = Shimmer3Protocol.SamplingRate.fromValue(Double(samplingRateIndex))?.rawValue

        await shimmer3Protocol?.sendSetSamplingRateCommand(samplingRate: samplingRate!)
        let buff = (shimmer3Protocol?.exgSensor.updateExgRateConfig(samplingRateFreq: samplingRate!))!
        shimmer3Protocol?.writeExgRate(exgArr:buff)
    }
    
    func sendInfoMemIMU() async{
        let infomwracc:[UInt8] = [ 0x80,0x02,0x01,0xE0,0x20,0x00,0x01,0x9B,0x0D,0x08,0x00,0x80,0x10,0x00,0x00,0x00,0x00,0x00,0x02,0x01,0x00,0x80,0x10,0x00,0x00,0x00,0x00,0x00,0x02,0x01,0x09,0x00,0x00,0x00,0x08,0xCD,0x08,0xCD,0x08,0xCD,0x00,0x5C,0x00,0x5C,0x00,0x5C,0x00,0x9C,0x00,0x9C,0x00,0x00,0x00,0x00,0x9C,0x00,0x00,0x00,0x00,0x00,0x00,0x19,0x96,0x19,0x96,0x19,0x96,0x00,0x9C,0x00,0x9C,0x00,0x00,0x00,0x00,0x9C,0x00,0x00,0x00,0x00,0x00,0x00,0x02,0x9B,0x02,0x9B,0x02,0x9B,0x00,0x9C,0x00,0x64,0x00,0x00,0x00,0x00,0x9C,0x00,0x00,0x00,0x00,0x00,0x00,0x06,0x87,0x06,0x87,0x06,0x87,0x00,0x9C,0x00,0x64,0x00,0x00,0x00,0x00,0x9C,0x00,0x00,0x00,0x00,0x00,0x00,0x02,0x01,0x00,0x80,0x10,0x00,0x00,0x00,0x00,0x00,0x02,0x01,0x09,0x00,0x00,0x00,0x08,0xCD,0x08,0xCD,0x08,0xCD,0x00,0x5C,0x00,0x5C,0x00,0x5C,0x00,0x9C,0x00,0x9C,0x00,0x00,0x00,0x00,0x9C,0x00,0x00,0x00,0x00,0x00,0x00,0x19,0x96,0x19,0x96,0x19,0x96,0x00,0x9C,0x00,0x9C,0x00,0x00,0x00,0x00,0x9C,0x00,0x00,0x00,0x00,0x00,0x00,0x02,0x9B,0x02,0x9B,0x02,0x9B,0x00,0x9C,0x00,0x64,0x00,0x00,0x00,0x00,0x9C,0x00,0x00,0x00,0x00,0x00,0x00,0x06,0x87,0x06,0x87,0x06,0x87,0x00,0x9C,0x00,0x64,0x00,0x00,0x00,0x00,0x9C,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00]
        await shimmer3Protocol?.writeShimmer3InfoMem(infoMem: infomwracc)
        refreshUISettings()
    }
    
    var isShimmerConnected: Bool {
        return stateText == "Connected" || stateText == "Configuring" || stateText == "Streaming"
    }
    
    func enableS3RAltMag() async{
        await applyShimmer3RSensorBitmap(
            Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_ALT_MAG.rawValue
        )
    }
    
    func enableS3RHighGAccel() async{
        await applyShimmer3RSensorBitmap(
            Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_HIGHG_ACCEL.rawValue
        )
    }
    
    func enableS3RLNAccel() async{
        await applyShimmer3RSensorBitmap(
            Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_LN_ACCEL.rawValue
        )
    }
    
    func enableS3RMag() async{
        await applyShimmer3RSensorBitmap(
            Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_MAG.rawValue
        )
    }
    
    func enableS3RGyro() async{
        await applyShimmer3RSensorBitmap(
            Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_GYRO.rawValue
        )
    }
 
    func enableS3RWRAccel() async{
        await applyShimmer3RSensorBitmap(
            Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_WR_ACCEL.rawValue
        )
    }

    func enableS3RPPG() async{
        let ppgInput = selectedPPGInputOption()
        let bitmap =
            Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_GSR.rawValue |
            ppgInput.sensorBitmap
        currentShimmer3RSensorBitmap = bitmap
        await shimmer3Protocol?.sendSetSensorsCommand(sensorBitmap: bitmap)
        await shimmer3Protocol?.sendInternalExpPower(1)
        refreshUISettings()
    }
    
    func configureShimmer3R() async {
        isSensorCommandInFlight = true
            guard let shimmer3Protocol = shimmer3Protocol else {
                isSensorCommandInFlight = false
                return
            }
        
        var bitmap: UInt32 = 0
        if lnAccelEnabled   { bitmap |= Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_LN_ACCEL.rawValue }
        if magEnabled       { bitmap |= Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_MAG.rawValue }
        if gyroEnabled      { bitmap |= Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_GYRO.rawValue }
        if wrAccelEnabled   { bitmap |= Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_WR_ACCEL.rawValue }
        if altMagEnabled    { bitmap |= Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_ALT_MAG.rawValue }
        if highGAccelEnabled{ bitmap |= Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_HIGHG_ACCEL.rawValue }
        if gsrPpgEnabled {
            let ppgInput = selectedPPGInputOption()
            bitmap |= Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_GSR.rawValue | ppgInput.sensorBitmap
        }
        // Consensys's isEXGUsingDefaultEMGConfiguration() requires chip1 enabled
        // and chip2 DISABLED (mIsExg1_24bitEnabled && !mIsExg2_24bitEnabled) — unlike
        // ECG/Test which require both chips enabled. Enabling EXG2 for EMG makes
        // Consensys's detection gate fail and fall back to "Custom".
        switch exgMode {
        case .ecg, .exgTest:
            bitmap |= Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_EXG1_24BIT.rawValue |
                      Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_EXG2_24BIT.rawValue
        case .emg:
            bitmap |= Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_EXG1_24BIT.rawValue
        case .none:
            break
        }
        currentShimmer3RSensorBitmap = bitmap
     
        // Range settings via InfoMem write — do this FIRST
        var infomem = shimmer3Protocol.getInfoMemByteArray()
        
        infomem[ConfigByteLayoutShimmer3.idxSensors0] = UInt8(bitmap & 0xFF)
        infomem[ConfigByteLayoutShimmer3.idxSensors1] = UInt8((bitmap >> 8) & 0xFF)
        infomem[ConfigByteLayoutShimmer3.idxSensors2] = UInt8((bitmap >> 16) & 0xFF)
        
        if let range = LNAccelSensor.Range.fromValue(UInt8(lnAccelRangeIndex)) {
            infomem = shimmer3Protocol.lnAccelSensor.updateInfoMemLNAccelRange(infomem: infomem, range: range)
        }
        if let range = AltMagSensor.Range3R.fromValue(UInt8(altMagRange3RIndex)) {
            infomem = shimmer3Protocol.altMagSensor.updateInfoMem3RAltMagRange(infomem: infomem, range: range)
        }
        if let range = GyroSensor.Range3R.fromValue(UInt8(gyroRange3RIndex)) {
            infomem = shimmer3Protocol.gyroSensor.updateInfoMem3RGyroRange(infomem: infomem, range: range)
        }
        if let range = WRAccelSensor.Range.fromValue(UInt8(wrRangeIndex)) {
            infomem = shimmer3Protocol.wrAccelSensor.updateInfoMemAccelRange(infomem: infomem, range: range)
        }

        // Mirror the EXG chip register config into InfoMem too, so a device read-back
        // (e.g. from Consensys) sees the same registers as what's live on the chips —
        // otherwise InfoMem keeps a stale/default EXG config that matches no known mode.
        var exgChip1: [UInt8]? = nil
        var exgChip2: [UInt8]? = nil
        switch exgMode {
        case .exgTest:
            exgChip1 = Shimmer3Protocol.Shimmer3Configuration.EXG_TEST_SIGNAL_CONFIGURATION_CHIP1
            exgChip2 = Shimmer3Protocol.Shimmer3Configuration.EXG_TEST_SIGNAL_CONFIGURATION_CHIP2
        case .ecg:
            exgChip1 = Shimmer3Protocol.Shimmer3Configuration.EXG_ECG_CONFIGURATION_CHIP1
            exgChip2 = Shimmer3Protocol.Shimmer3Configuration.EXG_ECG_CONFIGURATION_CHIP2
        case .emg:
            exgChip1 = Shimmer3Protocol.Shimmer3Configuration.EXG_EMG_CONFIGURATION_CHIP1
            exgChip2 = Shimmer3Protocol.Shimmer3Configuration.EXG_EMG_CONFIGURATION_CHIP2
        case .none:
            break
        }
        if let exgChip1, let exgChip2 {
            infomem = shimmer3Protocol.exgSensor.updateInfoMemExgChipConfig(infomem: infomem, chip1: exgChip1, chip2: exgChip2)
        }

        await shimmer3Protocol.writeShimmer3InfoMem(infoMem: infomem)

        // EXG chip config — moved to AFTER the InfoMem write, so its internal
        // setEXGArray() call is the last thing to touch CurrentEXGMode
        if let exgChip1, let exgChip2 {
            await shimmer3Protocol.sendSetEXGConfigurations(valuesChip1: exgChip1, valuesChip2: exgChip2)
        }
     
        // Sensor enable bitmap
        await shimmer3Protocol.sendSetSensorsCommand(sensorBitmap: bitmap)
     
        // Internal ADC power for GSR+PPG combos that use internal ADC channels
        if (bitmap & Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_GSR.rawValue) != 0 &&
           ((bitmap & Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_INT_A1.rawValue) != 0 ||
            (bitmap & Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_INT_A0.rawValue) != 0) {
            await shimmer3Protocol.sendInternalExpPower(1)
        }
     
        // Sampling rate
        await setShimmerSamplingRate()
     
        refreshUISettings()
        
        try? await Task.sleep(nanoseconds: 1500_000_000)
        isSensorCommandInFlight = false
    }

    private func selectedPPGInputOption() -> PPGInputOption {
        guard ppgInputSelectionIndex >= 0 && ppgInputSelectionIndex < PPGInputOption.allCases.count else {
            return .intA1
        }
        return PPGInputOption.allCases[ppgInputSelectionIndex]
    }
    
     func enableEXGTest() async{
         await shimmer3Protocol?.sendSetEXGConfigurations(valuesChip1: Shimmer3Protocol.Shimmer3Configuration.EXG_TEST_SIGNAL_CONFIGURATION_CHIP1, valuesChip2: Shimmer3Protocol.Shimmer3Configuration.EXG_TEST_SIGNAL_CONFIGURATION_CHIP2)
        let bitmap =
             Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_EXG1_24BIT.rawValue |
             Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_EXG2_24BIT.rawValue
        await shimmer3Protocol?.sendSetSensorsCommand(sensorBitmap: bitmap);
        refreshUISettings()
    }

    func enableECG() async{
        await shimmer3Protocol?.sendSetEXGConfigurations(valuesChip1: Shimmer3Protocol.Shimmer3Configuration.EXG_ECG_CONFIGURATION_CHIP1, valuesChip2: Shimmer3Protocol.Shimmer3Configuration.EXG_ECG_CONFIGURATION_CHIP2)
       let bitmap =
            Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_EXG1_24BIT.rawValue |
            Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_EXG2_24BIT.rawValue
       await shimmer3Protocol?.sendSetSensorsCommand(sensorBitmap: bitmap);
       refreshUISettings()
   }
    
    func enableEMG() async{
        await shimmer3Protocol?.sendSetEXGConfigurations(valuesChip1: Shimmer3Protocol.Shimmer3Configuration.EXG_EMG_CONFIGURATION_CHIP1, valuesChip2: Shimmer3Protocol.Shimmer3Configuration.EXG_EMG_CONFIGURATION_CHIP2)
       let bitmap =
            Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_EXG1_24BIT.rawValue |
            Shimmer3Protocol.SensorBitmapShimmer3.SENSOR_EXG2_24BIT.rawValue
       await shimmer3Protocol?.sendSetSensorsCommand(sensorBitmap: bitmap);
       refreshUISettings()
   }
    
    func sendInfoMemWRAccel() async{
        let infomwracc:[UInt8] = [ 0x80,0x02,0x01,0x00,0x10,0x00,0x41,0xFF,0x01,0x08,0x00,0x80,0x10,0x00,0x00,0x00,0x00,0x00,0x02,0x01,0x00,0x80,0x10,0x00,0x00,0x00,0x00,0x00,0x02,0x01,0x09,0x00,0x00,0x00,0x08,0xCD,0x08,0xCD,0x08,0xCD,0x00,0x5C,0x00,0x5C,0x00,0x5C,0x00,0x9C,0x00,0x9C,0x00,0x00,0x00,0x00,0x9C,0x00,0x00,0x00,0x00,0x00,0x00,0x19,0x96,0x19,0x96,0x19,0x96,0x00,0x9C,0x00,0x9C,0x00,0x00,0x00,0x00,0x9C,0x00,0x00,0x00,0x00,0x00,0x00,0x02,0x9B,0x02,0x9B,0x02,0x9B,0x00,0x9C,0x00,0x64,0x00,0x00,0x00,0x00,0x9C,0x00,0x00,0x00,0x00,0x00,0x00,0x06,0x87,0x06,0x87,0x06,0x87,0x00,0x9C,0x00,0x64,0x00,0x00,0x00,0x00,0x9C,0x00,0x00,0x00,0x00,0x00,0x00]
        await shimmer3Protocol?.writeShimmer3InfoMem(infoMem: infomwracc)
        refreshUISettings()
    }
    
    func sendInfoMemGyro() async{
        let infomgyro:[UInt8] = [ 0x20, 0x00, 0x01, 0x40, 0x00, 0x00, 0x01, 0x06, 0x01, 0x08, 0x04, 0x88, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x01, 0x04, 0x80, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00]
        await shimmer3Protocol?.writeShimmer3InfoMem(infoMem: infomgyro)
        refreshUISettings()
    }
   
    func sendInfoMemPPGGSR() async{
        let infomppggsr:[UInt8] = [0x80,0x02,0x01,0x04,0x01,0x00,0x01,0xFF,0x21,0x09,0x00,0x80,0x10,0x00,0x00,0x00,0x00,0x00,0x02,0x01,0x00,0x80,0x10,0x00,0x00,0x00,0x00,0x00,0x02,0x01,0x09,0x04]
        await shimmer3Protocol?.writeShimmer3InfoMem(infoMem: infomppggsr)
        refreshUISettings()
    }
    
    func sendInfoMemECG24Bit() async{
        //shimmer3Protocol?.exgSensor.resetEXG()
        let infomexg:[UInt8] = [0x80, 0x02, 0x01, 0x18, 0x00, 0x00, 0x01, 0xFF, 0x01, 0x09, 0x00, 0xA8, 0x10, 0x40, 0x40, 0x2D, 0x00, 0x00, 0x02, 0x03, 0x00, 0xA0, 0x10, 0x40, 0x47, 0x00, 0x00, 0x00, 0x02, 0x01]
        await shimmer3Protocol?.writeShimmer3InfoMem(infoMem: infomexg)
        refreshUISettings()
    }
    func sendInfoMemECG16Bit() async{
        //shimmer3Protocol?.exgSensor.resetEXG()
        let infomexg:[UInt8] = [0x80, 0x02, 0x01, 0x00, 0x00, 0x18, 0x01, 0xFF, 0x01, 0x09, 0x00, 0xA8, 0x10, 0x40, 0x40, 0x2D, 0x00, 0x00, 0x02, 0x03, 0x00, 0xA0, 0x10, 0x40, 0x47, 0x00, 0x00, 0x00, 0x02, 0x01]
        await shimmer3Protocol?.writeShimmer3InfoMem(infoMem: infomexg)
        refreshUISettings()
    }
    
    func sendInfoMemEMG() async{
        //shimmer3Protocol?.exgSensor.resetEXG()
        let infomemg:[UInt8] = [0x80, 0x02, 0x01, 0x10, 0x00, 0x00, 0x01, 0xFF, 0x01, 0x09, 0x00, 0xA8, 0x10, 0x69, 0x60, 0x20, 0x00, 0x00, 0x02, 0x03, 0x00, 0xA0, 0x10, 0xE1, 0xE1, 0x00, 0x00, 0x00, 0x02, 0x01]
        await shimmer3Protocol?.writeShimmer3InfoMem(infoMem: infomemg)
        refreshUISettings()
    }
                                
    func sendInfoMemEXGTest() async{
        //shimmer3Protocol?.exgSensor.resetEXG()
        let infomexgtest:[UInt8] = [0x80, 0x02, 0x01, 0x18, 0x00, 0x00, 0x01, 0xFF, 0x01, 0x09, 0x00, 0xAB, 0x10, 0x15, 0x15, 0x00, 0x00, 0x00, 0x02, 0x01, 0x00, 0xA3, 0x10, 0x15, 0x15, 0x00, 0x00, 0x00, 0x02, 0x01]
        await shimmer3Protocol?.writeShimmer3InfoMem(infoMem: infomexgtest)
        refreshUISettings()
    }
        
    func sendInfoMemRespiration() async{
        //shimmer3Protocol?.exgSensor.resetEXG()
        let infomresp:[UInt8] = [0x80, 0x02, 0x01, 0x18, 0x00, 0x00, 0x01, 0xFF, 0x01, 0x09, 0x00, 0xA8, 0x10, 0x40, 0x40, 0x20, 0x00, 0x00, 0x02, 0x03, 0x00, 0xA0, 0x10, 0x40, 0x40, 0x00, 0x00, 0x00, 0x02, 0x01]
        await shimmer3Protocol?.writeShimmer3InfoMem(infoMem: infomresp)
        refreshUISettings()
    }
    
    func sendInfoMemPressureAndTemperature() async{
        let infompressuretemp:[UInt8] = [0x80, 0x02, 0x01, 0x00, 0x00, 0x04, 0x01, 0xFF, 0x01, 0x08, 0x00, 0x88, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x01]
        await shimmer3Protocol?.writeShimmer3InfoMem(infoMem: infompressuretemp)
        refreshUISettings()
    }
    
    func sendInfoMemBattery() async{
        let infombatt:[UInt8] = [0x80, 0x02, 0x01, 0x00, 0x20, 0x00, 0x01, 0xFF, 0x01, 0x08, 0x00, 0x88, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x01]
        await shimmer3Protocol?.writeShimmer3InfoMem(infoMem: infombatt)
        refreshUISettings()
    }
    
    
    func sendReadStatusCommand() {
    }
    
}
extension ViewModel : BluetoothManagerDelegate{
    func scanCompleted() {
        print("Bluetooth Manager Scan Completed")
        self.pickerDevices = (bluetoothManager?.getDiscoveredPeripherals().compactMap { $0.name })!
        print(pickerDevices)
    }
    
    func isConnected() {
        
    }
    
    func isDisconnected() {
        
    }
    
}
extension ViewModel : ShimmerProtocolDelegate {
    func shimmerBTStateChange(message: ShimmerBluetooth.Shimmer3Protocol.Shimmer3BTState) {
        DispatchQueue.main.async {
            self.stateText = message.stringValue
        }
    }
    
    func shimmerProtocolNewMessage(message: String) {
        print("View Model \(message)")
    }

    func shimmerProtocolNewObjectCluster(message: ShimmerBluetooth.ObjectCluster) {
        DispatchQueue.main.async {
            print(message)
            self.packetReceptionRate = message.PacketReceptionRate
            
            if (!self.updatedPicker) {
                self.pickerData = message.SignalNames
                self.updatedPicker = true
            }
            
            if (self.numberOfSignals > 0 && self.startIndex + 0 < message.SignalData.count) {
                self.signal1.append(message.SignalData[self.startIndex + 0])
            }
            if (self.numberOfSignals > 1 && self.startIndex + 1 < message.SignalData.count) {
                self.signal2.append(message.SignalData[self.startIndex + 1])
            }
            if (self.numberOfSignals > 2 && self.startIndex + 2 < message.SignalData.count) {
                self.signal3.append(message.SignalData[self.startIndex + 2])
            }
            if (self.signal1.count == 500) {
                self.signal1.removeFirst()
            }
            if (self.signal2.count == 500) {
                self.signal2.removeFirst()
            }
            if (self.signal3.count == 500) {
                self.signal3.removeFirst()
            }
            self.count += 1
            if (self.count % 10 == 0) {
                self.delegate?.plotEvent(message: "")
            }
        }
    }
    
}

public protocol ViewModelDelegate {
    func plotEvent(message:String)
}
