# Sony 1000X control on macOS: research notes

Tested 2026-09-27 against a WH-1000XM5 (fw 2.4.1,) on macOS 27.0.

## TL;DR

- Control happens over a **Bluetooth Classic RFCOMM** channel that Sony calls the "MDR" protocol. No BLE and no pairing tricks: the headset is already paired for audio, so we open one more channel on the same link.
- Service name on the XM5 is `Serial HPC`, UUID `956c7b26-d49a-4ba8-b03f-b17d393cb6e2`, **RFCOMM channel 9** (always resolve via SDP, other models differ).
- macOS does **not** expose it as `/dev/cu.*`, so you need IOBluetooth:
  - **Python**: PyObjC (`pyobjc-framework-IOBluetooth`). Works, see `sonymdr.py`, `probe.py`.
  - **Bun/Node**: there's no usable native binding, so use a ~40-line Swift sidecar (`bun/rfcomm-bridge.swift`) that pipes raw bytes over stdio. Works, see `bun/sony.ts`.
- The protocol reference is Gadgetbridge's Sony implementation (`service/devices/sony/headphones/protocol/impl/v1` + `v2`). The XM5 speaks "v2".

## Framing

```
3e | esc( type | seq | len:u32be | payload | checksum ) | 3c
checksum = sum(type..payload) & 0xff
escape  : 3c/3d/3e  ->  3d, (b & 0xef)     unescape: 3d x -> x | 0x10
type    : 01 ACK, 0c COMMAND_1, 0e COMMAND_2
```

- Every non-ACK frame must be ACKed with `seq = 1 - received_seq`, or the headset retransmits.
- For your next command, use the seq from the headset's last ACK.
- Replies are "RET" (`opcode+1`). The headset also pushes unsolicited "NOTIFY" frames (`opcode+3`), e.g. when you press the NC button or battery changes. A menubar app should keep the channel open and listen for these.

## Verified on the XM5

| What | Send | Got | Meaning |
|---|---|---|---|
| Init / protocol info | `00 00` | `01 00 03 00 20 16 00 00` | must be sent first |
| Firmware | `04 02` | `05 02 05 "2.4.1"` | ASCII string |
| Battery | `22 00` | `23 00 63 00` | 0x63 = 99 %, byte 3 = charging |
| Codec | `12 02` | `13 02 02` | 0x02 = AAC (what macOS uses) |
| NC/Ambient get | `66 17` | `67 17 01 01 00 00 14` | `[3]` on, `[4]` 0=NC 1=ambient, `[5]` focus-on-voice, `[6]` ambient level 0–20 |
| NC/Ambient **set** | `68 17 01 <on> <amb> <voice> <lvl>` | NOTIFY `69 …` | tested NC ↔ ambient; state was restored afterwards |
| EQ | `56 00` | `57 00 a0 06 12 07 0d 0e 0a 12` | preset 0xa0 (custom), 6 values, each `value+10` (clear bass, 5 bands) |
| DSEE | `e6 01` | `e7 01 00` | off |
| Speak-to-chat | `f6 0c` | `f7 0c 01 01` | `[2]` 0=on / 1=off (inverted) |
| Pause when removed | `f6 01` | `f7 01 00` | 0 = enabled (Gadgetbridge's `26 01` gets no reply on XM5) |
| Auto power off | `26 05` | `27 05 10 00` | mode code |
| Volume | `a6 20` | `a7 20 16` | 22 / 30 |

Quirk: in NC mode the level byte is ignored, and the stored ambient level becomes whatever you last set while in ambient mode.

Not yet explored (Gadgetbridge has payloads for these): EQ set, speak-to-chat config, touch sensor, multipoint/connected devices, the Quick Access button, and NC optimizer.

## Running

```sh
python3 -m venv venv && ./venv/bin/pip install pyobjc-framework-IOBluetooth
./venv/bin/python probe.py            # read-only dump, verbose frames

cd bun && swiftc -O rfcomm-bridge.swift -o rfcomm-bridge
SONY_ADDR=AA-BB-CC-DD-EE-FF bun sony.ts status | nc | ambient 10 | off
```

The terminal app needs Bluetooth permission (System Settings → Privacy & Security → Bluetooth).

## Implications for the menubar app

- The shipped app should be **native Swift** (IOBluetooth + `NSStatusItem`/SwiftUI `MenuBarExtra`). The Python and Bun paths are good for poking at the protocol, but both end up wrapping IOBluetooth anyway.
- You need `NSBluetoothAlwaysUsageDescription` in Info.plist. A sandboxed app also needs the `com.apple.security.device.bluetooth` entitlement.
- Keep one long-lived channel open and drive the UI from NOTIFY frames, so the menu reflects hardware button presses.
- Detect connect/disconnect with `IOBluetoothDevice.register(forConnectNotifications:)`, then re-open the channel.
- Find the device by looking for paired devices that have the Sony UUID in their SDP records, not by name or address.

## Prior art

- Gadgetbridge Sony protocol (canonical reverse engineering): https://codeberg.org/Freeyourgadget/Gadgetbridge
- mos9527/SonyHeadphonesClient (C++ with a macOS IOBluetooth backend, v2 protocol)
- snizovtsev/xm5-mode-switch (Linux, XM5)
- There are many copycat forks on GitHub ("SonyBridge", "xm6-control", …). Treat them as unvetted.
