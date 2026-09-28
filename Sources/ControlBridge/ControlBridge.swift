import Foundation
import notify

// Shared by the app and the sandboxed Control Center extension (Extensions/Controls), which is
// compiled with this file by scripts/build-app.sh. The app publishes a snapshot to a JSON file the
// extension may read, and the extension sends commands back as Darwin notifications, which carry no
// payload but need no shared container.

public let appBundleIdentifier = "dev.open1000x.app"

/// What the controls show. `nil` means the connected headset doesn't have that feature.
public struct ControlSnapshot: Codable, Equatable, Sendable {
    public enum NoiseMode: String, Codable, Sendable {
        case noiseCancelling, ambient, off
    }

    public var connected = false
    public var model = ""
    public var noiseMode: NoiseMode?
    public var speakToChat: Bool?
    public var dsee: Bool?

    public init(connected: Bool = false, model: String = "", noiseMode: NoiseMode? = nil,
                speakToChat: Bool? = nil, dsee: Bool? = nil) {
        self.connected = connected
        self.model = model
        self.noiseMode = noiseMode
        self.speakToChat = speakToChat
        self.dsee = dsee
    }

    public static let disconnected = ControlSnapshot()

    /// `~/Library/Application Support/Open1000X/controls.json`, in the real home folder even when
    /// read from inside the extension's sandbox container.
    public static var fileURL: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(filePath: home)
            .appending(components: "Library", "Application Support", "Open1000X", "controls.json")
    }

    public static func read() -> ControlSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(ControlSnapshot.self, from: data) else { return .disconnected }
        return snapshot
    }

    public func write() throws {
        let url = Self.fileURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

public enum ControlCommand: String, CaseIterable, Sendable {
    case noiseCancelling, ambient, noiseOff, cycleNoise
    case speakToChatOn, speakToChatOff
    case dseeOn, dseeOff

    public var notificationName: String { "\(appBundleIdentifier).control.\(rawValue)" }

    /// Launch argument that hands a command to an app that wasn't running yet.
    public static let launchArgument = "--control"

    public func post() {
        notify_post(notificationName)
    }

    /// Calls `handler` on the main queue whenever the command is posted. Returns the notify token.
    @discardableResult
    public func observe(_ handler: @escaping @MainActor () -> Void) -> Int32 {
        var token: Int32 = 0
        notify_register_dispatch(notificationName, &token, .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return token
    }
}
