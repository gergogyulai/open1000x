import Foundation
import IOBluetooth
import Observation

/// Tracks paired Sony headsets and keeps an MDR session open to the connected one.
@Observable
@MainActor
public final class DeviceManager {
    public private(set) var headphones: Headphones?
    /// Paired devices that advertise Sony's control service.
    public private(set) var pairedHeadsets: [IOBluetoothDevice] = []

    @ObservationIgnored private var observer: NotificationObserver?
    @ObservationIgnored private var disconnectRegistrations: [String: IOBluetoothUserNotification] = [:]
    @ObservationIgnored public var trace: ((String) -> Void)?

    public init() {}

    public func start() {
        observer = NotificationObserver(owner: self)
        observer?.registerForConnects()
        rescan()
    }

    public func rescan() {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        pairedHeadsets = paired.filter(Self.isSonyHeadset)
        if headphones == nil || headphones?.state != .ready,
           let connected = pairedHeadsets.first(where: { $0.isConnected() }) {
            attach(connected)
        }
    }

    /// Opens a baseband connection to a paired headset that is on but not connected.
    public func connect(_ device: IOBluetoothDevice) {
        if device.isConnected() {
            attach(device)
        } else {
            device.openConnection()
        }
    }

    public func reconnect() {
        guard let device = headphones?.device else { return rescan() }
        headphones?.disconnect()
        headphones = nil
        attach(device)
    }

    static func isSonyHeadset(_ device: IOBluetoothDevice) -> Bool {
        if device.getServiceRecord(for: MDRConnection.serviceUUID) != nil { return true }
        // SDP records may not be cached yet for a device that was never connected here.
        let name = device.name ?? ""
        return name.hasPrefix("WH-") || name.hasPrefix("WF-") || name.hasPrefix("LinkBuds")
    }

    fileprivate func deviceConnected(_ device: IOBluetoothDevice) {
        guard Self.isSonyHeadset(device) else { return }
        if !pairedHeadsets.contains(where: { $0.addressString == device.addressString }) {
            pairedHeadsets.append(device)
        }
        // Audio profiles come up shortly after the ACL link; give the headset a moment.
        Task {
            try? await Task.sleep(for: .seconds(2))
            if headphones?.state != .ready { attach(device) }
        }
    }

    fileprivate func deviceDisconnected(_ device: IOBluetoothDevice) {
        guard let hp = headphones, hp.device.addressString == device.addressString else { return }
        hp.disconnect()
    }

    private func attach(_ device: IOBluetoothDevice) {
        if let hp = headphones, hp.device.addressString == device.addressString,
           hp.state == .ready || hp.state == .connecting { return }
        headphones?.disconnect()
        let hp = Headphones(device: device)
        hp.connection.trace = trace
        headphones = hp
        if let address = device.addressString, disconnectRegistrations[address] == nil {
            disconnectRegistrations[address] = observer?.registerForDisconnect(of: device)
        }
        Task { await hp.connect() }
    }
}

/// Objective-C target for IOBluetooth's selector-based notifications.
/// These can arrive on a CoreBluetooth background queue, so the callbacks hop to the main actor.
@MainActor
private final class NotificationObserver: NSObject {
    weak var owner: DeviceManager?
    private var connectRegistration: IOBluetoothUserNotification?

    init(owner: DeviceManager) {
        self.owner = owner
    }

    func registerForConnects() {
        connectRegistration = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    func registerForDisconnect(of device: IOBluetoothDevice) -> IOBluetoothUserNotification? {
        device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
    }

    @objc nonisolated func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        nonisolated(unsafe) let device = device
        DispatchQueue.main.async {
            self.owner?.deviceConnected(device)
        }
    }

    @objc nonisolated func disconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        nonisolated(unsafe) let device = device
        DispatchQueue.main.async {
            self.owner?.deviceDisconnected(device)
            self.owner?.forgetDisconnectRegistration(for: device)
        }
    }
}

extension DeviceManager {
    fileprivate func forgetDisconnectRegistration(for device: IOBluetoothDevice) {
        if let address = device.addressString { disconnectRegistrations[address] = nil }
    }
}
