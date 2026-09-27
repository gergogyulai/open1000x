import MDRKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    static let windowID = "settings"
    let manager: DeviceManager

    enum Pane: String, CaseIterable, Identifiable {
        case sound, noiseControl, speakToChat, controls, devices, system, about
        var id: Self { self }
        var title: String {
            switch self {
            case .sound: "Sound"
            case .noiseControl: "Noise Control"
            case .speakToChat: "Speak-to-Chat"
            case .controls: "Controls"
            case .devices: "Devices"
            case .system: "System"
            case .about: "About"
            }
        }
        var symbol: String {
            switch self {
            case .sound: "slider.vertical.3"
            case .noiseControl: "headphones"
            case .speakToChat: "bubble.left.and.bubble.right"
            case .controls: "hand.tap"
            case .devices: "laptopcomputer.and.iphone"
            case .system: "gearshape"
            case .about: "info.circle"
            }
        }
    }

    @State private var pane: Pane

    init(manager: DeviceManager, pane: Pane = .sound) {
        self.manager = manager
        _pane = State(initialValue: pane)
    }

    var body: some View {
        Group {
            if let h = manager.headphones, h.state == .ready {
                NavigationSplitView {
                    List(visiblePanes(h), selection: $pane) { p in
                        Label(p.title, systemImage: p.symbol).tag(p)
                    }
                    .navigationSplitViewColumnWidth(170)
                } detail: {
                    VStack(spacing: 0) {
                        HeadsetBanners(headphones: h).padding([.horizontal, .top])
                        detail(for: pane, h)
                    }
                    .animation(.smooth, value: h.pendingAlert)
                    .navigationTitle(pane.title)
                    .navigationSubtitle(h.modelName)
                    .toolbar { toolbar(h) }
                }
            } else {
                ContentUnavailableView("No headphones connected", systemImage: "headphones.slash",
                                       description: Text("Turn on your headphones and connect them to this Mac."))
            }
        }
        .frame(width: 720, height: 520)
    }

    @ToolbarContentBuilder
    private func toolbar(_ h: Headphones) -> some ToolbarContent {
        if h.supportsNoiseControl {
            ToolbarItem(placement: .primaryAction) {
                Picker("Noise control", selection: Binding(get: { h.noiseMode }, set: { h.setNoiseControl($0) })) {
                    ForEach(NoiseMode.allCases) { mode in
                        Label(mode.shortLabel, systemImage: mode.symbolName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .help("Noise control")
            }
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            BatteryLabel(level: h.battery, charging: h.charging)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 8)
        }
    }

    private func visiblePanes(_ h: Headphones) -> [Pane] {
        Pane.allCases.filter { p in
            switch p {
            case .noiseControl: h.supportsNoiseControl
            case .speakToChat: h.supports(.smartTalkingModeType2)
            case .devices: h.supportsPairedDevices || !h.generalSettings.isEmpty
            default: true
            }
        }
    }

    @ViewBuilder
    private func detail(for pane: Pane, _ h: Headphones) -> some View {
        switch pane {
        case .sound: SoundPane(h: h)
        case .noiseControl: NoiseControlPane(h: h)
        case .speakToChat: SpeakToChatPane(h: h)
        case .controls: ControlsPane(h: h)
        case .devices: DevicesPane(h: h)
        case .system: SystemPane(h: h)
        case .about: AboutPane(h: h)
        }
    }
}

// MARK: - Panes

private enum EQChoice: Hashable {
    case device(EQPreset)
    case curated(CuratedEQPreset)
}

private struct SoundPane: View {
    let h: Headphones

    var body: some View {
        Form {
            if h.supportsEqualizer {
                Section {
                    Picker("Preset", selection: Binding(
                        get: { h.activeCuratedEQ.map(EQChoice.curated) ?? .device(h.eqPreset) },
                        set: { choice in
                            switch choice {
                            case .device(let preset): h.setEQPreset(preset)
                            case .curated(let preset): h.apply(preset)
                            }
                        }
                    )) {
                        if h.supportsCuratedEQ {
                            Section("Open1000X") {
                                ForEach(CuratedEQPreset.all) { Text($0.name).tag(EQChoice.curated($0)) }
                            }
                        }
                        Section("Headphones") {
                            ForEach(h.eqPresets) { Text($0.label).tag(EQChoice.device($0)) }
                        }
                    }
                    if !h.eqBands.isEmpty {
                        EqualizerEditor(headphones: h)
                            .padding(.vertical, 8)
                            .disabled(!h.eqAvailable)
                    }
                } header: {
                    Text("Equalizer")
                } footer: {
                    Footnote(h.eqAvailable
                         ? "Moving a band on a fixed preset switches to Manual. Clear Bass adjusts low frequencies without muddying vocals."
                         : "The equalizer is unavailable in the current mode.")
                }
            }
            if h.supports(.upscalingAutoOff) {
                Section {
                    Toggle(h.upscalingType?.label ?? "DSEE", isOn: Binding(get: { h.upscalingEnabled }, set: { h.setUpscaling($0) }))
                        .disabled(!h.upscalingAvailable)
                } footer: {
                    Footnote("Restores detail lost in compressed music. Uses slightly more battery.")
                }
            }
            if h.supports(.connectionMode) {
                Section {
                    Picker("Bluetooth connection quality", selection: Binding(get: { h.connectionPriority }, set: { h.setConnectionPriority($0) })) {
                        ForEach(ConnectionPriority.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                } footer: {
                    Footnote("Sound quality allows LDAC on devices that support it. Current codec: \(h.codec.label).")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct NoiseControlPane: View {
    let h: Headphones

    var body: some View {
        Form {
            Section("Ambient Sound Control") {
                NoiseModeButtons(headphones: h, diameter: 60)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                if h.noiseMode == .ambient {
                    AmbientLevelSlider(headphones: h)
                    Toggle("Focus on Voice", isOn: Binding(get: { h.focusOnVoice }, set: { h.setNoiseControl(.ambient, focusOnVoice: $0) }))
                }
            }
            if h.supports(.ambientSoundControlModeSelect), let current = h.ncAmbButton {
                Section {
                    Picker("NC/AMB button", selection: Binding(get: { current }, set: { h.setNcAmbButton($0) })) {
                        ForEach(NcAmbButtonCycle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                } footer: {
                    Footnote("The modes the NC/AMB button on the left housing cycles through.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SpeakToChatPane: View {
    let h: Headphones

    var body: some View {
        Form {
            Section {
                Toggle("Speak-to-Chat", isOn: Binding(get: { h.speakToChat }, set: { h.setSpeakToChat($0) }))
            } footer: {
                Footnote("When you start talking, music pauses and ambient sound is let in so you can hear the conversation.")
            }
            Section {
                Picker("Voice detection sensitivity", selection: Binding(get: { h.speakToChatSensitivity }, set: { h.setSpeakToChat(sensitivity: $0) })) {
                    ForEach(SpeakToChatSensitivity.allCases) { Text($0.label).tag($0) }
                }
                Picker("End Speak-to-Chat", selection: Binding(get: { h.speakToChatTimeout }, set: { h.setSpeakToChat(timeout: $0) })) {
                    ForEach(SpeakToChatTimeout.allCases) { Text($0.label).tag($0) }
                }
            }
            .disabled(!h.speakToChat)
        }
        .formStyle(.grouped)
    }
}

private struct ControlsPane: View {
    let h: Headphones

    var body: some View {
        Form {
            let touchPanel = h.generalSettings.filter { $0.key == "TOUCH_PANEL_SETTING" }
            if !touchPanel.isEmpty {
                Section {
                    ForEach(touchPanel) { gs in
                        Toggle(gs.title, isOn: Binding(get: { gs.isOn }, set: { h.setGeneralSetting(gs.id, $0) }))
                    }
                } footer: {
                    Footnote("Swipe and tap on the right housing to control playback, volume and calls.")
                }
            }
            if h.supports(.voiceAssistantSettings), !h.voiceAssistantOptions.isEmpty {
                Section {
                    Picker("Voice assistant", selection: Binding(get: { h.voiceAssistant }, set: { h.setVoiceAssistant($0) })) {
                        ForEach(h.voiceAssistantOptions) { Text($0.label).tag($0) }
                    }
                } footer: {
                    Footnote("Google Assistant and Alexa need their phone apps; on a Mac, the device assistant is Siri.")
                }
            }
            if h.supports(.quickAccess), !h.quickAccessDoubleTapOptions.isEmpty {
                Section {
                    Picker("Double tap", selection: Binding(get: { h.quickAccessDoubleTap }, set: { h.setQuickAccess(doubleTap: $0) })) {
                        ForEach(options(h.quickAccessDoubleTapOptions, h.quickAccessDoubleTap)) { Text($0.label).tag($0) }
                    }
                    Picker("Triple tap", selection: Binding(get: { h.quickAccessTripleTap }, set: { h.setQuickAccess(tripleTap: $0) })) {
                        ForEach(options(h.quickAccessTripleTapOptions, h.quickAccessTripleTap)) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Quick Access")
                } footer: {
                    Footnote("Taps on the NC/AMB button that launch a music service on your phone.")
                }
            }
            if h.supports(.playbackControlByWearing) {
                Section {
                    Toggle("Pause when headphones are taken off", isOn: Binding(get: { h.pauseWhenTakenOff }, set: { h.setPauseWhenTakenOff($0) }))
                }
            }
        }
        .formStyle(.grouped)
    }

    private func options(_ list: [QuickAccessService], _ current: QuickAccessService) -> [QuickAccessService] {
        list.contains(current) ? list : [current] + list
    }
}

private struct DevicesPane: View {
    let h: Headphones

    var body: some View {
        Form {
            let multipoint = h.generalSettings.filter { $0.key == "MULTIPOINT_SETTING" }
            if !multipoint.isEmpty {
                Section {
                    ForEach(multipoint) { gs in
                        Toggle(gs.title, isOn: Binding(get: { gs.isOn }, set: { h.setGeneralSetting(gs.id, $0) }))
                    }
                } footer: {
                    Footnote(multipoint.first?.summary ?? "")
                }
            }
            if h.supportsPairedDevices {
                Section("Paired devices") {
                    ForEach(h.pairedDevices) { device in
                        PairedDeviceRow(headphones: h, device: device, showsManagement: true)
                    }
                    Toggle("Pairing mode", isOn: Binding(get: { h.pairingMode }, set: { h.setPairingMode($0) }))
                }
            }
            if h.supports(.sourceSwitchControl) {
                Section {
                    Toggle("Switch audio to the device that starts playing", isOn: Binding(get: { h.sourceSwitchEnabled }, set: { h.setSourceSwitch($0) }))
                }
            }
            let others = h.generalSettings.filter { $0.key != "MULTIPOINT_SETTING" && $0.key != "TOUCH_PANEL_SETTING" }
            if !others.isEmpty {
                Section("Other") {
                    ForEach(others) { gs in
                        Toggle(gs.title, isOn: Binding(get: { gs.isOn }, set: { h.setGeneralSetting(gs.id, $0) }))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SystemPane: View {
    let h: Headphones
    @State private var confirm: Confirmation?

    enum Confirmation: Identifiable {
        case powerOff, reset, factoryReset
        var id: Self { self }
    }

    var body: some View {
        Form {
            if h.supports(.autoPowerOffWithWearingDetection) || h.supports(.autoPowerOff), let current = h.autoPowerOff {
                Section {
                    Picker("Automatic power off", selection: Binding(get: { current }, set: { h.setAutoPowerOff($0) })) {
                        ForEach(powerOffOptions) { Text($0.label).tag($0) }
                    }
                }
            }
            if h.supportsVoiceGuidance {
                Section {
                    Toggle("Voice guidance", isOn: Binding(get: { h.voiceGuidance }, set: { h.setVoiceGuidance($0) }))
                    if !h.voiceGuidanceLanguages.isEmpty {
                        Picker("Language", selection: Binding(get: { h.voiceGuidanceLanguage }, set: { h.setVoiceGuidance(h.voiceGuidance, language: $0) })) {
                            ForEach(h.voiceGuidanceLanguages) { Text($0.label).tag($0) }
                        }
                        .disabled(!h.voiceGuidance)
                    }
                } footer: {
                    Footnote("Spoken prompts for power, battery and connection status.")
                }
            }
            if h.supports(.safeListeningHBS1) {
                Section {
                    LabeledContent("Current sound pressure", value: h.soundPressure.map { "\($0) dB" } ?? "—")
                } footer: {
                    Footnote("Estimated level at your ears while audio is playing.")
                }
            }
            Section {
                HStack(spacing: 10) {
                    if h.supports(.powerOff) {
                        Button("Turn Off…", systemImage: "power") { confirm = .powerOff }
                            .buttonStyle(.glass)
                    }
                    if h.supports(.resetSettings) {
                        Button("Reset Settings…", systemImage: "arrow.counterclockwise") { confirm = .reset }
                            .buttonStyle(.glass)
                        Spacer()
                        Button("Factory Reset…", systemImage: "exclamationmark.triangle", role: .destructive) { confirm = .factoryReset }
                            .buttonStyle(.glassProminent)
                            .tint(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(title, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { c in
            switch c {
            case .powerOff: Button("Turn Off") { h.powerOff() }
            case .reset: Button("Reset", role: .destructive) { h.resetSettings() }
            case .factoryReset: Button("Factory Reset", role: .destructive) { h.factoryReset() }
            }
        } message: { c in
            switch c {
            case .powerOff: Text("The headphones will disconnect from all devices.")
            case .reset: Text("Sound and control settings return to their defaults. Pairings are kept.")
            case .factoryReset: Text("All settings and pairing information are erased. You will need to pair the headphones again.")
            }
        }
    }

    private var title: String {
        switch confirm {
        case .powerOff: "Turn off \(h.modelName)?"
        case .reset: "Reset headphone settings?"
        case .factoryReset: "Factory reset \(h.modelName)?"
        case nil: ""
        }
    }

    private var powerOffOptions: [AutoPowerOff] {
        h.supports(.autoPowerOffWithWearingDetection)
            ? [.whenRemoved, .disabled]
            : [.after5Min, .after15Min, .after30Min, .after60Min, .after180Min, .disabled]
    }
}

private struct AboutPane: View {
    let h: Headphones
    @AppStorage("showBatteryInMenuBar") private var showBattery = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Headphones") {
                LabeledContent("Model", value: h.modelName)
                LabeledContent("Firmware", value: h.firmwareVersion)
                LabeledContent("Bluetooth address", value: h.address)
                LabeledContent("Codec", value: h.codec.label)
                LabeledContent("Protocol", value: String(format: "MDR v2 (0x%08X)", h.protocolVersion))
            }
            Section("Open1000X") {
                Toggle("Show battery level in the menu bar", isOn: $showBattery)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            Section {
                DisclosureGroup("Supported functions") {
                    Text("Table 1: " + h.t1.map { String(format: "%02X", $0.rawValue) }.sorted().joined(separator: " "))
                    Text("Table 2: " + h.t2.map { String(format: "%02X", $0.rawValue) }.sorted().joined(separator: " "))
                }
                .font(.callout.monospaced())
            } footer: {
                Footnote("Protocol research: Gadgetbridge and mos9527/SonyHeadphonesClient. Not affiliated with Sony.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Section footers in grouped forms, leading-aligned like System Settings.
private struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
