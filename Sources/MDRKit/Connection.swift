import Foundation
import IOBluetooth

public enum MDRError: Error, LocalizedError {
    case deviceNotFound
    case serviceNotFound
    case openFailed(IOReturn)
    case writeFailed(IOReturn)
    case notConnected
    case ackTimeout
    case replyTimeout(UInt8)

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound: "No connected Sony headset was found."
        case .serviceNotFound: "The headset does not expose Sony's control service."
        case .openFailed(let r): String(format: "Could not open the control channel (0x%08X).", r)
        case .writeFailed(let r): String(format: "Could not write to the headset (0x%08X).", r)
        case .notConnected: "The headset is not connected."
        case .ackTimeout: "The headset did not acknowledge the command."
        case .replyTimeout(let c): String(format: "The headset did not reply to command 0x%02X.", c)
        }
    }
}

/// One RFCOMM channel to the headset's "Serial HPC" service, speaking MDR frames.
///
/// Commands are sent one at a time; each waits for the headset's ACK (retransmitting
/// with the same sequence number if needed). Every data frame from the headset is
/// ACKed immediately and handed to `onMessage`.
@MainActor
public final class MDRConnection: NSObject, @preconcurrency IOBluetoothRFCOMMChannelDelegate {
    public static let serviceUUID = IOBluetoothSDPUUID(bytes: [
        0x95, 0x6C, 0x7B, 0x26, 0xD4, 0x9A, 0x4B, 0xA8, 0xB0, 0x3F, 0xB1, 0x7D, 0x39, 0x3C, 0xB6, 0xE2,
    ] as [UInt8], length: 16)

    public var onMessage: ((MDRDataType, [UInt8]) -> Void)?
    public var onClose: (() -> Void)?
    /// Logs every frame in both directions; handy for protocol work.
    public var trace: ((String) -> Void)?

    public let device: IOBluetoothDevice
    private var channel: IOBluetoothRFCOMMChannel?
    private var openContinuation: CheckedContinuation<Void, Error>?
    private var decoder = MDRFrameDecoder()
    private var seq: UInt8 = 0
    private var ackContinuation: CheckedContinuation<Void, Error>?
    private var ackGeneration = 0
    private var sendChain: Task<Void, Never>?
    private var waiters: [(id: UUID, match: (MDRDataType, [UInt8]) -> Bool, cont: CheckedContinuation<[UInt8], Error>)] = []

    public init(device: IOBluetoothDevice) {
        self.device = device
    }

    public var isOpen: Bool { channel?.isOpen() ?? false }

