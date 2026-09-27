import IOBluetooth
import MDRKit
import SwiftUI

struct MenuContent: View {
    let manager: DeviceManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let h = manager.headphones, h.state == .ready {
                ConnectedMenu(headphones: h)
            } else {
                DisconnectedMenu(manager: manager)
            }
            VStack(spacing: 2) {
                Divider().padding(.horizontal, 4).padding(.bottom, 4)
                if manager.headphones?.state == .ready {
                    MenuRow(title: "Headphone Settings…", shortcut: "⌘,") { openSettings() }
                        .keyboardShortcut(",")
                }
                MenuRow(title: "Quit Open1000X", shortcut: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, -6)
        }
        .padding(14)
        .frame(width: 340)
    }

    private func openSettings() {
        openWindow(id: SettingsView.windowID)
        NSApp.activate()
    }
}

private struct ConnectedMenu: View {
    let headphones: Headphones
    @Environment(\.openWindow) private var openWindow
    @State private var showsPresets = false

    var body: some View {
        let h = headphones
        HStack(spacing: 12) {
            Image(systemName: "headphones")
                .font(.system(size: 19, weight: .medium))
                .frame(width: 40, height: 40)
                .glassEffect(.regular, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(h.modelName).font(.headline)
                Text(subtitle(h)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            BatteryRing(level: h.battery, charging: h.charging, size: 34)
        }

        HeadsetBanners(headphones: h)

        if h.supportsNoiseControl {
            VStack(spacing: 12) {
                NoiseModeButtons(headphones: h)
                    .frame(maxWidth: .infinity)
                if h.noiseMode == .ambient {
                    VStack(alignment: .leading, spacing: 10) {
                        AmbientLevelSlider(headphones: h)
                        Toggle("Focus on Voice", isOn: Binding(
                            get: { h.focusOnVoice },
                            set: { h.setNoiseControl(.ambient, focusOnVoice: $0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    .glassCard(cornerRadius: 16)
                    .transition(.blurReplace)
                }
            }
            .animation(.smooth, value: h.noiseMode)
        }

        tiles(h)

        if h.supports(.playbackController) {
            VStack(spacing: 12) {
                NowPlaying(headphones: h)
                VolumeSlider(headphones: h)
            }
            .glassCard(cornerRadius: 16)
        }

        if h.supportsPairedDevices, h.pairedDevices.filter(\.isConnected).count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader("Play Audio From")
                ForEach(h.pairedDevices.filter(\.isConnected)) { device in
                    DeviceSourceRow(device: device) { h.switchAudio(to: device) }
                }
            }
        }
    }

    @ViewBuilder
    private func tiles(_ h: Headphones) -> some View {
        let s2c = h.supports(.smartTalkingModeType2)
        let dsee = h.supports(.upscalingAutoOff)
        VStack(spacing: 8) {
            if s2c || dsee {
                HStack(spacing: 8) {
                    if s2c {
                        ControlTile(symbol: "bubble.left.and.bubble.right.fill", title: "Speak-to-Chat",
                                    value: h.speakToChat ? "On" : "Off", isOn: h.speakToChat) {
                            h.setSpeakToChat(!h.speakToChat)
                        }
                    }
                    if dsee {
                        ControlTile(symbol: "waveform", title: h.upscalingType?.label ?? "DSEE",
                                    value: !h.upscalingAvailable ? "Unavailable" : h.upscalingEnabled ? "Auto" : "Off",
                                    isOn: h.upscalingEnabled) {
                            h.setUpscaling(!h.upscalingEnabled)
                        }
                        .disabled(!h.upscalingAvailable)
                    }
                }
            }
            if h.supportsEqualizer, !h.eqPresets.isEmpty {
                EqualizerModule(headphones: h, expanded: $showsPresets) {
                    openWindow(id: SettingsView.windowID)
                    NSApp.activate()
                }
            }
        }
    }

    private func subtitle(_ h: Headphones) -> String {
        var parts = [h.charging == .charging ? "Charging" : "Connected", h.codec.label]
        if h.upscalingActive, let t = h.upscalingType { parts.append(t.label) }
        return parts.joined(separator: " · ")
    }
}

/// The equalizer tile. Expanding it grows a preset grid out of the tile as one
/// Liquid Glass shape; the selection highlight slides between presets.
private struct EqualizerModule: View {
    let headphones: Headphones
    @Binding var expanded: Bool
    let openEditor: () -> Void
    @Namespace private var glass
    @Namespace private var selection

    private let spring = Animation.snappy(duration: 0.28, extraBounce: 0.04)

    var body: some View {
        let h = headphones
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                ControlTile(symbol: "slider.vertical.3", title: "Equalizer", value: h.eqPresetName,
                            isOn: h.eqPreset != .off, action: { withAnimation(spring) { expanded.toggle() } }) {
                    HStack(spacing: 8) {
                        if !h.eqBands.isEmpty {
                            EQCurve(bands: h.eqPreset == .off ? h.eqBands.map { _ in 0 } : h.eqBands)
                                .frame(width: 56, height: 22)
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                }
                .glassEffectID("tile", in: glass)
                .disabled(!h.eqAvailable)

                if expanded {
                    presetGrid(h)
                        .padding(8)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                        .glassEffectID("presets", in: glass)
                        .glassEffectTransition(.matchedGeometry)
                }
            }
        }
    }

    private func presetGrid(_ h: Headphones) -> some View {
        let curated = h.activeCuratedEQ
        let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]
        return VStack(alignment: .leading, spacing: 6) {
            if h.supportsCuratedEQ {
                SectionHeader("Open1000X")
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(CuratedEQPreset.all) { preset in
                        presetButton(preset.name, selected: curated == preset) {
                            withAnimation(spring) { h.apply(preset) }
                        }
                        .help(preset.summary)
                    }
                }
                SectionHeader("Headphones").padding(.top, 2)
            }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(h.eqPresets) { preset in
                    presetButton(preset.label, selected: curated == nil && h.eqPreset == preset) {
                        withAnimation(spring) { h.setEQPreset(preset) }
                    }
                }
            }
            Divider().padding(.horizontal, 6)
            Button(action: openEditor) {
                Label("Edit Equalizer…", systemImage: "slider.horizontal.3")
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
    }

    private func presetButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .opacity(selected ? 1 : 0)
                    .scaleEffect(selected ? 1 : 0.4)
                Text(title)
                    .foregroundStyle(selected ? .white : .primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.tint)
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Plain button that dips slightly while pressed, for list-like choices.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A connected source device; the one playing is marked with a filled glyph.
private struct DeviceSourceRow: View {
    let device: PairedDevice
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: device.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(device.isPlaying ? .white : .primary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(device.isPlaying ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary)))
                Text(device.name).lineLimit(1)
                Spacer()
                if device.isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering && !device.isPlaying ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(device.isPlaying)
        .onHover { hovering = $0 }
        .help(device.isPlaying ? "Playing on \(device.name)" : "Play audio from \(device.name)")
    }
}

private struct DisconnectedMenu: View {
    let manager: DeviceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Group {
                    if manager.headphones?.state == .connecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "headphones").font(.system(size: 19, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 40, height: 40)
                .glassEffect(.regular, in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if case .disconnected(_?) = manager.headphones?.state {
                Button("Try Again") { manager.reconnect() }
                    .buttonStyle(.glassProminent)
            } else if manager.headphones == nil, !manager.pairedHeadsets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader("Paired Headphones")
                    ForEach(manager.pairedHeadsets, id: \.addressString) { device in
                        HStack {
                            Text(device.name ?? device.addressString)
                            Spacer()
                            Button("Connect") { manager.connect(device) }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        switch manager.headphones?.state {
        case .connecting: "Connecting…"
        case .disconnected(_?): "Couldn't Connect"
        default: "Not Connected"
        }
    }

    private var detail: String? {
        switch manager.headphones?.state {
        case .connecting: manager.headphones?.modelName
        case .disconnected(let reason?): reason
        default: manager.pairedHeadsets.isEmpty ? "Pair your headphones in Bluetooth settings." : nil
        }
    }
}
