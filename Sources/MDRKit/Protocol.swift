// Sony MDR protocol v2 vocabulary.
// Values come from mos9527/SonyHeadphonesClient (MIT), which generated them from
// Sound Connect's own metadata, and were checked against a WH-1000XM5 (fw 2.4.1).

/// Table 1 support function IDs (`CONNECT_RET_SUPPORT_FUNCTION` on 0x0C).
public enum T1Function: UInt8, Sendable, CaseIterable {
    case codecIndicator = 0x12
    case upscalingIndicator = 0x13
    case batteryLevel = 0x20
    case leftRightBattery = 0x21
    case cradleBattery = 0x22
    case powerOff = 0x23
    case autoPowerOff = 0x24
    case autoPowerOffWithWearingDetection = 0x25
    case batteryLevelWithThreshold = 0x28
    case presetEQ = 0x50
    case presetEQNonCustomizable = 0x52
    case ncAsmDualLevel = 0x6B
    case ncAsmDualLevelNoiseAdaptation = 0x6D
    case ambientSoundLevel = 0x67
    case ambientSoundControlModeSelect = 0x69
    case autoNcAsm = 0x70
    case fixedMessage = 0x90
    case playbackController = 0xA1
    case sar = 0xB0
    case generalSetting1 = 0xD1
    case generalSetting2 = 0xD2
    case generalSetting3 = 0xD3
    case generalSetting4 = 0xD4
    case connectionMode = 0xE1
    case upscalingAutoOff = 0xE2
    case playbackControlByWearing = 0xF1
    case voiceAssistantSettings = 0xF4
    case resetSettings = 0xF9
    case smartTalkingModeType2 = 0xFC
    case quickAccess = 0xFD
}

/// Table 2 support function IDs (`CONNECT_RET_SUPPORT_FUNCTION` on 0x0E).
public enum T2Function: UInt8, Sendable, CaseIterable {
    case pairingDeviceManagementClassic = 0x30
    case sourceSwitchControl = 0x31
    case pairingDeviceManagementWithCoD = 0x32
    case pairingDeviceManagementWithCoDLE = 0x33
    case voiceGuidanceNoLanguageSwitch = 0x40
    case voiceGuidanceLanguageSwitch = 0x41
    case voiceGuidanceLanguageSwitchAndVolume = 0x42
    case safeListeningHBS1 = 0x50
    case safeListeningHBS2 = 0x52
    case linkAutoSwitchForHeadsets = 0xF8
}

/// Table 1 command bytes (first payload byte).
enum C1 {
    static let connectGetProtocolInfo: UInt8 = 0x00, connectRetProtocolInfo: UInt8 = 0x01
    static let connectGetCapabilityInfo: UInt8 = 0x02, connectRetCapabilityInfo: UInt8 = 0x03
    static let connectGetDeviceInfo: UInt8 = 0x04, connectRetDeviceInfo: UInt8 = 0x05
    static let connectGetSupportFunction: UInt8 = 0x06, connectRetSupportFunction: UInt8 = 0x07
    static let commonGetStatus: UInt8 = 0x12, commonRetStatus: UInt8 = 0x13, commonNtfyStatus: UInt8 = 0x15
    static let powerGetStatus: UInt8 = 0x22, powerRetStatus: UInt8 = 0x23, powerSetStatus: UInt8 = 0x24, powerNtfyStatus: UInt8 = 0x25
    static let powerGetParam: UInt8 = 0x26, powerRetParam: UInt8 = 0x27, powerSetParam: UInt8 = 0x28, powerNtfyParam: UInt8 = 0x29
    static let eqGetCapability: UInt8 = 0x50, eqRetCapability: UInt8 = 0x51
    static let eqGetStatus: UInt8 = 0x52, eqRetStatus: UInt8 = 0x53, eqNtfyStatus: UInt8 = 0x55
    static let eqGetParam: UInt8 = 0x56, eqRetParam: UInt8 = 0x57, eqSetParam: UInt8 = 0x58, eqNtfyParam: UInt8 = 0x59
    static let ncAsmGetParam: UInt8 = 0x66, ncAsmRetParam: UInt8 = 0x67, ncAsmSetParam: UInt8 = 0x68, ncAsmNtfyParam: UInt8 = 0x69
    static let alertSetStatus: UInt8 = 0x94, alertSetParam: UInt8 = 0x98, alertNtfyParam: UInt8 = 0x99
    static let playGetStatus: UInt8 = 0xA2, playRetStatus: UInt8 = 0xA3, playSetStatus: UInt8 = 0xA4, playNtfyStatus: UInt8 = 0xA5
    static let playGetParam: UInt8 = 0xA6, playRetParam: UInt8 = 0xA7, playSetParam: UInt8 = 0xA8, playNtfyParam: UInt8 = 0xA9
    static let logSetStatus: UInt8 = 0xC4
    static let gsGetCapability: UInt8 = 0xD0, gsRetCapability: UInt8 = 0xD1
    static let gsGetParam: UInt8 = 0xD6, gsRetParam: UInt8 = 0xD7, gsSetParam: UInt8 = 0xD8, gsNtfyParam: UInt8 = 0xD9
    static let audioGetCapability: UInt8 = 0xE0, audioRetCapability: UInt8 = 0xE1
    static let audioGetStatus: UInt8 = 0xE2, audioRetStatus: UInt8 = 0xE3, audioNtfyStatus: UInt8 = 0xE5
    static let audioGetParam: UInt8 = 0xE6, audioRetParam: UInt8 = 0xE7, audioSetParam: UInt8 = 0xE8, audioNtfyParam: UInt8 = 0xE9
    static let systemGetCapability: UInt8 = 0xF0, systemRetCapability: UInt8 = 0xF1
    static let systemGetParam: UInt8 = 0xF6, systemRetParam: UInt8 = 0xF7, systemSetParam: UInt8 = 0xF8, systemNtfyParam: UInt8 = 0xF9
    static let systemGetExtParam: UInt8 = 0xFA, systemRetExtParam: UInt8 = 0xFB, systemSetExtParam: UInt8 = 0xFC, systemNtfyExtParam: UInt8 = 0xFD
}

