import MDRKit
import SwiftUI

// MARK: - Status

struct BatteryLabel: View {
    let level: Int?
    let charging: ChargingStatus

    var body: some View {
        if let level {
            Label {
                Text("\(level)%").monospacedDigit()
            } icon: {
                Image(systemName: symbol(level))
            }
            .labelStyle(.titleAndIcon)
        }
    }

    private func symbol(_ level: Int) -> String {
        if charging == .charging { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - Noise control

struct AmbientLevelSlider: View {
    let headphones: Headphones

    var body: some View {
        HStack {
            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { Double(headphones.ambientLevel) },
                set: { headphones.setNoiseControl(.ambient, ambientLevel: Int($0.rounded()), dragging: true) }
            ), in: 1...20, step: 1) { editing in
                if !editing { headphones.setNoiseControl(.ambient, ambientLevel: headphones.ambientLevel) }
            }
            Image(systemName: "ear.and.waveform").foregroundStyle(.secondary)
            Text("\(headphones.ambientLevel)")
                .monospacedDigit()
                .frame(width: 20, alignment: .trailing)
        }
    }
}

// MARK: - Playback

struct VolumeSlider: View {
    let headphones: Headphones

    var body: some View {
        HStack {
            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { Double(headphones.volume) },
                set: { headphones.setVolume(Int($0.rounded())) }
            ), in: 0...30, step: 1)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
        }
    }
}

struct NowPlaying: View {
    let headphones: Headphones

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .frame(width: 34, height: 34)
                .glassEffect(.regular, in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(headphones.trackTitle.isEmpty
                     ? (headphones.playback == .playing ? "Playing" : "Paused")
                     : headphones.trackTitle)
                    .lineLimit(1)
                if !headphones.trackArtist.isEmpty {
                    Text(headphones.trackArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    GlassIconButton(symbol: "backward.fill", size: 30) { headphones.sendPlayback(.previousTrack) }
                    GlassIconButton(symbol: headphones.playback == .playing ? "pause.fill" : "play.fill", size: 36, prominent: true) {
                        headphones.sendPlayback(headphones.playback == .playing ? .pause : .play)
                    }
                    GlassIconButton(symbol: "forward.fill", size: 30) { headphones.sendPlayback(.nextTrack) }
                }
            }
        }
    }
}

// MARK: - Devices

struct PairedDeviceRow: View {
    let headphones: Headphones
    let device: PairedDevice
    var showsManagement = false
    @State private var confirmUnpair = false

    var body: some View {
        HStack {
            Image(systemName: device.symbolName)
                .frame(width: 20)
                .foregroundStyle(device.isConnected ? .primary : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name.isEmpty ? device.address : device.name).lineLimit(1)
                Text(device.isPlaying ? "Playing audio" : device.isConnected ? "Connected" : "Not connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if device.isConnected && !device.isPlaying {
                Button("Play Here") { headphones.switchAudio(to: device) }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            if showsManagement {
                Menu {
                    if device.isConnected {
                        Button("Disconnect") { headphones.perform(.disconnect, on: device) }
                    } else {
                        Button("Connect") { headphones.perform(.connect, on: device) }
                    }
                    Divider()
                    Button("Remove Pairing…", role: .destructive) { confirmUnpair = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .confirmationDialog("Remove \(device.name) from the headset's pairing list?", isPresented: $confirmUnpair) {
            Button("Remove Pairing", role: .destructive) { headphones.perform(.unpair, on: device) }
        } message: {
            Text("You will need to pair this device with the headset again to use it.")
        }
    }
}

// MARK: - Banners

struct HeadsetBanners: View {
    let headphones: Headphones

    var body: some View {
        if let alert = headphones.pendingAlert {
            VStack(alignment: .leading, spacing: 8) {
                Label(alert.message, systemImage: "exclamationmark.bubble")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    if alert.needsAnswer {
                        Button("Cancel") { headphones.respond(to: alert, accept: false) }
                            .buttonStyle(.glass)
                    }
                    Button("OK") { headphones.respond(to: alert, accept: true) }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .glassCard(cornerRadius: 16, tint: .yellow.opacity(0.35))
            .transition(.blurReplace)
        }
        if let error = headphones.lastError {
            HStack(alignment: .top) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { headphones.clearError() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }
            .font(.callout)
            .glassCard(cornerRadius: 16, tint: .red.opacity(0.3))
            .transition(.blurReplace)
        }
    }
}
