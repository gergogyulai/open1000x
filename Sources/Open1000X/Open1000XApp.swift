import AppKit
import MDRKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let manager = DeviceManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["OPEN1000X_TRACE"] != nil {
            manager.trace = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
        }
        manager.start()
        DebugSnapshots.runIfRequested(manager)
    }
}

@main
struct Open1000XApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(manager: delegate.manager)
        } label: {
            MenuBarLabel(manager: delegate.manager)
        }
        .menuBarExtraStyle(.window)

        Window("Open1000X", id: SettingsView.windowID) {
            SettingsView(manager: delegate.manager)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

struct MenuBarLabel: View {
    let manager: DeviceManager
    @AppStorage("showBatteryInMenuBar") private var showBattery = true

    var body: some View {
        if let h = manager.headphones, h.state == .ready {
            HStack(spacing: 3) {
                Image(systemName: h.noiseMode.symbolName)
                if showBattery, let battery = h.battery {
                    Text("\(battery)%").monospacedDigit()
                }
            }
        } else {
            Image(systemName: "headphones.slash")
        }
    }
}

extension NoiseMode {
    var symbolName: String {
        switch self {
        case .noiseCancelling: "headphones"
        case .ambient: "ear.and.waveform"
        case .off: "headphones.circle"
        }
    }

    var shortLabel: String {
        switch self {
        case .noiseCancelling: "Noise Cancelling"
        case .ambient: "Ambient"
        case .off: "Off"
        }
    }
}
