import MDRKit
import SwiftUI

// Liquid Glass building blocks shared by the popover and the settings window.

extension View {
    /// A rounded glass panel for grouping controls.
    func glassCard(cornerRadius: CGFloat = 18, tint: Color? = nil) -> some View {
        padding(12)
            .glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: .rect(cornerRadius: cornerRadius))
    }
}

/// Control Center style round buttons for NC / Ambient / Off. The selection glass
/// morphs between buttons when the mode changes, including changes from the headset.
struct NoiseModeButtons: View {
    let headphones: Headphones
    var diameter: CGFloat = 52
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            HStack(spacing: 18) {
                ForEach(NoiseMode.allCases) { mode in
                    let selected = headphones.noiseMode == mode
                    Button {
                        withAnimation(.bouncy) { headphones.setNoiseControl(mode) }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: mode.symbolName)
                                .font(.system(size: diameter * 0.38, weight: .medium))
                                .foregroundStyle(selected ? .white : .primary)
                                .frame(width: diameter, height: diameter)
                                .glassEffect(selected ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                                             in: .circle)
                                .glassEffectID(mode, in: glass)
                            Text(mode.shortLabel)
                                .font(.caption)
                                .foregroundStyle(selected ? .primary : .secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .animation(.bouncy, value: headphones.noiseMode)
    }
}

/// A round glass button holding a single symbol.
struct GlassIconButton: View {
    let symbol: String
    var size: CGFloat = 32
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(prominent ? .white : .primary)
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(prominent ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .circle)
    }
}

struct BatteryRing: View {
    let level: Int?
    let charging: ChargingStatus
    var size: CGFloat = 40

    var body: some View {
        let fraction = Double(level ?? 0) / 100
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color(fraction), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if charging == .charging {
                Image(systemName: "bolt.fill").font(.system(size: size * 0.3)).foregroundStyle(.green)
            } else {
                Text(level.map { "\($0)" } ?? "–")
                    .font(.system(size: size * 0.3, weight: .semibold).monospacedDigit())
            }
        }
        .frame(width: size, height: size)
        .animation(.smooth, value: level)
        .accessibilityLabel("Battery \(level ?? 0) percent")
    }

    private func color(_ f: Double) -> Color {
        f <= 0.2 ? .red : f <= 0.4 ? .orange : .green
    }
}

/// Control Center style module: a filled circle glyph with a title and state line.
struct ControlTile<Trailing: View>: View {
    let symbol: String
    let title: String
    let value: String
    let isOn: Bool
    let action: () -> Void
    @ViewBuilder var trailing: Trailing

    init(symbol: String, title: String, value: String, isOn: Bool, action: @escaping () -> Void,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.symbol = symbol
        self.title = title
        self.value = value
        self.isOn = isOn
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? .white : .primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.interpolate)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                trailing
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .animation(.snappy(duration: 0.25), value: isOn)
        .animation(.snappy(duration: 0.25), value: value)
        .accessibilityValue(value)
    }
}

/// Band values as an animatable vector, so curves morph between presets.
struct BandVector: VectorArithmetic {
    var values: [Double]

    static var zero: BandVector { BandVector(values: []) }

    private static func combine(_ a: BandVector, _ b: BandVector, _ op: (Double, Double) -> Double) -> BandVector {
        let n = max(a.values.count, b.values.count)
        return BandVector(values: (0..<n).map { i in
            op(i < a.values.count ? a.values[i] : 0, i < b.values.count ? b.values[i] : 0)
        })
    }

    static func + (a: BandVector, b: BandVector) -> BandVector { combine(a, b, +) }
    static func - (a: BandVector, b: BandVector) -> BandVector { combine(a, b, -) }
    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

/// A smooth curve through the band values, edge to edge.
struct EQCurveShape: Shape {
    var bands: BandVector
    var range: Double

    var animatableData: BandVector {
        get { bands }
        set { bands = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let v = bands.values
        var path = Path()
        guard v.count > 1 else { return path }
        let points = v.enumerated().map { i, value in
            CGPoint(x: rect.minX + rect.width * CGFloat(i) / CGFloat(v.count - 1),
                    y: rect.midY - rect.height * 0.46 * CGFloat(value / range))
        }
        path.addSmoothCurve(through: points)
        return path
    }
}

extension Path {
    /// Horizontal-tangent cubic segments: smooth, and never overshoots between points.
    mutating func addSmoothCurve(through points: [CGPoint]) {
        guard let first = points.first else { return }
        if isEmpty { move(to: first) } else { addLine(to: first) }
        for (a, b) in zip(points, points.dropFirst()) {
            let c = (a.x + b.x) / 2
            addCurve(to: b, control1: CGPoint(x: c, y: a.y), control2: CGPoint(x: c, y: b.y))
        }
    }
}

/// Equalizer response preview. Morphs with a snappy spring when the bands change.
struct EQCurve: View {
    let bands: [Int]
    var range: Double = 10
    var lineWidth: CGFloat = 2
    var animation: Animation? = .snappy(duration: 0.3)

    var body: some View {
        let vector = BandVector(values: bands.map(Double.init))
        ZStack {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
            EQCurveShape(bands: vector, range: range)
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .animation(animation, value: bands)
        .accessibilityHidden(true)
    }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
}

/// A full-width row that highlights on hover, like the items at the bottom of system menu extras.
struct MenuRow: View {
    let title: String
    var shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(hovering ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
                }
            }
            .foregroundStyle(hovering ? .white : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