/// Table 2 command bytes.
enum C2 {
    static let connectGetSupportFunction: UInt8 = 0x06, connectRetSupportFunction: UInt8 = 0x07
    static let periGetStatus: UInt8 = 0x32, periRetStatus: UInt8 = 0x33, periSetStatus: UInt8 = 0x34, periNtfyStatus: UInt8 = 0x35
    static let periGetParam: UInt8 = 0x36, periRetParam: UInt8 = 0x37, periSetParam: UInt8 = 0x38, periNtfyParam: UInt8 = 0x39
    static let periSetExtParam: UInt8 = 0x3C, periNtfyExtParam: UInt8 = 0x3D
    static let vgGetCapability: UInt8 = 0x40, vgRetCapability: UInt8 = 0x41
    static let vgGetParam: UInt8 = 0x46, vgRetParam: UInt8 = 0x47, vgSetParam: UInt8 = 0x48, vgNtfyParam: UInt8 = 0x49
    static let slGetParam: UInt8 = 0x56, slRetParam: UInt8 = 0x57, slNtfyParam: UInt8 = 0x59
    static let slGetExtParam: UInt8 = 0x5A, slRetExtParam: UInt8 = 0x5B
    static let systemGetParam: UInt8 = 0xF6, systemRetParam: UInt8 = 0xF7, systemSetParam: UInt8 = 0xF8, systemNtfyParam: UInt8 = 0xF9
}

// MARK: - Values

public enum NoiseMode: String, Sendable, CaseIterable, Identifiable {
    case noiseCancelling, ambient, off
    public var id: Self { self }
    public var label: String {
        switch self {
        case .noiseCancelling: "Noise Cancelling"
        case .ambient: "Ambient Sound"
        case .off: "Off"
        }
    }
}

/// What the NC/AMB button cycles through.
public enum NcAmbButtonCycle: UInt8, Sendable, CaseIterable, Identifiable {
    case ncAmbientOff = 0x01
    case ncAmbient = 0x02
    case ncOff = 0x03
    case ambientOff = 0x04
    public var id: Self { self }
    public var label: String {
        switch self {
        case .ncAmbientOff: "Noise Cancelling → Ambient → Off"
        case .ncAmbient: "Noise Cancelling ↔ Ambient"
        case .ncOff: "Noise Cancelling ↔ Off"
        case .ambientOff: "Ambient ↔ Off"
        }
    }
}

