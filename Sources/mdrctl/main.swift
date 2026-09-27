import Foundation
import IOBluetooth
import MDRKit

let usage = """
usage: mdrctl [--trace] <command>

  status                         full state of the connected headset
  nc | off                       noise cancelling / noise control off
  ambient [1-20] [voice]         ambient sound, optional level and focus on voice
  button <1-4>                   NC/AMB button cycle (1 NC→AMB→Off, 2 NC↔AMB, 3 NC↔Off, 4 AMB↔Off)
  eq <preset-hex|name>           e.g. eq 00 (off), eq 10 (bright), eq a0 (manual), eq punch, eq clarity
  eq-bands <cb> <b1> ... <b5>    Clear Bass and five bands, -10...10
  s2c on|off                     Speak-to-Chat
  s2c-config <0-2> <0-3>         sensitivity (auto/high/low), timeout (short/std/long/never)
  dsee on|off
  priority sound|stable          connection quality
  volume <0-30>
  play | pause | next | prev
  auto-off <hex>                 00 5m, 04 15m, 01 30m, 02 1h, 03 3h, 10 when removed, 11 never
  pause-on-removal on|off
  va <hex>                       voice assistant: 30 device, 31 Google, 32 Alexa, ff off
  quick-access <double> <triple> service ids, e.g. 00 01
  gs <d1-d4> on|off              general settings (touch panel, multipoint)
  guidance on|off [lang-hex]
  devices                        list paired devices
  switch <address>               move audio to another multipoint device
  connect|disconnect|unpair <address>
  pairing on|off
  source-switch on|off
  raw t1|t2 <hex bytes>          send a raw payload and print replies
  listen [seconds]               print notifications from the headset
  power-off
"""

