import AppIntents
import AppKit
import SwiftUI
import WidgetKit

// Control Center tiles. This runs as a sandboxed extension, so it never talks to the headset itself:
// it reads the state Open1000X publishes (ControlSnapshot) and asks the app to act (ControlCommand).

@main
struct Open1000XControls: WidgetBundle {
    var body: some Widget {
        NoiseControlControl()
        AmbientSoundControl()
        SpeakToChatControl()
        DSEEControl()
    }
}

struct SnapshotProvider: ControlValueProvider {
    var previewValue: ControlSnapshot {
        ControlSnapshot(connected: true, model: "WH-1000XM5", noiseMode: .noiseCancelling, speakToChat: false, dsee: true)
    }

    func currentValue() async throws -> ControlSnapshot {
        HostApp.isRunning ? ControlSnapshot.read() : .disconnected
    }
}

// MARK: Controls

struct NoiseControlControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "\(appBundleIdentifier).control.noise", provider: SnapshotProvider()) { s in
            ControlWidgetButton(action: CycleNoiseModeIntent()) {
                Label {
                    Text("Noise Control")
                    Text(s.connected ? s.noiseMode?.label ?? "Unavailable" : "Not Connected")
                } icon: {
                    Image(systemName: s.noiseMode?.symbolName ?? "headphones.slash")
                }
            }
            .disabled(s.connected && s.noiseMode == nil)
        }
        .displayName("Noise Control")
        .description("Switch between Noise Cancelling, Ambient Sound and Off, like the headset's NC/AMB button.")
    }
}

struct AmbientSoundControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "\(appBundleIdentifier).control.ambient", provider: SnapshotProvider()) { s in
            ControlWidgetToggle("Ambient Sound", isOn: s.noiseMode == .ambient, action: SetAmbientSoundIntent()) { isOn in
                Label(s.valueLabel(isOn ? "On" : "Off", feature: s.noiseMode), systemImage: "ear.and.waveform")
            }
            .disabled(s.connected && s.noiseMode == nil)
        }
        .displayName("Ambient Sound")
        .description("Turn Ambient Sound on, or go back to Noise Cancelling.")
    }
}

struct SpeakToChatControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "\(appBundleIdentifier).control.speakToChat", provider: SnapshotProvider()) { s in
            ControlWidgetToggle("Speak-to-Chat", isOn: s.speakToChat == true, action: SetSpeakToChatIntent()) { isOn in
                Label(s.valueLabel(isOn ? "On" : "Off", feature: s.speakToChat), systemImage: "bubble.left.and.bubble.right.fill")
            }
            .disabled(s.connected && s.speakToChat == nil)
        }
        .displayName("Speak-to-Chat")
        .description("Pause music and let in ambient sound when you start talking.")
    }
}

struct DSEEControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "\(appBundleIdentifier).control.dsee", provider: SnapshotProvider()) { s in
            ControlWidgetToggle("DSEE Extreme", isOn: s.dsee == true, action: SetDSEEIntent()) { isOn in
                Label(s.valueLabel(isOn ? "Auto" : "Off", feature: s.dsee), systemImage: "waveform")
            }
            .disabled(s.connected && s.dsee == nil)
        }
        .displayName("DSEE Extreme")
        .description("Upscale compressed music.")
    }
}

extension ControlSnapshot {
    func valueLabel<T>(_ value: String, feature: T?) -> String {
        !connected ? "Not Connected" : feature == nil ? "Unavailable" : value
    }
}

extension ControlSnapshot.NoiseMode {
    var label: String {
        switch self {
        case .noiseCancelling: "Noise Cancelling"
        case .ambient: "Ambient Sound"
        case .off: "Off"
        }
    }

    // Matches the menu bar icon.
    var symbolName: String {
        switch self {
        case .noiseCancelling: "headphones"
        case .ambient: "ear.and.waveform"
        case .off: "headphones.circle"
        }
    }
}

// MARK: Intents

struct CycleNoiseModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Cycle Noise Control"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let before = ControlSnapshot.read().noiseMode
        await HostApp.send(.cycleNoise) { $0.noiseMode != before }
        return .result()
    }
}

struct SetAmbientSoundIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Ambient Sound"
    static let isDiscoverable = false

    @Parameter(title: "Ambient Sound")
    var value: Bool

    func perform() async throws -> some IntentResult {
        await HostApp.send(value ? .ambient : .noiseCancelling) { $0.noiseMode == (value ? .ambient : .noiseCancelling) }
        return .result()
    }
}

struct SetSpeakToChatIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Speak-to-Chat"
    static let isDiscoverable = false

    @Parameter(title: "Speak-to-Chat")
    var value: Bool

    func perform() async throws -> some IntentResult {
        await HostApp.send(value ? .speakToChatOn : .speakToChatOff) { $0.speakToChat == value }
        return .result()
    }
}

struct SetDSEEIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set DSEE Extreme"
    static let isDiscoverable = false

    @Parameter(title: "DSEE Extreme")
    var value: Bool

    func perform() async throws -> some IntentResult {
        await HostApp.send(value ? .dseeOn : .dseeOff) { $0.dsee == value }
        return .result()
    }
}

// MARK: Talking to the app

enum HostApp {
    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: appBundleIdentifier).isEmpty
    }

    /// Open1000X.app/Contents/PlugIns/Open1000XControls.appex
    static var url: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Posts `command`, launching the app with it if needed, then waits briefly until the published
    /// state satisfies `done` so Control Center shows the new value rather than the old one.
    static func send(_ command: ControlCommand, until done: (ControlSnapshot) -> Bool) async {
        if isRunning {
            command.post()
        } else {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.arguments = [ControlCommand.launchArgument, command.rawValue]
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        for _ in 0..<30 {
            if done(ControlSnapshot.read()) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