    public func open() async throws {
        let channelID = try Self.rfcommChannelID(for: device)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            openContinuation = cont
            var chan: IOBluetoothRFCOMMChannel?
            let status = device.openRFCOMMChannelAsync(&chan, withChannelID: channelID, delegate: self)
            if status != kIOReturnSuccess {
                openContinuation = nil
                cont.resume(throwing: MDRError.openFailed(status))
            } else {
                channel = chan
            }
        }
    }

    public func close() {
        channel?.close()
        channel = nil
        failPending(MDRError.notConnected)
    }

    static func rfcommChannelID(for device: IOBluetoothDevice) throws -> BluetoothRFCOMMChannelID {
        guard let record = device.getServiceRecord(for: serviceUUID) else { throw MDRError.serviceNotFound }
        var id: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&id) == kIOReturnSuccess else { throw MDRError.serviceNotFound }
        return id
    }

    // MARK: Sending

    /// Sends a command and waits for the headset's ACK.
    public func send(_ payload: [UInt8], table: MDRDataType = .table1) async throws {
        let previous = sendChain
        let task = Task { @MainActor in
            await previous?.value
            return try await self.transmit(payload, table: table)
        }
        sendChain = Task { _ = try? await task.value }
        try await task.value
    }

    /// Sends a command and returns the first reply accepted by `match`.
    public func request(_ payload: [UInt8], table: MDRDataType = .table1, timeout: Duration = .seconds(3),
                        match: @escaping ([UInt8]) -> Bool) async throws -> [UInt8] {
        let id = UUID()
        let reply = Task { @MainActor in
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[UInt8], Error>) in
                waiters.append((id, { t, p in t == table && match(p) }, cont))
            }
        }
        let timer = Task { @MainActor in
            try await Task.sleep(for: timeout)
            self.resolveWaiter(id, with: .failure(MDRError.replyTimeout(payload.first ?? 0)))
        }
        defer { timer.cancel() }
        do {
            try await send(payload, table: table)
        } catch {
            resolveWaiter(id, with: .failure(error))
        }
        return try await reply.value
    }

    /// Convenience for the common `GET x sub` → `RET x+1 sub` shape.
    public func query(_ payload: [UInt8], table: MDRDataType = .table1) async throws -> [UInt8] {
        let ret = payload[0] &+ 1
        let sub = payload.count > 1 ? payload[1] : nil
        return try await request(payload, table: table) { p in
            p.first == ret && (sub == nil || (p.count > 1 && p[1] == sub))
        }
    }

    private func transmit(_ payload: [UInt8], table: MDRDataType) async throws {
        guard let channel, channel.isOpen() else { throw MDRError.notConnected }
        let frame = MDRFrame(type: table.rawValue, seq: seq, payload: payload)
        for _ in 0..<3 {
            trace?("→ \(table == .table1 ? "T1" : "T2") \(hex(payload))")
            try write(MDRFraming.encode(frame))
            let acked = try await waitForAck(timeout: .milliseconds(800))
            if acked { return }
        }
        throw MDRError.ackTimeout
    }

    private func waitForAck(timeout: Duration) async throws -> Bool {
        ackGeneration &+= 1
        let generation = ackGeneration
        let timer = Task { @MainActor in
            try await Task.sleep(for: timeout)
            if generation == self.ackGeneration, let c = self.ackContinuation {
                self.ackContinuation = nil
                c.resume(throwing: CancellationError())
            }
        }
        defer { timer.cancel() }
        do {
            try await withCheckedThrowingContinuation { ackContinuation = $0 }
            return true
        } catch is CancellationError {
            return false
        }
    }

    private func write(_ bytes: [UInt8]) throws {
        guard let channel else { throw MDRError.notConnected }
        var data = bytes
        let status = data.withUnsafeMutableBytes { buf in
            channel.writeSync(buf.baseAddress, length: UInt16(buf.count))
        }
        if status != kIOReturnSuccess { throw MDRError.writeFailed(status) }
    }

    private func resolveWaiter(_ id: UUID, with result: Result<[UInt8], Error>) {
        guard let i = waiters.firstIndex(where: { $0.id == id }) else { return }
        let w = waiters.remove(at: i)
        w.cont.resume(with: result)
    }

    private func failPending(_ error: Error) {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.cont.resume(throwing: error) }
        if let c = ackContinuation {
            ackContinuation = nil
            c.resume(throwing: error)
        }
    }

    // MARK: Receiving

    private func receive(_ bytes: [UInt8]) {
        for frame in decoder.feed(bytes) {
            if frame.type == MDRDataType.ack.rawValue {
                seq = frame.seq
                if let c = ackContinuation {
                    ackContinuation = nil
                    c.resume()
                }
                continue
            }
            try? write(MDRFraming.encode(MDRFrame(type: MDRDataType.ack.rawValue, seq: 1 &- frame.seq, payload: [])))
            guard let table = MDRDataType(rawValue: frame.type) else { continue }
            trace?("← \(table == .table1 ? "T1" : "T2") \(hex(frame.payload))")
            onMessage?(table, frame.payload)
            if let i = waiters.firstIndex(where: { $0.match(table, frame.payload) }) {
                let w = waiters.remove(at: i)
                w.cont.resume(returning: frame.payload)
            }
        }
    }

    // MARK: IOBluetoothRFCOMMChannelDelegate

    public func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard let c = openContinuation else { return }
        openContinuation = nil
        if error == kIOReturnSuccess {
            channel = rfcommChannel
            c.resume()
        } else {
            channel = nil
            c.resume(throwing: MDRError.openFailed(error))
        }
    }

    public func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        receive([UInt8](UnsafeRawBufferPointer(start: dataPointer, count: dataLength)))
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        channel = nil
        if let c = openContinuation {
            openContinuation = nil
            c.resume(throwing: MDRError.notConnected)
        }
        failPending(MDRError.notConnected)
        onClose?()
    }
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}
