import Foundation
import CoreBluetooth
import Combine
import os

private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "DoorLockBLEManager")

@MainActor
class DoorLockBLEManager: NSObject, ObservableObject {
    @Published var connectionState: BleConnectionState = .disconnected
    @Published var lastResponse: String?

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var targetMac: String = ""
    private var scanTimer: Timer?
    private var connectTimer: Timer?

    private let serviceUUID = CBUUID(string: BLECommandHelper.serviceUUID)
    private let charUUID = CBUUID(string: BLECommandHelper.characteristicUUID)

    override init() {
        super.init()
    }

    func connect(macAddress: String) {
        targetMac = macAddress.uppercased().replacingOccurrences(of: ":", with: "")
        connectionState = .scanning
        lastResponse = nil

        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        } else if centralManager?.state == .poweredOn {
            startScan()
        }
    }

    private func startScan() {
        guard let cm = centralManager, cm.state == .poweredOn else {
            connectionState = .error
            return
        }
        cm.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard self?.connectionState == .scanning else { return }
                logger.warning("Scan timeout")
                self?.stopScan()
                self?.connectionState = .error
            }
        }
    }

    private func stopScan() {
        scanTimer?.invalidate()
        scanTimer = nil
        centralManager?.stopScan()
    }

    func sendCommand(_ data: Data) -> Bool {
        guard let peripheral, let characteristic = writeCharacteristic else { return false }
        logger.debug("Sending: \(BLECommandHelper.bytesToHex(data))")
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        return true
    }

    func disconnect() {
        stopScan()
        connectTimer?.invalidate()
        connectTimer = nil
        if let p = peripheral { centralManager?.cancelPeripheralConnection(p) }
        cleanup()
        connectionState = .disconnected
    }

    private func cleanup() {
        peripheral?.delegate = nil
        peripheral = nil
        writeCharacteristic = nil
    }

    func destroy() {
        disconnect()
        centralManager = nil
    }
}

extension DoorLockBLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn && connectionState == .scanning {
                startScan()
            } else if central.state != .poweredOn {
                connectionState = .error
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                     advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let advHex = advData.map { data in data.map { String(format: "%02x", $0) }.joined() } ?? ""
        let deviceName = peripheral.name ?? ""

        Task { @MainActor in
            let mac = self.targetMac
            guard advHex.uppercased().contains(mac) || deviceName.uppercased().contains(mac) else { return }
            logger.debug("Found target device: \(peripheral.identifier)")
            self.stopScan()
            self.peripheral = peripheral
            peripheral.delegate = self
            self.connectionState = .connecting
            central.connect(peripheral, options: nil)

            self.connectTimer?.invalidate()
            self.connectTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard self?.connectionState == .connecting else { return }
                    logger.warning("Connection timeout")
                    self?.disconnect()
                    self?.connectionState = .error
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            logger.debug("Connected, discovering services...")
            self.connectTimer?.invalidate()
            peripheral.discoverServices([serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown")")
            self.connectionState = .error
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            logger.debug("Disconnected")
            self.cleanup()
            self.connectionState = .disconnected
        }
    }
}

extension DoorLockBLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard error == nil else {
                self.connectionState = .error
                return
            }
            guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
                logger.error("Target service not found")
                self.connectionState = .error
                return
            }
            peripheral.discoverCharacteristics([charUUID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard error == nil else {
                self.connectionState = .error
                return
            }
            guard let characteristic = service.characteristics?.first(where: { $0.uuid == charUUID }) else {
                logger.error("Target characteristic not found")
                self.connectionState = .error
                return
            }
            self.writeCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
            logger.debug("BLE ready")
            self.connectionState = .connected
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }
        let hex = BLECommandHelper.bytesToHex(value)
        Task { @MainActor in
            logger.debug("Characteristic changed: \(hex)")
            self.lastResponse = hex
        }
    }
}