public enum AudioCodec: UInt8, Sendable {
    case unsettled = 0x00, sbc = 0x01, aac = 0x02, ldac = 0x10, aptX = 0x20, aptXHD = 0x21, lc3 = 0x30, other = 0xFF
    public var label: String {
        switch self {
        case .unsettled: "—"
        case .sbc: "SBC"
        case .aac: "AAC"
        case .ldac: "LDAC"
        case .aptX: "aptX"
        case .aptXHD: "aptX HD"
        case .lc3: "LC3"
        case .other: "Other"
        }
    }
}

public enum ChargingStatus: UInt8, Sendable {
    case notCharging = 0x00, charging = 0x01, unknown = 0x02, charged = 0x03
}

public enum SpeakToChatSensitivity: UInt8, Sendable, CaseIterable, Identifiable {
    case auto = 0x00, high = 0x01, low = 0x02
    public var id: Self { self }
    public var label: String {
        switch self {
        case .auto: "Auto"
        case .high: "High"
        case .low: "Low"
        }
    }
}

public enum SpeakToChatTimeout: UInt8, Sendable, CaseIterable, Identifiable {
    case short = 0x00, standard = 0x01, long = 0x02, never = 0x03
    public var id: Self { self }
    public var label: String {
        switch self {
        case .short: "Short (about 5 s)"
        case .standard: "Standard (about 15 s)"
        case .long: "Long (about 30 s)"
        case .never: "Don't end automatically"
        }
    }
}

public enum AutoPowerOff: UInt8, Sendable, CaseIterable, Identifiable {
    case after5Min = 0x00, after15Min = 0x04, after30Min = 0x01, after60Min = 0x02, after180Min = 0x03
    case whenRemoved = 0x10, disabled = 0x11
    public var id: Self { self }
    public var label: String {
        switch self {
        case .after5Min: "After 5 minutes"
        case .after15Min: "After 15 minutes"
        case .after30Min: "After 30 minutes"
        case .after60Min: "After 1 hour"
        case .after180Min: "After 3 hours"
        case .whenRemoved: "When taken off"
        case .disabled: "Never"
        }
    }
}

public enum ConnectionPriority: UInt8, Sendable, CaseIterable, Identifiable {
    case soundQuality = 0x00, stableConnection = 0x01
    public var id: Self { self }
    public var label: String {
        switch self {
        case .soundQuality: "Prioritize Sound Quality"
        case .stableConnection: "Prioritize Stable Connection"
        }
    }
}

public enum UpscalingType: UInt8, Sendable {
    case dseeHX = 0x00, dsee = 0x01, dseeHXAI = 0x02, dseeUltimate = 0x03
    public var label: String {
        switch self {
        case .dseeHX: "DSEE HX"
        case .dsee: "DSEE"
        case .dseeHXAI: "DSEE Extreme"
        case .dseeUltimate: "DSEE Ultimate"
        }
    }
}

public enum VoiceAssistant: UInt8, Sendable, Identifiable {
    case deviceDefault = 0x30, googleAssistant = 0x31, alexa = 0x32, tencentXiaowei = 0x33
    case sonyVoiceAssistant = 0x34, enabledInOtherDevice = 0x3F, none = 0xFF
    public var id: Self { self }
    public var label: String {
        switch self {
        case .deviceDefault: "Voice assistant of your device (Siri)"
        case .googleAssistant: "Google Assistant"
        case .alexa: "Amazon Alexa"
        case .tencentXiaowei: "Tencent Xiaowei"
        case .sonyVoiceAssistant: "Sony voice assistant"
        case .enabledInOtherDevice: "Set on another device"
        case .none: "Off"
        }
    }
}

public enum PlaybackState: UInt8, Sendable {
    case unsettled = 0x00, playing = 0x01, paused = 0x02, stopped = 0x03
}

public enum PlaybackControl: UInt8, Sendable {
    case pause = 0x01, nextTrack = 0x02, previousTrack = 0x03, play = 0x07
}

public enum VoiceGuidanceLanguage: UInt8, Sendable, Identifiable {
    case undefined = 0x00, english = 0x01, french = 0x02, german = 0x03, spanish = 0x04, italian = 0x05
    case portuguese = 0x06, dutch = 0x07, swedish = 0x08, finnish = 0x09, russian = 0x0A, japanese = 0x0B
    case brazilianPortuguese = 0x0D, korean = 0x0F, turkish = 0x10, chinese = 0xF0
    public var id: Self { self }
    public var label: String {
        switch self {
        case .undefined: "—"
        case .english: "English"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        case .italian: "Italiano"
        case .portuguese: "Português"
        case .dutch: "Nederlands"
        case .swedish: "Svenska"
        case .finnish: "Suomi"
        case .russian: "Русский"
        case .japanese: "日本語"
        case .brazilianPortuguese: "Português (Brasil)"
        case .korean: "한국어"
        case .turkish: "Türkçe"
        case .chinese: "中文"
        }
    }
}

