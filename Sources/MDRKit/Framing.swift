import Foundation

/// Frame data types used on the Sony MDR RFCOMM channel.
public enum MDRDataType: UInt8, Sendable {
    case ack = 0x01
    /// Command table 1 ("DATA_MDR").
    case table1 = 0x0C
    /// Command table 2 ("DATA_MDR_NO2").
    case table2 = 0x0E
}

public struct MDRFrame: Equatable, Sendable {
    public var type: UInt8
    public var seq: UInt8
    public var payload: [UInt8]

    public init(type: UInt8, seq: UInt8, payload: [UInt8]) {
        self.type = type
        self.seq = seq
        self.payload = payload
    }
}

/// `3e | escape(type seq len:u32be payload checksum) | 3c`
public enum MDRFraming {
    static let start: UInt8 = 0x3E
    static let end: UInt8 = 0x3C
    static let escape: UInt8 = 0x3D

    public static func encode(_ frame: MDRFrame) -> [UInt8] {
        let n = UInt32(frame.payload.count)
        var body: [UInt8] = [frame.type, frame.seq,
                             UInt8(n >> 24 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)]
        body += frame.payload
        body.append(checksum(body))
        var out: [UInt8] = [start]
        out.reserveCapacity(body.count + 4)
        for b in body {
            if b == start || b == end || b == escape {
                out += [escape, b & 0xEF]
            } else {
                out.append(b)
            }
        }
        out.append(end)
        return out
    }

    static func checksum(_ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(0, &+)
    }

    /// Decodes the bytes between the start and end markers.
    public static func decode(escaped: ArraySlice<UInt8>) -> MDRFrame? {
        var raw: [UInt8] = []
        raw.reserveCapacity(escaped.count)
        var it = escaped.makeIterator()
        while let b = it.next() {
            if b == escape {
                guard let next = it.next() else { return nil }
                raw.append(next | 0x10)
            } else {
                raw.append(b)
            }
        }
        guard raw.count >= 7 else { return nil }
        let body = raw.dropLast()
        guard checksum(Array(body)) == raw.last else { return nil }
        let len = Int(raw[2]) << 24 | Int(raw[3]) << 16 | Int(raw[4]) << 8 | Int(raw[5])
        guard 6 + len <= body.count else { return nil }
        return MDRFrame(type: raw[0], seq: raw[1], payload: Array(raw[6..<(6 + len)]))
    }
}

/// Reassembles frames from an RFCOMM byte stream.
public struct MDRFrameDecoder {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func feed(_ bytes: [UInt8]) -> [MDRFrame] {
        buffer += bytes
        var frames: [MDRFrame] = []
        while let s = buffer.firstIndex(of: MDRFraming.start) {
            guard let e = buffer[(s + 1)...].firstIndex(of: MDRFraming.end) else {
                buffer.removeSubrange(..<s)
                break
            }
            if let frame = MDRFraming.decode(escaped: buffer[(s + 1)..<e]) {
                frames.append(frame)
            }
            buffer.removeSubrange(...e)
        }
        if buffer.firstIndex(of: MDRFraming.start) == nil { buffer.removeAll() }
        return frames
    }
}

/// Cursor over a payload with the MDR primitive encodings
/// (u8-prefixed strings and arrays, big-endian integers).
public struct ByteReader {
    public enum Error: Swift.Error { case underflow }

    private let bytes: [UInt8]
    public private(set) var offset: Int

    public init(_ bytes: [UInt8], offset: Int = 0) {
        self.bytes = bytes
        self.offset = offset
    }

    public var remaining: Int { bytes.count - offset }

    public mutating func u8() throws -> UInt8 {
        guard offset < bytes.count else { throw Error.underflow }
        defer { offset += 1 }
        return bytes[offset]
    }

    public mutating func take(_ n: Int) throws -> [UInt8] {
        guard n >= 0, offset + n <= bytes.count else { throw Error.underflow }
        defer { offset += n }
        return Array(bytes[offset..<(offset + n)])
    }

    public mutating func u16() throws -> UInt16 {
        let b = try take(2)
        return UInt16(b[0]) << 8 | UInt16(b[1])
    }

    public mutating func u24() throws -> UInt32 {
        let b = try take(3)
        return UInt32(b[0]) << 16 | UInt32(b[1]) << 8 | UInt32(b[2])
    }

    public mutating func string() throws -> String {
        let n = Int(try u8())
        return String(decoding: try take(n), as: UTF8.self)
    }

    public mutating func ascii(_ n: Int) throws -> String {
        String(decoding: try take(n), as: UTF8.self)
    }

    public mutating func podArray() throws -> [UInt8] {
        try take(Int(try u8()))
    }
}
