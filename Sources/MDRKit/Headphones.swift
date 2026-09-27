import Foundation
import IOBluetooth
import Observation

public struct PairedDevice: Hashable, Sendable, Identifiable {
    public let address: String
    public let name: String
    public let isConnected: Bool
    public let isPlaying: Bool
    public let classOfDevice: UInt32
    public var id: String { address }

    /// Bluetooth major device class 0x01 = computer, 0x02 = phone.
    public var symbolName: String {
        switch (classOfDevice >> 8) & 0x1F {
        case 0x01: "laptopcomputer"
        case 0x02: "iphone"
        case 0x04: "hifispeaker"
        default: "wave.3.right"
        }
    }
}

/// A headset-described on/off setting (Sound Connect's "general settings").
public struct GeneralSetting: Hashable, Sendable, Identifiable {
    public let id: UInt8
    public let key: String
    public let summaryKey: String
    public var isOn: Bool

    public var title: String {
        switch key {
        case "TOUCH_PANEL_SETTING": "Touch sensor control panel"
        case "MULTIPOINT_SETTING": "Connect to 2 devices simultaneously"
        case "CAPTURE_VOICE_SETTING": "Capture voice during a phone call"
        default: key.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
        }
    }

    public var summary: String? {
        switch summaryKey {
        case "MULTIPOINT_SETTING_SUMMARY_LDAC_AVAILABLE": "LDAC stays available, at a lower bitrate while two devices are connected."
        case "": nil
        default: nil
        }
    }
}

@Observable
@MainActor
public final class Headphones {
    public enum State: Equatable { case connecting, ready, disconnected(String?) }

    public let connection: MDRConnection
    public var device: IOBluetoothDevice { connection.device }

    public private(set) var state: State = .connecting
    public private(set) var lastError: String?

    // Identity
    public private(set) var modelName: String
    public private(set) var firmwareVersion = ""
    public private(set) var address: String
    public private(set) var protocolVersion: UInt32 = 0
    public private(set) var t1: Set<T1Function> = []
    public private(set) var t2: Set<T2Function> = []
    public private(set) var hasTable2 = false

    // Status
    public private(set) var battery: Int?
    public private(set) var charging: ChargingStatus = .notCharging
    public private(set) var codec: AudioCodec = .unsettled
    public private(set) var upscalingActive = false

    // Noise control
    public private(set) var noiseMode: NoiseMode = .noiseCancelling
    public private(set) var ambientLevel = 20
    public private(set) var focusOnVoice = false
    public private(set) var ncAmbButton: NcAmbButtonCycle?

    // Speak-to-Chat
    public private(set) var speakToChat = false
    public private(set) var speakToChatSensitivity: SpeakToChatSensitivity = .auto
    public private(set) var speakToChatTimeout: SpeakToChatTimeout = .standard

    // Equalizer
    public private(set) var eqAvailable = true
    public private(set) var eqPresets: [EQPreset] = []
    public private(set) var eqPreset: EQPreset = .off
    /// Clear Bass followed by 400 Hz, 1 kHz, 2.5 kHz, 6.3 kHz and 16 kHz, each -10...10.
    public private(set) var eqBands: [Int] = []
    /// Band values last reported for each preset, so a preset switch can show its curve immediately.
    @ObservationIgnored private var presetBands: [EQPreset: [Int]] = [:]
    public private(set) var eqStepCount = 21

    // Audio
    public private(set) var upscalingType: UpscalingType?
    public private(set) var upscalingEnabled = false
    public private(set) var upscalingAvailable = true
    public private(set) var connectionPriority: ConnectionPriority = .soundQuality

    // Playback
    public private(set) var volume = 0
    public private(set) var playback: PlaybackState = .unsettled
    public private(set) var trackTitle = ""
    public private(set) var trackAlbum = ""
    public private(set) var trackArtist = ""

    // System
    public private(set) var autoPowerOff: AutoPowerOff?
    private var autoPowerOffLastSelected: UInt8 = 0x00
    public private(set) var pauseWhenTakenOff = true
    public private(set) var voiceAssistant: VoiceAssistant = .deviceDefault
    public private(set) var voiceAssistantOptions: [VoiceAssistant] = []
    public private(set) var quickAccessDoubleTap: QuickAccessService = .off
    public private(set) var quickAccessTripleTap: QuickAccessService = .off
    public private(set) var quickAccessDoubleTapOptions: [QuickAccessService] = []
    public private(set) var quickAccessTripleTapOptions: [QuickAccessService] = []
    public private(set) var generalSettings: [GeneralSetting] = []