/// Quick Access services. Sound Connect only documents Spotify Tap publicly;
/// other IDs the headset offers are shown by number.
public struct QuickAccessService: Hashable, Sendable, Identifiable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public var id: UInt8 { rawValue }
    public static let off = QuickAccessService(rawValue: 0x00)
    public static let spotify = QuickAccessService(rawValue: 0x01)
    public var label: String {
        switch rawValue {
        case 0x00: "Off"
        case 0x01: "Spotify Tap"
        default: "Service \(rawValue)"
        }
    }
}

public struct EQPreset: Hashable, Sendable, Identifiable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public var id: UInt8 { rawValue }
    public static let off = EQPreset(rawValue: 0x00)
    public static let custom = EQPreset(rawValue: 0xA0)
    public var isCustomizable: Bool { (0xA0...0xA5).contains(rawValue) }
    public var label: String {
        switch rawValue {
        case 0x00: "Off"
        case 0x01: "Rock"
        case 0x02: "Pop"
        case 0x03: "Jazz"
        case 0x04: "Dance"
        case 0x05: "EDM"
        case 0x06: "R&B/Hip-Hop"
        case 0x07: "Acoustic"
        case 0x10: "Bright"
        case 0x11: "Excited"
        case 0x12: "Mellow"
        case 0x13: "Relaxed"
        case 0x14: "Vocal"
        case 0x15: "Treble Boost"
        case 0x16: "Bass Boost"
        case 0x17: "Speech"
        case 0x20: "Gaming"
        case 0xA0: "Manual"
        case 0xA1: "Custom 1"
        case 0xA2: "Custom 2"
        case 0xA3: "Custom 3"
        case 0xA4: "Custom 4"
        case 0xA5: "Custom 5"
        default: String(format: "Preset %02X", rawValue)
        }
    }
}

/// Equalizer curves that ship with Open1000X. They are written to the headset's
/// Manual slot, so the user's own Custom slots are never overwritten.
public struct CuratedEQPreset: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    public let clearBass: Int
    /// 400 Hz, 1 kHz, 2.5 kHz, 6.3 kHz, 16 kHz.
    public let bands: [Int]

    /// In the order the headset uses: Clear Bass first.
    public var steps: [Int] { [clearBass] + bands }

    public static let punch = CuratedEQPreset(
        id: "punch", name: "Punch", summary: "Deep Clear Bass with crisp, airy highs.",
        clearBass: 8, bands: [-2, 3, 4, 0, 9])
    public static let clarity = CuratedEQPreset(
        id: "clarity", name: "Clarity", summary: "Lean bass, forward vocals and open highs.",
        clearBass: -6, bands: [-2, 2, 3, 0, 7])

    public static let all = [punch, clarity]
}

/// Confirmation prompts the headset raises before disruptive changes.
public struct HeadsetAlert: Sendable, Equatable, Identifiable {
    public let messageType: UInt8
    public let needsAnswer: Bool
    public var id: UInt8 { messageType }

    public var message: String {
        switch messageType {
        case 0x00: "The headset will disconnect briefly to change the connection mode."
        case 0x01: "The headset will disconnect briefly to change the button assignment."
        case 0x06, 0x07: "The headset will disconnect briefly to change the multipoint setting."
        case 0x08, 0x2B: "Battery life will be shorter with this sound setting."
        case 0x0A, 0x0B: "The touch sensor control panel will be turned off."
        case 0x0C, 0x0D: "The touch sensor control panel will be turned on."
        case 0x16, 0x17, 0x18: "The voice assistant will be changed."
        case 0x1C, 0x2A: "LDAC is not available with this connection setting."
        case 0x70, 0x72: "With two devices connected, LDAC runs at a lower bitrate."
        case 0x71: "Prioritizing sound quality while two devices are connected may reduce stability."
        default: String(format: "The headset asks for confirmation (message 0x%02X).", messageType)
        }
    }
}
