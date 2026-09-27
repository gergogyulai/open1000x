/// Payload builders for MDR v2 commands. Byte layouts mirror Sound Connect's structs.
public enum MDRCommand {
    // MARK: Connect / identity (T1)
    public static let protocolInfo: [UInt8] = [C1.connectGetProtocolInfo, 0x00]
    public static let capabilityInfo: [UInt8] = [C1.connectGetCapabilityInfo, 0x00]
    public static let modelName: [UInt8] = [C1.connectGetDeviceInfo, 0x01]
    public static let firmwareVersion: [UInt8] = [C1.connectGetDeviceInfo, 0x02]
    public static let seriesAndColor: [UInt8] = [C1.connectGetDeviceInfo, 0x03]
    public static let supportFunctions: [UInt8] = [C1.connectGetSupportFunction, 0x00]
    /// Same bytes, sent on table 2.
    public static let supportFunctionsT2: [UInt8] = [C2.connectGetSupportFunction, 0x00]

    // MARK: Status
    public static let codec: [UInt8] = [C1.commonGetStatus, 0x02]
    public static let upscalingEffect: [UInt8] = [C1.commonGetStatus, 0x03]
    public static let battery: [UInt8] = [C1.powerGetStatus, 0x00]
    public static let enableAlerts: [UInt8] = [C1.alertSetStatus, 0x00, 0x00]

    public static func alertResponse(messageType: UInt8, accept: Bool) -> [UInt8] {
        [C1.alertSetParam, 0x00, messageType, accept ? 0x01 : 0x00]
    }

    // MARK: Noise control
    public static let noiseControl: [UInt8] = [C1.ncAsmGetParam, 0x17]
    public static let ncAmbButton: [UInt8] = [C1.ncAsmGetParam, 0x30]

    /// `dragging` marks intermediate slider values (the headset skips the confirmation beep).
    public static func setNoiseControl(mode: NoiseMode, ambientLevel: Int, focusOnVoice: Bool, dragging: Bool = false) -> [UInt8] {
        [C1.ncAsmSetParam, 0x17,
         dragging ? 0x00 : 0x01,
         mode == .off ? 0x00 : 0x01,
         mode == .ambient ? 0x01 : 0x00,
         focusOnVoice ? 0x01 : 0x00,
         UInt8(clamping: ambientLevel)]
    }

    public static func setNcAmbButton(_ cycle: NcAmbButtonCycle) -> [UInt8] {
        [C1.ncAsmSetParam, 0x30, cycle.rawValue]
    }

    // MARK: Equalizer
    public static let eqCapability: [UInt8] = [C1.eqGetCapability, 0x00, 0x01] // + display language: English
    public static let eqStatus: [UInt8] = [C1.eqGetStatus, 0x00]
    public static let eq: [UInt8] = [C1.eqGetParam, 0x00]

    public static func setEQPreset(_ preset: EQPreset) -> [UInt8] {
        [C1.eqSetParam, 0x00, preset.rawValue, 0x00]
    }

    /// `bands` are the raw steps as the headset reports them: for the 1000X
    /// headphones that is Clear Bass followed by five bands, each -10...10.
    public static func setEQBands(preset: EQPreset, bands: [Int], offset: Int = 10) -> [UInt8] {
        [C1.eqSetParam, 0x00, preset.rawValue, UInt8(bands.count)] + bands.map { UInt8(clamping: $0 + offset) }
    }

    // MARK: Audio
    public static let connectionPriority: [UInt8] = [C1.audioGetParam, 0x00]
    public static let upscalingCapability: [UInt8] = [C1.audioGetCapability, 0x01]
    public static let upscalingStatus: [UInt8] = [C1.audioGetStatus, 0x01]
    public static let upscaling: [UInt8] = [C1.audioGetParam, 0x01]

    public static func setConnectionPriority(_ p: ConnectionPriority) -> [UInt8] {
        [C1.audioSetParam, 0x00, p.rawValue]
    }

    public static func setUpscaling(_ on: Bool) -> [UInt8] {
        [C1.audioSetParam, 0x01, on ? 0x01 : 0x00]
    }

    // MARK: Playback
    public static let playbackNames: [UInt8] = [C1.playGetParam, 0x01]
    public static let volume: [UInt8] = [C1.playGetParam, 0x20]
    public static let playbackStatus: [UInt8] = [C1.playGetStatus, 0x01]

    public static func setVolume(_ v: Int) -> [UInt8] {
        [C1.playSetParam, 0x20, UInt8(clamping: v)]
    }

    public static func playback(_ c: PlaybackControl) -> [UInt8] {
        [C1.playSetStatus, 0x01, 0x00, c.rawValue]
    }

    // MARK: Power
    public static let autoPowerOff: [UInt8] = [C1.powerGetParam, 0x05]
    public static let autoPowerOffLegacy: [UInt8] = [C1.powerGetParam, 0x04]
    public static let powerOff: [UInt8] = [C1.powerSetStatus, 0x03, 0x01]

