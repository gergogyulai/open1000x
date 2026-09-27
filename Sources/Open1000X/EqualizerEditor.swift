import MDRKit
import SwiftUI

/// Band editor in the style of Music's equalizer: one plot where each band is a knob on a
/// track, the response curve runs through the knobs, and bands fill from the zero line.
/// Dragging anywhere in a column moves that band, snapping to whole steps.
struct EqualizerEditor: View {
    let headphones: Headphones
    @State private var draft: [Int] = []
    @State private var activeBand: Int?

    private let plotHeight: CGFloat = 176
    private let knob: CGFloat = 20
    private let scaleWidth: CGFloat = 34

    private var limit: Int { headphones.eqBands.count == 10 ? 6 : 10 }

    private var labels: [String] {
        switch headphones.eqBands.count {
        case 6: ["Clear Bass", "400", "1k", "2.5k", "6.3k", "16k"]
        case 10: ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
        default: headphones.eqBands.indices.map { "\($0 + 1)" }
        }
    }

    var body: some View {
        let values = activeBand == nil ? headphones.eqBands : draft
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                scale
                plot(values)
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: scaleWidth, height: 1)
                ForEach(values.indices, id: \.self) { i in
                    VStack(spacing: 2) {
                        Text(values[i] > 0 ? "+\(values[i])" : "\(values[i])")
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(activeBand == i ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                            .contentTransition(.numericText(value: Double(values[i])))
                        Text(labels[i])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(activeBand == nil ? .snappy(duration: 0.3) : .interactiveSpring(duration: 0.15), value: values)
        .padding(.vertical, 4)
    }

    private var scale: some View {
        ZStack(alignment: .trailing) {
            ForEach([limit, 0, -limit], id: \.self) { v in
                Text(v > 0 ? "+\(v)" : v < 0 ? "−\(-v)" : "0")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .position(x: scaleWidth / 2 - 4, y: y(for: Double(v)))
            }
        }
        .frame(width: scaleWidth, height: plotHeight)
    }

    private func plot(_ values: [Int]) -> some View {
        GeometryReader { geo in
            let columns = CGFloat(max(values.count, 1))
            let columnWidth = geo.size.width / columns
            let points = values.enumerated().map { i, v in
                CGPoint(x: columnWidth * (CGFloat(i) + 0.5), y: y(for: Double(v)))
            }
            let zero = y(for: 0)

            ZStack(alignment: .topLeading) {
                // Grid: faint limits, stronger zero line.
                ForEach([limit, -limit], id: \.self) { v in
                    Rectangle().fill(.quaternary.opacity(0.6)).frame(height: 1).offset(y: y(for: Double(v)))
                }
                Rectangle().fill(.tertiary).frame(height: 1).offset(y: zero)

                // Tracks and the fill from zero to each knob.
                ForEach(points.indices, id: \.self) { i in
                    Capsule()
                        .fill(.fill.tertiary)
                        .frame(width: 4, height: plotHeight - knob)
                        .position(x: points[i].x, y: plotHeight / 2)
                    Capsule()
                        .fill(.tint)
                        .frame(width: 4, height: abs(points[i].y - zero))
                        .position(x: points[i].x, y: (points[i].y + zero) / 2)
                }

                // Response curve through the knobs, with a soft area fill to the zero line.
                ResponseShape(points: AnimatablePoints(points), zero: zero, closed: true)
                    .fill(LinearGradient(colors: [.accentColor.opacity(0.28), .accentColor.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                ResponseShape(points: AnimatablePoints(points), zero: zero, closed: false)
                    .stroke(.tint.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // Knobs.
                ForEach(points.indices, id: \.self) { i in
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                        .overlay(Circle().strokeBorder(.black.opacity(0.08)))
                        .frame(width: knob, height: knob)
                        .scaleEffect(activeBand == i ? 1.18 : 1)
                        .position(points[i])
                        .accessibilityElement()
                        .accessibilityLabel(labels[i])
                        .accessibilityValue("\(values[i])")
                        .accessibilityAdjustableAction { direction in
                            var bands = headphones.eqBands
                            bands[i] = min(limit, max(-limit, bands[i] + (direction == .increment ? 1 : -1)))
                            headphones.setEQBands(bands)
                        }
                }
            }
            .contentShape(.rect)
            .gesture(drag(columnWidth: columnWidth, count: values.count))
            .sensoryFeedback(.alignment, trigger: activeBand.map { draft[$0] })
        }
        .frame(height: plotHeight)
    }

    private func drag(columnWidth: CGFloat, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if activeBand == nil {
                    let band = Int(g.startLocation.x / columnWidth)
                    guard (0..<count).contains(band) else { return }
                    draft = headphones.eqBands
                    withAnimation(.snappy(duration: 0.2)) { activeBand = band }
                }
                guard let band = activeBand else { return }
                let v = value(at: g.location.y)
                if draft[band] != v { draft[band] = v }
            }
            .onEnded { _ in
                if activeBand != nil, draft != headphones.eqBands { headphones.setEQBands(draft) }
                withAnimation(.snappy(duration: 0.25)) { activeBand = nil }
            }
    }

    // MARK: Geometry

    private func y(for value: Double) -> CGFloat {
        let usable = plotHeight - knob
        return knob / 2 + usable * (1 - (value + Double(limit)) / Double(2 * limit))
    }

    private func value(at y: CGFloat) -> Int {
        let usable = plotHeight - knob
        let fraction = 1 - Double((y - knob / 2) / usable)
        let v = Int((fraction * Double(2 * limit)).rounded()) - limit
        return min(limit, max(-limit, v))
    }
}

/// Points as an animatable vector, so the curve and fill morph with the knobs.
private struct AnimatablePoints: VectorArithmetic {
    var ys: BandVector
    var xs: [CGFloat]

    init(_ points: [CGPoint]) {
        ys = BandVector(values: points.map { Double($0.y) })
        xs = points.map(\.x)
    }

    private init(ys: BandVector, xs: [CGFloat]) {
        self.ys = ys
        self.xs = xs
    }

    static var zero: AnimatablePoints { AnimatablePoints(ys: .zero, xs: []) }
    static func + (a: Self, b: Self) -> Self { Self(ys: a.ys + b.ys, xs: a.xs.count >= b.xs.count ? a.xs : b.xs) }
    static func - (a: Self, b: Self) -> Self { Self(ys: a.ys - b.ys, xs: a.xs.count >= b.xs.count ? a.xs : b.xs) }
    mutating func scale(by rhs: Double) { ys.scale(by: rhs) }
    var magnitudeSquared: Double { ys.magnitudeSquared }

    var points: [CGPoint] {
        zip(xs, ys.values).map { CGPoint(x: $0, y: $1) }
    }
}

private struct ResponseShape: Shape {
    var points: AnimatablePoints
    let zero: CGFloat
    let closed: Bool

    var animatableData: AnimatablePoints {
        get { points }
        set { points = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let pts = points.points
        var path = Path()
        guard let first = pts.first, let last = pts.last, pts.count > 1 else { return path }
        if closed { path.move(to: CGPoint(x: first.x, y: zero)) }
        path.addSmoothCurve(through: pts)
        if closed {
            path.addLine(to: CGPoint(x: last.x, y: zero))
            path.closeSubpath()
        }
        return path
    }
}
