import AppKit
import MDRKit
import SwiftUI

/// `OPEN1000X_SNAPSHOT=<dir>` shows the popover content and each settings pane in real
/// windows once the headset is synced, captures them with `screencapture`, then quits.
/// Liquid Glass is composited by the window server, so offscreen rendering can't capture it.
@MainActor
enum DebugSnapshots {
    static func runIfRequested(_ manager: DeviceManager) {
        guard let dir = ProcessInfo.processInfo.environment["OPEN1000X_SNAPSHOT"] else { return }
        Task {
            while manager.headphones?.state != .ready { try? await Task.sleep(for: .milliseconds(200)) }
            try? await Task.sleep(for: .seconds(1))
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = appearance == .aqua ? "light" : "dark"
                await capture(MenuContent(manager: manager), to: "\(dir)/menu-\(suffix).png", appearance: appearance, popover: true)
                for pane in SettingsView.Pane.allCases {
                    await capture(SettingsView(manager: manager, pane: pane),
                                  to: "\(dir)/settings-\(pane.rawValue)-\(suffix).png", appearance: appearance)
                }
            }
            NSApp.terminate(nil)
        }
    }

    private static func capture(_ view: some View, to path: String, appearance: NSAppearance.Name, popover: Bool = false) async {
        let controller = NSHostingController(rootView: view)
        controller.sceneBridgingOptions = .all
        let window = NSWindow(contentViewController: controller)
        window.appearance = NSAppearance(named: appearance)
        if popover {
            window.styleMask = [.titled, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        } else {
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.toolbarStyle = .unified
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(1.2))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", path]
        try? p.run()
        p.waitUntilExit()
        window.close()
    }
}