    public static func setAutoPowerOff(_ v: AutoPowerOff, lastSelected: UInt8, wearingDetection: Bool = true) -> [UInt8] {
        wearingDetection
            ? [C1.powerSetParam, 0x05, v.rawValue, lastSelected]
            : [C1.powerSetParam, 0x04, v.rawValue, lastSelected]
    }

    // MARK: General settings (headset-described booleans)
    public static func generalSettingCapability(_ id: UInt8) -> [UInt8] { [C1.gsGetCapability, id, 0x01] }
    public static func generalSetting(_ id: UInt8) -> [UInt8] { [C1.gsGetParam, id] }
    public static func setGeneralSetting(_ id: UInt8, _ on: Bool) -> [UInt8] {
        [C1.gsSetParam, id, 0x00, on ? 0x00 : 0x01]
    }

    // MARK: System
    public static let pauseWhenTakenOff: [UInt8] = [C1.systemGetParam, 0x01]
    public static let voiceAssistantCapability: [UInt8] = [C1.systemGetCapability, 0x04]
    public static let voiceAssistant: [UInt8] = [C1.systemGetParam, 0x04]
    public static let speakToChat: [UInt8] = [C1.systemGetParam, 0x0C]
    public static let speakToChatConfig: [UInt8] = [C1.systemGetExtParam, 0x0C]
    public static let quickAccessCapability: [UInt8] = [C1.systemGetCapability, 0x0D]
    public static let quickAccess: [UInt8] = [C1.systemGetParam, 0x0D]

    public static func setPauseWhenTakenOff(_ on: Bool) -> [UInt8] {
        [C1.systemSetParam, 0x01, on ? 0x00 : 0x01]
    }

    public static func setVoiceAssistant(_ va: VoiceAssistant) -> [UInt8] {
        [C1.systemSetParam, 0x04, va.rawValue]
    }

    public static func setSpeakToChat(_ on: Bool) -> [UInt8] {
        [C1.systemSetParam, 0x0C, on ? 0x00 : 0x01, 0x01]
    }

    public static func setSpeakToChatConfig(sensitivity: SpeakToChatSensitivity, timeout: SpeakToChatTimeout) -> [UInt8] {
        [C1.systemSetExtParam, 0x0C, sensitivity.rawValue, timeout.rawValue]
    }

    public static func setQuickAccess(doubleTap: QuickAccessService, tripleTap: QuickAccessService) -> [UInt8] {
        [C1.systemSetParam, 0x0D, 0x02, doubleTap.rawValue, tripleTap.rawValue]
    }

    public static func resetSettings(factory: Bool) -> [UInt8] {
        [C1.systemSetParam, 0x09, factory ? 0x01 : 0x00]
    }

    // MARK: Table 2
    public static let voiceGuidanceCapability: [UInt8] = [C2.vgGetCapability, 0x01]
    public static let voiceGuidance: [UInt8] = [C2.vgGetParam, 0x01]

    public static func setVoiceGuidance(_ on: Bool, language: VoiceGuidanceLanguage) -> [UInt8] {
        [C2.vgSetParam, 0x01, on ? 0x00 : 0x01, language.rawValue]
    }

    public static let pairingStatus: [UInt8] = [C2.periGetStatus, 0x02]
    public static let pairedDevices: [UInt8] = [C2.periGetParam, 0x02]
    public static let sourceSwitch: [UInt8] = [C2.periGetParam, 0x01]

    public static func setPairingMode(_ on: Bool) -> [UInt8] {
        [C2.periSetStatus, 0x02, on ? 0x01 : 0x00, 0x00]
    }

    public enum DeviceAction: UInt8, Sendable { case disconnect = 0x00, connect = 0x01, unpair = 0x02 }

    public static func device(_ action: DeviceAction, address: String) -> [UInt8] {
        [C2.periSetExtParam, 0x02, action.rawValue] + addressBytes(address)
    }

    /// Makes `address` the device whose audio is playing (multipoint).
    public static func switchSource(to address: String) -> [UInt8] {
        [C2.periSetExtParam, 0x01] + addressBytes(address)
    }

    public static func setSourceSwitch(_ on: Bool) -> [UInt8] {
        [C2.periSetParam, 0x01, on ? 0x01 : 0x00]
    }

    public static let safeListening: [UInt8] = [C2.slGetParam, 0x00]
    public static let soundPressure: [UInt8] = [C2.slGetExtParam, 0x00]
    public static let linkAutoSwitch: [UInt8] = [C2.systemGetParam, 0x0A]

    /// Addresses travel as 17 ASCII characters, e.g. `12:34:56:78:9A:BC`.
    static func addressBytes(_ address: String) -> [UInt8] {
        let normalized = address.uppercased().replacingOccurrences(of: "-", with: ":")
        let bytes = Array(normalized.utf8)
        return Array((bytes + [UInt8](repeating: 0x30, count: 17)).prefix(17))
    }
}