    // Table 2
    public private(set) var voiceGuidance = true
    public private(set) var voiceGuidanceLanguage: VoiceGuidanceLanguage = .english
    public private(set) var voiceGuidanceLanguages: [VoiceGuidanceLanguage] = []
    public private(set) var pairedDevices: [PairedDevice] = []
    public private(set) var pairingMode = false
    public private(set) var sourceSwitchEnabled = true
    public private(set) var soundPressure: Int?
    public private(set) var linkAutoSwitch: Bool?

    /// A confirmation the headset is waiting for; answer with `respond(to:accept:)`.
    public private(set) var pendingAlert: HeadsetAlert?

    private var refreshTask: Task<Void, Never>?

    public init(device: IOBluetoothDevice) {
        connection = MDRConnection(device: device)
        modelName = device.name ?? "Headphones"
        address = device.addressString?.uppercased().replacingOccurrences(of: "-", with: ":") ?? ""
        connection.onMessage = { [weak self] table, payload in self?.handle(table, payload) }
        connection.onClose = { [weak self] in
            guard let self else { return }
            refreshTask?.cancel()
            if state != .disconnected(nil) { state = .disconnected(nil) }
        }
    }

    public func supports(_ f: T1Function) -> Bool { t1.contains(f) }
    public func supports(_ f: T2Function) -> Bool { t2.contains(f) }

    public var supportsNoiseControl: Bool {
        supports(.ncAsmDualLevel) || supports(.ncAsmDualLevelNoiseAdaptation) || supports(.ambientSoundLevel)
    }
    public var supportsEqualizer: Bool { supports(.presetEQ) || supports(.presetEQNonCustomizable) }
    public var supportsVoiceGuidance: Bool {
        supports(.voiceGuidanceLanguageSwitch) || supports(.voiceGuidanceLanguageSwitchAndVolume) || supports(.voiceGuidanceNoLanguageSwitch)
    }
    public var supportsPairedDevices: Bool {
        supports(.pairingDeviceManagementWithCoD) || supports(.pairingDeviceManagementWithCoDLE) || supports(.pairingDeviceManagementClassic)
    }

    // MARK: Lifecycle

    public func connect() async {
        state = .connecting
        do {
            try await connection.open()
            try await initialSync()
            state = .ready
            startRefreshing()
        } catch {
            connection.close()
            state = .disconnected(error.localizedDescription)
        }
    }

    public func disconnect() {
        refreshTask?.cancel()
        connection.close()
        state = .disconnected(nil)
    }

