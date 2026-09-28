import ControlBridge
import Foundation
import MDRKit
import Observation
import WidgetKit

/// Keeps the Control Center controls (Extensions/Controls) in step with the headset and carries out
/// what they ask for.
@MainActor
final class ControlsBridge {
    private let manager: DeviceManager
    private var published: ControlSnapshot?
    /// A command the extension launched the app with, run once the headset is ready.
    private var pending: (command: ControlCommand, deadline: ContinuousClock.Instant)?

    init(manager: DeviceManager) {
        self.manager = manager
        for command in ControlCommand.allCases {
            command.observe { [weak self] in self?.run(command) }
        }
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: ControlCommand.launchArgument), i + 1 < args.count,
           let command = ControlCommand(rawValue: args[i + 1]) {
            pending = (command, .now + .seconds(20))
        }
        update()
    }

    /// Publishes the snapshot the extension shows while the app isn't around to answer.
    func appWillTerminate() {
        publish(.disconnected)
    }

    private func update() {
        let snapshot = withObservationTracking { current() } onChange: { [weak self] in
            Task { @MainActor in self?.update() }
        }
        publish(snapshot)
        if snapshot.connected, let pending {
            self.pending = nil
            if .now < pending.deadline { run(pending.command) }
        }
    }

    private func current() -> ControlSnapshot {
        guard let h = manager.headphones, h.state == .ready else { return .disconnected }
        return ControlSnapshot(
            connected: true,
            model: h.modelName,
            noiseMode: h.supportsNoiseControl ? ControlSnapshot.NoiseMode(rawValue: h.noiseMode.rawValue) : nil,
            speakToChat: h.supports(.smartTalkingModeType2) ? h.speakToChat : nil,
            dsee: h.supports(.upscalingAutoOff) && h.upscalingAvailable ? h.upscalingEnabled : nil
        )
    }

    private func publish(_ snapshot: ControlSnapshot) {
        guard snapshot != published else { return }
        published = snapshot
        do {
            try snapshot.write()
        } catch {
            return
        }
        ControlCenter.shared.reloadAllControls()
    }

    private func run(_ command: ControlCommand) {
        guard let h = manager.headphones, h.state == .ready else { return }
        switch command {
        case .noiseCancelling, .ambient, .noiseOff, .cycleNoise:
            guard h.supportsNoiseControl else { return }
            let mode: NoiseMode = switch command {
            case .noiseCancelling: .noiseCancelling
            case .ambient: .ambient
            case .noiseOff: .off
            default: h.nextNoiseMode
            }
            h.setNoiseControl(mode)
        case .speakToChatOn, .speakToChatOff:
            guard h.supports(.smartTalkingModeType2) else { return }
            h.setSpeakToChat(command == .speakToChatOn)
        case .dseeOn, .dseeOff:
            guard h.supports(.upscalingAutoOff), h.upscalingAvailable else { return }
            h.setUpscaling(command == .dseeOn)
        }
    }
}

extension Headphones {
    /// The mode after the current one in the NC/AMB button's cycle.
    var nextNoiseMode: NoiseMode {
        let cycle: [NoiseMode] = switch ncAmbButton ?? .ncAmbientOff {
        case .ncAmbientOff: [.noiseCancelling, .ambient, .off]
        case .ncAmbient: [.noiseCancelling, .ambient]
        case .ncOff: [.noiseCancelling, .off]
        case .ambientOff: [.ambient, .off]
        }
        let next = cycle.firstIndex(of: noiseMode).map { $0 + 1 } ?? 0
        return cycle[next % cycle.count]
    }
}
