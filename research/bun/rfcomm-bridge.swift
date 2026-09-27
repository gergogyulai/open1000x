// Tiny stdio <-> RFCOMM bridge. Usage: rfcomm-bridge <addr> [channel]
// stdin: raw bytes to send; stdout: raw bytes received.
import Foundation
import IOBluetooth

final class D: NSObject, IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelData(_ c: IOBluetoothRFCOMMChannel!, data p: UnsafeMutableRawPointer!, length n: Int) {
        FileHandle.standardOutput.write(Data(bytes: p, count: n))
    }
    func rfcommChannelClosed(_ c: IOBluetoothRFCOMMChannel!) { exit(0) }
}
let args = CommandLine.arguments
guard args.count > 1, let dev = IOBluetoothDevice(addressString: args[1]) else {
    FileHandle.standardError.write("usage: rfcomm-bridge <addr> [channel]\n".data(using: .utf8)!); exit(2)
}
let delegate = D()
var chan: IOBluetoothRFCOMMChannel?
let ch = BluetoothRFCOMMChannelID(args.count > 2 ? UInt8(args[2])! : 9)
let st = dev.openRFCOMMChannelSync(&chan, withChannelID: ch, delegate: delegate)
guard st == kIOReturnSuccess, let chan else {
    FileHandle.standardError.write("open failed \(st)\n".data(using: .utf8)!); exit(1)
}
FileHandle.standardInput.readabilityHandler = { h in
    var d = h.availableData
    if d.isEmpty { chan.close(); exit(0) }
    DispatchQueue.main.async { _ = d.withUnsafeMutableBytes { chan.writeSync($0.baseAddress, length: UInt16($0.count)) } }
}
RunLoop.main.run()