    private func initialSync() async throws {
        _ = try await connection.query(MDRCommand.protocolInfo)
        try? await q(MDRCommand.capabilityInfo)
        try? await q(MDRCommand.firmwareVersion)
        try? await q(MDRCommand.modelName)
        _ = try await connection.query(MDRCommand.supportFunctions)
        if hasTable2 { try? await q(MDRCommand.supportFunctionsT2, .table2) }

        if supports(.fixedMessage) { try? await connection.send(MDRCommand.enableAlerts) }
        for id: UInt8 in 0xD1...0xD4 where t1.contains(T1Function(rawValue: id)!) {
            try? await q(MDRCommand.generalSettingCapability(id))
            try? await q(MDRCommand.generalSetting(id))
        }
        if supports(.upscalingAutoOff) {
            try? await q(MDRCommand.upscalingCapability)
            try? await q(MDRCommand.upscalingStatus)
            try? await q(MDRCommand.upscaling)
        }
        if supports(.codecIndicator) { try? await q(MDRCommand.codec) }
        if supports(.upscalingIndicator) { try? await q(MDRCommand.upscalingEffect) }
        if supports(.playbackController) {
            try? await q(MDRCommand.volume)
            try? await q(MDRCommand.playbackStatus)
            try? await q(MDRCommand.playbackNames)
        }
        if supportsNoiseControl { try? await q(MDRCommand.noiseControl) }
        if supports(.ambientSoundControlModeSelect) { try? await q(MDRCommand.ncAmbButton) }
        if supports(.smartTalkingModeType2) {
            try? await q(MDRCommand.speakToChat)
            try? await q(MDRCommand.speakToChatConfig)
        }
        if supportsEqualizer {
            try? await q(MDRCommand.eqCapability)
            try? await q(MDRCommand.eqStatus)
            try? await q(MDRCommand.eq)
        }
        if supports(.connectionMode) { try? await q(MDRCommand.connectionPriority) }
        if supports(.autoPowerOffWithWearingDetection) {
            try? await q(MDRCommand.autoPowerOff)
        } else if supports(.autoPowerOff) {
            try? await q(MDRCommand.autoPowerOffLegacy)
        }
        if supports(.playbackControlByWearing) { try? await q(MDRCommand.pauseWhenTakenOff) }
        if supports(.voiceAssistantSettings) {
            try? await q(MDRCommand.voiceAssistantCapability)
            try? await q(MDRCommand.voiceAssistant)
        }
        if supports(.quickAccess) {
            try? await q(MDRCommand.quickAccessCapability)
            try? await q(MDRCommand.quickAccess)
        }
        if supportsVoiceGuidance {
            try? await q(MDRCommand.voiceGuidanceCapability, .table2)
            try? await q(MDRCommand.voiceGuidance, .table2)
        }
        if supportsPairedDevices {
            try? await q(MDRCommand.pairingStatus, .table2)
            try? await q(MDRCommand.pairedDevices, .table2)
        }
        if supports(.sourceSwitchControl) { try? await q(MDRCommand.sourceSwitch, .table2) }
        if supports(.linkAutoSwitchForHeadsets) { try? await q(MDRCommand.linkAutoSwitch, .table2) }
        try await refreshLiveStatus()
    }

    /// Battery, sound pressure and now-playing; not every change is notified.
    public func refreshLiveStatus() async throws {
        if supports(.batteryLevel) { try await q(MDRCommand.battery) }
        if supports(.safeListeningHBS1) { try? await q(MDRCommand.soundPressure, .table2) }
        if supports(.playbackController) { try? await q(MDRCommand.playbackNames) }
    }

