import SwiftUI
import QuotaCore

struct QuotaChangeEffect: View {
    let change: QuotaChange
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var color: Color { change.dominantDelta > 0 ? .mint : Color(red: 1, green: 0.60, blue: 0.58) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let progress = max(0, min(1, timeline.date.timeIntervalSince(change.startedAt) / change.intensity.duration))
            Canvas { context, size in
                guard progress < 1 else { return }
                let fade = pow(1 - progress, 1.3)
                let pulse = reduceMotion ? fade : (0.45 + 0.55 * abs(sin(progress * .pi * (change.intensity == .major ? 3 : 1)))) * fade
                let inset = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
                let outline = Path(roundedRect: inset, cornerRadius: 14)
                context.stroke(outline, with: .color(color.opacity(pulse * 0.9)), lineWidth: change.intensity == .small ? 2 : 4)
                context.fill(outline, with: .color(color.opacity(pulse * (change.intensity == .major ? 0.14 : 0.06))))
                guard !reduceMotion, change.intensity != .small else { return }
                let center = CGPoint(x: size.width * 0.78, y: size.height * 0.42)
                let radius = 12 + progress * size.width * 1.1
                let ripple = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.stroke(Path(ellipseIn: ripple), with: .color(color.opacity(fade * 0.55)), lineWidth: change.intensity == .major ? 3 : 1.5)
                let count = change.intensity == .major ? 22 : 8
                for index in 0..<count {
                    let angle = Double(index) * 2.399963
                    let distance = (25 + Double(index % 5) * 14) * progress * (change.intensity == .major ? 2.3 : 1)
                    let x = center.x + cos(angle) * distance
                    let y = center.y + sin(angle) * distance + (change.dominantDelta < 0 ? 35 : -25) * progress
                    let length = change.intensity == .major ? 4.0 : 2.0
                    let dot = CGRect(x: x, y: y, width: length, height: length)
                    context.fill(Path(ellipseIn: dot), with: .color(color.opacity(fade * 0.8)))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct QuotaNumericTransition: ViewModifier {
    let value: Double
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 14.0, *) { content.contentTransition(.numericText(value: value)) }
        else { content }
    }
}