var args = Array(CommandLine.arguments.dropFirst())
let traceEnabled = args.first == "--trace"
if traceEnabled { args.removeFirst() }
guard let command = args.first else {
    print(usage)
    exit(2)
}
let rest = Array(args.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func byte(_ s: String) -> UInt8 {
    guard let v = UInt8(s.replacingOccurrences(of: "0x", with: ""), radix: 16) else { fail("not a hex byte: \(s)") }
    return v
}

func onOff(_ s: String?) -> Bool {
    switch s {
    case "on": return true
    case "off": return false
    default: fail("expected on|off")
    }
}

@MainActor
func printStatus(_ h: Headphones) {
    func line(_ k: String, _ v: Any) { print("\(k.count < 22 ? k.padding(toLength: 22, withPad: " ", startingAt: 0) : k) \(v)") }
    line("model", "\(h.modelName)  fw \(h.firmwareVersion)  \(h.address)")
    line("battery", "\(h.battery.map { "\($0)%" } ?? "?")  \(h.charging)")
    line("codec", h.codec.label + (h.upscalingActive ? "  (DSEE active)" : ""))
    line("noise control", "\(h.noiseMode.label)  ambient \(h.ambientLevel)\(h.focusOnVoice ? " voice" : "")")
    if let b = h.ncAmbButton { line("NC/AMB button", b.label) }
    line("speak-to-chat", "\(h.speakToChat ? "on" : "off")  \(h.speakToChatSensitivity.label), \(h.speakToChatTimeout.label)")
    line("equalizer", "\(h.eqPresetName)  \(h.eqBands)  presets: \(h.eqPresets.map(\.label).joined(separator: ", "))")
    line("DSEE", "\(h.upscalingType?.label ?? "-") \(h.upscalingEnabled ? "auto" : "off")\(h.upscalingAvailable ? "" : " (unavailable)")")
    line("connection", h.connectionPriority.label)
    line("volume", "\(h.volume)/30  \(h.playback)")
    if !h.trackTitle.isEmpty { line("now playing", "\(h.trackTitle) — \(h.trackArtist) (\(h.trackAlbum))") }
    line("auto power off", h.autoPowerOff?.label ?? "-")
    line("pause when removed", h.pauseWhenTakenOff ? "on" : "off")
    line("voice assistant", "\(h.voiceAssistant.label)  options: \(h.voiceAssistantOptions.map(\.label).joined(separator: ", "))")
    line("quick access", "double: \(h.quickAccessDoubleTap.label), triple: \(h.quickAccessTripleTap.label)  options: \(h.quickAccessDoubleTapOptions.map(\.label).joined(separator: ", "))")
    for gs in h.generalSettings { line(gs.title, gs.isOn ? "on" : "off") }
    line("voice guidance", "\(h.voiceGuidance ? "on" : "off")  \(h.voiceGuidanceLanguage.label)  (\(h.voiceGuidanceLanguages.count) languages)")
    line("sound pressure", h.soundPressure.map { "\($0) dB" } ?? "-")
    line("pairing mode", h.pairingMode ? "on" : "off")
    line("auto source switch", h.sourceSwitchEnabled ? "on" : "off")
    for d in h.pairedDevices {
        line("  device", "\(d.address)  \(d.name)\(d.isConnected ? "  connected" : "")\(d.isPlaying ? "  ▶︎" : "")")
    }
    line("functions T1", h.t1.map { String(format: "%02x", $0.rawValue) }.sorted().joined(separator: " "))
    line("functions T2", h.t2.map { String(format: "%02x", $0.rawValue) }.sorted().joined(separator: " "))
}

@MainActor
func run() async {
    let manager = DeviceManager()
    if traceEnabled { manager.trace = { print("  \($0)") } }
    manager.rescan()
    guard let h = manager.headphones else { fail("no connected Sony headset") }
    while h.state == .connecting { try? await Task.sleep(for: .milliseconds(50)) }
    if case .disconnected(let reason) = h.state { fail("could not connect: \(reason ?? "unknown")") }

    // Let queued setters flush and the headset's notifications arrive.
    func settle() async { try? await Task.sleep(for: .milliseconds(600)) }

    switch command {
    case "status":
        printStatus(h)
    case "nc":
        h.setNoiseControl(.noiseCancelling)
    case "off":
        h.setNoiseControl(.off)
    case "ambient":
        let level = rest.first.flatMap(Int.init)
        h.setNoiseControl(.ambient, ambientLevel: level, focusOnVoice: rest.contains("voice"))
    case "button":
        guard let v = rest.first.flatMap(UInt8.init), let c = NcAmbButtonCycle(rawValue: v) else { fail("button 1-4") }
        h.setNcAmbButton(c)
    case "eq":
        if let curated = CuratedEQPreset.all.first(where: { $0.id == rest.first?.lowercased() }) {
            h.apply(curated)
        } else {
            h.setEQPreset(EQPreset(rawValue: byte(rest.first ?? "00")))
        }
    case "eq-bands":
        let bands = rest.compactMap(Int.init)
        guard bands.count == 6 else { fail("need 6 values") }
        h.setEQBands(bands)
    case "s2c":
        h.setSpeakToChat(onOff(rest.first))
    case "s2c-config":
        guard rest.count == 2, let s = SpeakToChatSensitivity(rawValue: byte(rest[0])),
              let t = SpeakToChatTimeout(rawValue: byte(rest[1])) else { fail("s2c-config <0-2> <0-3>") }
        h.setSpeakToChat(sensitivity: s, timeout: t)
    case "dsee":
        h.setUpscaling(onOff(rest.first))
    case "priority":
        h.setConnectionPriority(rest.first == "stable" ? .stableConnection : .soundQuality)
    case "volume":
        guard let v = rest.first.flatMap(Int.init) else { fail("volume 0-30") }
        h.setVolume(v)
    case "play": h.sendPlayback(.play)
    case "pause": h.sendPlayback(.pause)
    case "next": h.sendPlayback(.nextTrack)
    case "prev": h.sendPlayback(.previousTrack)
    case "auto-off":
        guard let v = AutoPowerOff(rawValue: byte(rest.first ?? "")) else { fail("bad auto-off value") }
        h.setAutoPowerOff(v)
    case "pause-on-removal":
        h.setPauseWhenTakenOff(onOff(rest.first))
    case "va":
        guard let v = VoiceAssistant(rawValue: byte(rest.first ?? "")) else { fail("bad assistant") }
        h.setVoiceAssistant(v)
    case "quick-access":
        guard rest.count == 2 else { fail("quick-access <double> <triple>") }
        h.setQuickAccess(doubleTap: QuickAccessService(rawValue: byte(rest[0])), tripleTap: QuickAccessService(rawValue: byte(rest[1])))
    case "gs":
        guard rest.count == 2 else { fail("gs <id> on|off") }
        h.setGeneralSetting(byte(rest[0]), onOff(rest[1]))
    case "guidance":
        h.setVoiceGuidance(onOff(rest.first), language: rest.count > 1 ? VoiceGuidanceLanguage(rawValue: byte(rest[1])) : nil)
    case "devices":
        for d in h.pairedDevices { print("\(d.address)  \(d.name)\(d.isConnected ? "  connected" : "")\(d.isPlaying ? "  playing" : "")") }
    case "switch", "connect", "disconnect", "unpair":
        guard let addr = rest.first, let d = h.pairedDevices.first(where: { $0.address.caseInsensitiveCompare(addr) == .orderedSame })
        else { fail("unknown device; see `mdrctl devices`") }
        switch command {
        case "switch": h.switchAudio(to: d)
        case "connect": h.perform(.connect, on: d)
        case "disconnect": h.perform(.disconnect, on: d)
        default: h.perform(.unpair, on: d)
        }
    case "pairing":
        h.setPairingMode(onOff(rest.first))
    case "source-switch":
        h.setSourceSwitch(onOff(rest.first))
    case "raw":
        guard rest.count >= 2 else { fail("raw t1|t2 <hex>") }
        let table: MDRDataType = rest[0] == "t2" ? .table2 : .table1
        let payload = rest.dropFirst().joined(separator: " ").split(separator: " ").map { byte(String($0)) }
        h.connection.trace = { print("  \($0)") }
        try? await h.connection.send(payload, table: table)
        await settle()
    case "listen":
        h.connection.trace = { print("\(Date().formatted(date: .omitted, time: .standard))  \($0)") }
        let seconds = rest.first.flatMap(Double.init) ?? 60
        print("listening for \(Int(seconds)) s…")
        try? await Task.sleep(for: .seconds(seconds))
    case "power-off":
        h.powerOff()
    default:
        print(usage)
        exit(2)
    }
    await settle()
    if let alert = h.pendingAlert {
        print("headset asks: \(alert.message)")
        print("(answer in the app; mdrctl declines by default)")
        h.respond(to: alert, accept: false)
        await settle()
    }
    if let error = h.lastError { fail(error) }
    if !["status", "devices", "raw", "listen"].contains(command) { printStatus(h) }
    h.disconnect()
    exit(0)
}

Task { @MainActor in await run() }
RunLoop.main.run()