    private func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, self.state == .ready else { return }
                try? await self.refreshLiveStatus()
            }
        }
    }

    private func q(_ payload: [UInt8], _ table: MDRDataType = .table1) async throws {
        _ = try await connection.query(payload, table: table)
    }

    private func perform(_ payload: [UInt8], _ table: MDRDataType = .table1) {
        Task {
            do {
                try await connection.send(payload, table: table)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    @ObservationIgnored private var coalescing: [String: [UInt8]] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []

    /// For sliders: while a send for `key` is in flight, only the latest value is kept.
    private func performLatest(_ key: String, _ payload: [UInt8]) {
        coalescing[key] = payload
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        Task {
            while let next = coalescing.removeValue(forKey: key) {
                do {
                    try await connection.send(next)
                } catch {
                    lastError = error.localizedDescription
                }
            }
            inFlight.remove(key)
        }
    }

    public func clearError() { lastError = nil }

    // MARK: Setters

    public func setNoiseControl(_ mode: NoiseMode, ambientLevel level: Int? = nil, focusOnVoice voice: Bool? = nil, dragging: Bool = false) {
        noiseMode = mode
        if let level { ambientLevel = max(1, min(20, level)) }
        if let voice { focusOnVoice = voice }
        performLatest("nc", MDRCommand.setNoiseControl(mode: mode, ambientLevel: ambientLevel, focusOnVoice: focusOnVoice, dragging: dragging))
    }

    public func setNcAmbButton(_ cycle: NcAmbButtonCycle) {
        ncAmbButton = cycle
        perform(MDRCommand.setNcAmbButton(cycle))
    }

    public func setSpeakToChat(_ on: Bool) {
        speakToChat = on
        perform(MDRCommand.setSpeakToChat(on))
    }

    public func setSpeakToChat(sensitivity: SpeakToChatSensitivity? = nil, timeout: SpeakToChatTimeout? = nil) {
        if let sensitivity { speakToChatSensitivity = sensitivity }
        if let timeout { speakToChatTimeout = timeout }
        perform(MDRCommand.setSpeakToChatConfig(sensitivity: speakToChatSensitivity, timeout: speakToChatTimeout))
    }

    public func setEQPreset(_ preset: EQPreset) {
        rememberCuratedEQ(nil)
        eqPreset = preset
        if let cached = presetBands[preset] { eqBands = cached }
        perform(MDRCommand.setEQPreset(preset))
        perform(MDRCommand.eq)
    }

    /// Editing bands of a fixed preset switches the headset to Manual, as Sound Connect does.
    public func setEQBands(_ bands: [Int], preset: EQPreset? = nil) {
        rememberCuratedEQ(nil)
        let target = preset ?? (eqPreset.isCustomizable ? eqPreset : .custom)
        eqPreset = target
        eqBands = bands
        presetBands[target] = bands
        performLatest("eq", MDRCommand.setEQBands(preset: target, bands: bands))
    }

    /// Open1000X presets apply to headsets with Clear Bass plus five bands.
    public var supportsCuratedEQ: Bool { eqBands.count == 6 && eqPresets.contains(.custom) }

    /// The Open1000X preset the user chose, while the Manual slot still holds its curve.
    /// Tracked explicitly: a Manual curve that merely matches a preset is still "Manual".
    public private(set) var activeCuratedEQ: CuratedEQPreset?
    @ObservationIgnored private var curatedEQRestored = false
    /// Set once the headset reports the chosen curve; replies to earlier commands can arrive
    /// after a preset is chosen and must not clear it.
    @ObservationIgnored private var curatedEQConfirmed = false
    private var curatedEQKey: String { "curatedEQ.\(address)" }

    private func rememberCuratedEQ(_ preset: CuratedEQPreset?) {
        guard activeCuratedEQ != preset else { return }
        activeCuratedEQ = preset
        UserDefaults.standard.set(preset?.id, forKey: curatedEQKey)
    }

    /// Keeps the chosen preset in step with what the headset reports.
    private func reconcileCuratedEQ() {
        if let chosen = activeCuratedEQ {
            if eqPreset == .custom && eqBands == chosen.steps {
                curatedEQConfirmed = true
            } else if curatedEQConfirmed {
                rememberCuratedEQ(nil)
            }
        } else if !curatedEQRestored {
            // First report after connecting: restore the choice from a previous session.
            curatedEQRestored = true
            if eqPreset == .custom,
               let id = UserDefaults.standard.string(forKey: curatedEQKey),
               let saved = CuratedEQPreset.all.first(where: { $0.id == id }), saved.steps == eqBands {
                activeCuratedEQ = saved
                curatedEQConfirmed = true
            }
        }
    }

    public var eqPresetName: String { activeCuratedEQ?.name ?? eqPreset.label }

    public func apply(_ preset: CuratedEQPreset) {
        setEQBands(preset.steps, preset: .custom)
        curatedEQRestored = true
        curatedEQConfirmed = false
        rememberCuratedEQ(preset)
    }

    public func setUpscaling(_ on: Bool) {
        upscalingEnabled = on
        perform(MDRCommand.setUpscaling(on))
    }

    public func setConnectionPriority(_ p: ConnectionPriority) {
        connectionPriority = p
        perform(MDRCommand.setConnectionPriority(p))
    }

    public func setVolume(_ v: Int) {
        volume = max(0, min(30, v))
        performLatest("volume", MDRCommand.setVolume(volume))
    }

    public func sendPlayback(_ control: PlaybackControl) {
        perform(MDRCommand.playback(control))
    }

    public func setAutoPowerOff(_ v: AutoPowerOff) {
        autoPowerOff = v
        if v != .whenRemoved && v != .disabled { autoPowerOffLastSelected = v.rawValue }
        perform(MDRCommand.setAutoPowerOff(v, lastSelected: autoPowerOffLastSelected,
                                           wearingDetection: supports(.autoPowerOffWithWearingDetection)))
    }

    public func setPauseWhenTakenOff(_ on: Bool) {
        pauseWhenTakenOff = on
        perform(MDRCommand.setPauseWhenTakenOff(on))
    }

    public func setVoiceAssistant(_ va: VoiceAssistant) {
        voiceAssistant = va
        perform(MDRCommand.setVoiceAssistant(va))
    }

    public func setQuickAccess(doubleTap: QuickAccessService? = nil, tripleTap: QuickAccessService? = nil) {
        if let doubleTap { quickAccessDoubleTap = doubleTap }
        if let tripleTap { quickAccessTripleTap = tripleTap }
        perform(MDRCommand.setQuickAccess(doubleTap: quickAccessDoubleTap, tripleTap: quickAccessTripleTap))
    }

    public func setGeneralSetting(_ id: UInt8, _ on: Bool) {
        if let i = generalSettings.firstIndex(where: { $0.id == id }) { generalSettings[i].isOn = on }
        perform(MDRCommand.setGeneralSetting(id, on))
    }

    public func setVoiceGuidance(_ on: Bool, language: VoiceGuidanceLanguage? = nil) {
        voiceGuidance = on
        if let language { voiceGuidanceLanguage = language }
        perform(MDRCommand.setVoiceGuidance(on, language: voiceGuidanceLanguage), .table2)
    }

    public func setPairingMode(_ on: Bool) {
        pairingMode = on
        perform(MDRCommand.setPairingMode(on), .table2)
    }

    public func switchAudio(to device: PairedDevice) {
        perform(MDRCommand.switchSource(to: device.address), .table2)
    }

    public func perform(_ action: MDRCommand.DeviceAction, on device: PairedDevice) {
        perform(MDRCommand.device(action, address: device.address), .table2)
        Task {
            try? await Task.sleep(for: .seconds(2))
            try? await q(MDRCommand.pairedDevices, .table2)
        }
    }

    public func setSourceSwitch(_ on: Bool) {
        sourceSwitchEnabled = on
        perform(MDRCommand.setSourceSwitch(on), .table2)
    }

    public func respond(to alert: HeadsetAlert, accept: Bool) {
        pendingAlert = nil
        perform(MDRCommand.alertResponse(messageType: alert.messageType, accept: accept))
    }

    public func powerOff() { perform(MDRCommand.powerOff) }
    public func resetSettings() { perform(MDRCommand.resetSettings(factory: false)) }
    public func factoryReset() { perform(MDRCommand.resetSettings(factory: true)) }

    // MARK: Parsing

    func handle(_ table: MDRDataType, _ p: [UInt8]) {
        guard p.count >= 2 else { return }
        do {
            switch table {
            case .table1: try handleT1(p)
            case .table2: try handleT2(p)
            case .ack: break
            }
        } catch {
            connection.trace?("parse error for \(hex(p)): \(error)")
        }
    }

    private func handleT1(_ p: [UInt8]) throws {
        var r = ByteReader(p, offset: 2)
        switch (p[0], p[1]) {
        case (C1.connectRetProtocolInfo, _):
            let v = try r.take(4)
            protocolVersion = v.reduce(0) { $0 << 8 | UInt32($1) }
            _ = try r.u8()
            hasTable2 = (try? r.u8()) == 0x00
        case (C1.connectRetDeviceInfo, 0x01):
            modelName = try r.string()
        case (C1.connectRetDeviceInfo, 0x02):
            firmwareVersion = try r.string()
        case (C1.connectRetSupportFunction, _):
            t1 = Set(try Self.supportFunctions(&r).compactMap(T1Function.init))

        case (C1.commonRetStatus, 0x02), (C1.commonNtfyStatus, 0x02):
            codec = AudioCodec(rawValue: try r.u8()) ?? .other
        case (C1.commonRetStatus, 0x03), (C1.commonNtfyStatus, 0x03):
            _ = try r.u8()
            upscalingActive = try r.u8() == 0x01

        case (C1.powerRetStatus, 0x00), (C1.powerNtfyStatus, 0x00):
            battery = Int(try r.u8())
            charging = ChargingStatus(rawValue: try r.u8()) ?? .unknown
        case (C1.powerRetParam, 0x04), (C1.powerNtfyParam, 0x04), (C1.powerRetParam, 0x05), (C1.powerNtfyParam, 0x05):
            autoPowerOff = AutoPowerOff(rawValue: try r.u8())
            autoPowerOffLastSelected = try r.u8()

        case (C1.eqRetCapability, 0x00):
            _ = try r.u8()                      // band count
            eqStepCount = Int(try r.u8())
            let n = Int(try r.u8())
            eqPresets = try (0..<n).map { _ in
                let id = try r.u8()
                _ = try r.string()              // localized name, empty on XM5
                return EQPreset(rawValue: id)
            }
        case (C1.eqRetStatus, 0x00), (C1.eqNtfyStatus, 0x00):
            eqAvailable = try r.u8() == 0x00
        case (C1.eqRetParam, 0x00), (C1.eqNtfyParam, 0x00):
            eqPreset = EQPreset(rawValue: try r.u8())
            let steps = try r.podArray()
            let offset = steps.count == 10 ? 6 : 10
            if !steps.isEmpty {
                eqBands = steps.map { Int($0) - offset }
                presetBands[eqPreset] = eqBands
                reconcileCuratedEQ()
            }

        case (C1.ncAsmRetParam, 0x17), (C1.ncAsmNtfyParam, 0x17):
            _ = try r.u8()                      // value change status
            let on = try r.u8() == 0x01
            let ambient = try r.u8() == 0x01
            focusOnVoice = try r.u8() == 0x01
            ambientLevel = Int(try r.u8())
            noiseMode = !on ? .off : ambient ? .ambient : .noiseCancelling
        case (C1.ncAsmRetParam, 0x30), (C1.ncAsmNtfyParam, 0x30):
            ncAmbButton = NcAmbButtonCycle(rawValue: try r.u8())

        case (C1.alertNtfyParam, 0x00):
            let type = try r.u8()
            let action = try r.u8()
            pendingAlert = HeadsetAlert(messageType: type, needsAnswer: action == 0x01)

        case (C1.playRetStatus, 0x01), (C1.playNtfyStatus, 0x01):
            _ = try r.u8()
            playback = PlaybackState(rawValue: try r.u8()) ?? .unsettled
        case (C1.playRetParam, 0x01), (C1.playNtfyParam, 0x01):
            var names: [String] = []
            while r.remaining > 0 && names.count < 4 {
                let status = try r.u8()
                let name = try r.string()
                names.append(status == 0x02 ? name : "")
            }
            trackTitle = names.count > 0 ? names[0] : ""
            trackAlbum = names.count > 1 ? names[1] : ""
            trackArtist = names.count > 2 ? names[2] : ""
        case (C1.playRetParam, 0x20), (C1.playNtfyParam, 0x20):
            volume = Int(try r.u8())

        case (C1.gsRetCapability, _):
            let id = p[1]
            _ = try r.u8(); _ = try r.u8()      // setting type, string format
            let key = try r.string()
            let summary = (try? r.string()) ?? ""
            if let i = generalSettings.firstIndex(where: { $0.id == id }) {
                generalSettings[i] = GeneralSetting(id: id, key: key, summaryKey: summary, isOn: generalSettings[i].isOn)
            } else {
                generalSettings.append(GeneralSetting(id: id, key: key, summaryKey: summary, isOn: false))
                generalSettings.sort { $0.id < $1.id }
            }
        case (C1.gsRetParam, _), (C1.gsNtfyParam, _):
            _ = try r.u8()
            let on = try r.u8() == 0x00
            if let i = generalSettings.firstIndex(where: { $0.id == p[1] }) { generalSettings[i].isOn = on }

        case (C1.audioRetCapability, 0x01):
            upscalingType = UpscalingType(rawValue: try r.u8())
        case (C1.audioRetStatus, 0x01), (C1.audioNtfyStatus, 0x01):
            upscalingAvailable = try r.u8() == 0x00
        case (C1.audioRetParam, 0x00), (C1.audioNtfyParam, 0x00):
            connectionPriority = ConnectionPriority(rawValue: try r.u8()) ?? .soundQuality
        case (C1.audioRetParam, 0x01), (C1.audioNtfyParam, 0x01):
            upscalingEnabled = try r.u8() == 0x01

        case (C1.systemRetCapability, 0x04):
            _ = try r.u8()                      // key type
            voiceAssistantOptions = try r.podArray().compactMap(VoiceAssistant.init)
        case (C1.systemRetCapability, 0x0D):
            _ = try r.u8(); _ = try r.u8()      // key, key type
            let n = Int(try r.u8())
            for _ in 0..<n {
                let action = try r.u8()
                _ = try r.u8()                  // default function
                let options = try r.podArray().map(QuickAccessService.init)
                if action == 0x01 { quickAccessDoubleTapOptions = options }
                if action == 0x02 { quickAccessTripleTapOptions = options }
            }
        case (C1.systemRetParam, 0x01), (C1.systemNtfyParam, 0x01):
            pauseWhenTakenOff = try r.u8() == 0x00
        case (C1.systemRetParam, 0x04), (C1.systemNtfyParam, 0x04):
            voiceAssistant = VoiceAssistant(rawValue: try r.u8()) ?? .none
        case (C1.systemRetParam, 0x0C), (C1.systemNtfyParam, 0x0C):
            speakToChat = try r.u8() == 0x00
        case (C1.systemRetExtParam, 0x0C), (C1.systemNtfyExtParam, 0x0C):
            speakToChatSensitivity = SpeakToChatSensitivity(rawValue: try r.u8()) ?? .auto
            speakToChatTimeout = SpeakToChatTimeout(rawValue: try r.u8()) ?? .standard
        case (C1.systemRetParam, 0x0D), (C1.systemNtfyParam, 0x0D):
            let functions = try r.podArray()
            if functions.count > 0 { quickAccessDoubleTap = QuickAccessService(rawValue: functions[0]) }
            if functions.count > 1 { quickAccessTripleTap = QuickAccessService(rawValue: functions[1]) }
        default:
            break
        }
    }

    private func handleT2(_ p: [UInt8]) throws {
        var r = ByteReader(p, offset: 2)
        switch (p[0], p[1]) {
        case (C2.connectRetSupportFunction, _):
            t2 = Set(try Self.supportFunctions(&r).compactMap(T2Function.init))

        case (C2.vgRetCapability, 0x01):
            _ = try r.take(5)
            voiceGuidanceLanguages = try r.podArray().compactMap(VoiceGuidanceLanguage.init)
        case (C2.vgRetParam, 0x01), (C2.vgNtfyParam, 0x01):
            voiceGuidance = try r.u8() == 0x00
            if r.remaining > 0 { voiceGuidanceLanguage = VoiceGuidanceLanguage(rawValue: try r.u8()) ?? .undefined }

        case (C2.periRetStatus, 0x02), (C2.periNtfyStatus, 0x02), (C2.periRetStatus, 0x00), (C2.periNtfyStatus, 0x00):
            pairingMode = try r.u8() == 0x01
        case (C2.periRetParam, 0x02), (C2.periNtfyParam, 0x02):
            let n = Int(try r.u8())
            var raw: [(String, UInt8, UInt32, String)] = []
            for _ in 0..<n {
                let addr = try r.ascii(17)
                let status = try r.u8()
                let cod = try r.u24()
                let name = try r.string()
                raw.append((addr, status, cod, name))
            }
            let playing = (try? r.u8()) ?? 0
            pairedDevices = raw.map { addr, status, cod, name in
                PairedDevice(address: addr, name: name, isConnected: status != 0,
                             isPlaying: status != 0 && status == playing, classOfDevice: cod)
            }
        case (C2.periRetParam, 0x01), (C2.periNtfyParam, 0x01):
            sourceSwitchEnabled = try r.u8() != 0
        case (C2.periNtfyExtParam, 0x01):
            _ = try r.u8()                      // result
            let target = try r.ascii(17)
            pairedDevices = pairedDevices.map {
                PairedDevice(address: $0.address, name: $0.name, isConnected: $0.isConnected,
                             isPlaying: $0.address == target, classOfDevice: $0.classOfDevice)
            }

        case (C2.slRetExtParam, _):
            // Error causes 0-2 are not playing, in a call, and taken off.
            let level = Int(try r.u8())
            let cause = (try? r.u8()) ?? 0xFF
            soundPressure = level > 0 && cause > 0x02 ? level : nil
        case (C2.systemRetParam, 0x0A), (C2.systemNtfyParam, 0x0A):
            linkAutoSwitch = try r.u8() == 0x00
        default:
            break
        }
    }

    private static func supportFunctions(_ r: inout ByteReader) throws -> [UInt8] {
        let n = Int(try r.u8())
        return try (0..<n).map { _ in
            let f = try r.u8()
            _ = try r.u8()                      // UI priority
            return f
        }
    }
}
