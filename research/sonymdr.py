"""Minimal Sony MDR (v2) client for WH-1000XM5 on macOS via IOBluetooth RFCOMM.

Research prototype. Frame format (from Gadgetbridge):
  0x3e | escaped( type | seq | len:u32be | payload | checksum ) | 0x3c
  checksum = sum(type, seq, len bytes, payload) & 0xff
  escape: 0x3c/0x3d/0x3e -> 0x3d, (b & 0xef)
Message types: 0x01 ACK, 0x0c COMMAND_1, 0x0e COMMAND_2.
"""
import struct
import sys
import time

import IOBluetooth
import objc
from Foundation import NSDate, NSObject, NSRunLoop

SONY_SERVICE_NAME = "Serial HPC"  # UUID 956c7b26-d49a-4ba8-b03f-b17d393cb6e2
HEADER, TRAILER, ESCAPE = 0x3E, 0x3C, 0x3D
ACK, CMD1, CMD2 = 0x01, 0x0C, 0x0E


def escape(data: bytes) -> bytes:
    out = bytearray()
    for b in data:
        if b in (HEADER, TRAILER, ESCAPE):
            out += bytes((ESCAPE, b & 0xEF))
        else:
            out.append(b)
    return bytes(out)


def unescape(data: bytes) -> bytes:
    out, it = bytearray(), iter(data)
    for b in it:
        out.append((next(it) | 0x10) if b == ESCAPE else b)
    return bytes(out)


def encode(mtype: int, seq: int, payload: bytes) -> bytes:
    body = bytes((mtype, seq)) + struct.pack(">I", len(payload)) + payload
    return bytes((HEADER,)) + escape(body + bytes((sum(body) & 0xFF,))) + bytes((TRAILER,))


def decode(frame: bytes):
    """frame excludes 0x3e/0x3c. Returns (type, seq, payload)."""
    raw = unescape(frame)
    body, chk = raw[:-1], raw[-1]
    if sum(body) & 0xFF != chk:
        raise ValueError(f"bad checksum {raw.hex()}")
    mtype, seq = body[0], body[1]
    (n,) = struct.unpack(">I", body[2:6])
    return mtype, seq, body[6 : 6 + n]


def pump(seconds: float):
    NSRunLoop.currentRunLoop().runUntilDate_(NSDate.dateWithTimeIntervalSinceNow_(seconds))


class Delegate(NSObject):
    def init(self):
        self = objc.super(Delegate, self).init()
        self.buf = bytearray()
        self.inbox = []  # decoded (type, seq, payload)
        self.chan = None
        return self

    def rfcommChannelData_data_length_(self, chan, data, length):
        self.buf += bytes(data[:length]) if not isinstance(data, bytes) else data[:length]
        while True:
            try:
                s = self.buf.index(HEADER)
                e = self.buf.index(TRAILER, s)
            except ValueError:
                break
            frame = bytes(self.buf[s + 1 : e])
            del self.buf[: e + 1]
            mtype, seq, payload = decode(frame)
            if mtype != ACK:
                # every command from the headset must be ACKed with seq = 1 - seq
                self.write(encode(ACK, 1 - seq, b""))
            self.inbox.append((mtype, seq, payload))

    def rfcommChannelClosed_(self, chan):
        print("# channel closed", file=sys.stderr)

    @objc.python_method
    def write(self, data: bytes):
        self.chan.writeSync_length_(data, len(data))


class MDR:
    def __init__(self, address: str | None = None, verbose=False):
        self.verbose = verbose
        self.dev = self._find(address)
        channel_id = self._channel()
        self.d = Delegate.alloc().init()
        status, chan = self.dev.openRFCOMMChannelSync_withChannelID_delegate_(None, channel_id, self.d)
        if status != 0:
            raise RuntimeError(f"openRFCOMMChannel failed: {status:#x}")
        self.d.chan = chan
        self.seq = 0

    @staticmethod
    def _find(address):
        if address:
            return IOBluetooth.IOBluetoothDevice.deviceWithAddressString_(address)
        for dev in IOBluetooth.IOBluetoothDevice.pairedDevices() or []:
            if dev.isConnected() and dev.getServiceRecordForUUID_(
                IOBluetooth.IOBluetoothSDPUUID.uuidWithBytes_length_(
                    bytes.fromhex("956c7b26d49a4ba8b03fb17d393cb6e2"), 16
                )
            ):
                return dev
        for dev in IOBluetooth.IOBluetoothDevice.pairedDevices() or []:
            if dev.isConnected() and (dev.name() or "").startswith(("WH-", "WF-")):
                return dev
        raise RuntimeError("no connected Sony headset found")

    def _channel(self) -> int:
        for s in self.dev.services() or []:
            if s.getServiceName() == SONY_SERVICE_NAME:
                ok, ch = s.getRFCOMMChannelID_(None)
                if ok == 0:
                    return ch
        return 9  # XM5 default

    def close(self):
        self.d.chan.closeChannel()

    def send(self, payload: bytes, mtype=CMD1, wait_reply=True, timeout=2.0):
        """Send a command; return list of non-ACK messages received until quiet."""
        if self.verbose:
            print(f"> {mtype:02x} seq={self.seq} {payload.hex(' ')}", file=sys.stderr)
        self.d.write(encode(mtype, self.seq, payload))
        deadline = time.time() + timeout
        got_ack = False
        replies = []
        while time.time() < deadline:
            pump(0.05)
            while self.d.inbox:
                t, s, p = self.d.inbox.pop(0)
                if self.verbose:
                    print(f"< {t:02x} seq={s} {p.hex(' ')}", file=sys.stderr)
                if t == ACK:
                    got_ack = True
                    self.seq = s  # next seq comes from the ACK
                else:
                    replies.append((t, p))
            if got_ack and (replies or not wait_reply):
                pump(0.15)  # collect trailing notifications
                while self.d.inbox:
                    t, s, p = self.d.inbox.pop(0)
                    if t != ACK:
                        replies.append((t, p))
                break
        return replies

    def listen(self, seconds: float):
        end = time.time() + seconds
        while time.time() < end:
            pump(0.1)
            while self.d.inbox:
                yield self.d.inbox.pop(0)
