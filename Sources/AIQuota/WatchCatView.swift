import SwiftUI
import AppKit
import QuotaCore

struct FirstQuotaCardKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// An overlay: card geometry provides occlusion without affecting layout or hit testing.
struct WatchCatView: View {
    let watching: Bool
    let selection: WatchMascot
    let card: CGRect
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var kind = WatchMascot.sad
    @State private var entered = Date()
    @State private var exited: Date?

    private static let images: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for kind in WatchMascot.allCases {
            for frame in ["open", "blink"] {
                let name = "\(kind.assetName)-\(frame)"
                if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "WatchCats"),
                   let image = NSImage(contentsOf: url) { result[name] = image }
            }
        }
        return result
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !visible || reduceMotion)) { timeline in
            Canvas { context, size in
                guard visible, card.width > 0,
                      let open = Self.images["\(kind.assetName)-open"],
                      let closed = Self.images["\(kind.assetName)-blink"] else { return }
                let elapsed = timeline.date.timeIntervalSince(exited ?? entered)
                let amount = kind.visibility(elapsed: elapsed, exiting: exited != nil)
                let progress = reduceMotion ? 1 : amount
                context.opacity = reduceMotion ? (exited == nil ? 1 : 0) : 1
                context.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 18))
                let front = kind == .lying && exited == nil
                var mask = Path(CGRect(x: 0, y: 0, width: size.width, height: front ? card.minY + 8 : card.maxY))
                if !front { mask.addRoundedRect(in: card, cornerSize: CGSize(width: 16, height: 16)) }
                context.clip(to: mask, style: FillStyle(eoFill: true))
                let rect: CGRect
                if kind == .lying {
                    let width: CGFloat = 136
                    let height = width * open.size.height / open.size.width
                    rect = CGRect(x: card.minX + 2, y: card.minY + 8 - height + (1 - progress) * height, width: width, height: height)
                } else {
                    let travel = (1 - progress) * 240
                    context.translateBy(x: card.minX + 30 + kind.axis.x * travel,
                                        y: card.minY - 19 + kind.axis.y * travel)
                    context.rotate(by: .radians(-0.32))
                    rect = CGRect(x: -90, y: -90, width: 180, height: 180)
                }
                let age = timeline.date.timeIntervalSince(entered)
                let twitch = reduceMotion || exited != nil ? 0 : kind.earTwitch(at: age)
                drawFrame(open, in: rect, twitch: twitch, context: context)
                if !reduceMotion {
                    context.opacity = kind.blink(at: timeline.date.timeIntervalSince(entered))
                    drawFrame(closed, in: rect, twitch: twitch, context: context)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: watching) {
            if watching {
                kind = selection
                entered = Date()
                exited = nil
                visible = true
            } else if visible {
                exited = Date()
                do {
                    try await Task.sleep(nanoseconds: UInt64((reduceMotion ? 0.15 : kind.exitDuration) * 1_000_000_000))
                    try Task.checkCancellation()
                    visible = false
                } catch { /* A restarted watch owns the new presentation. */ }
            }
        }
    }

    private func drawFrame(_ image: NSImage, in rect: CGRect, twitch: Double, context: GraphicsContext) {
        guard twitch > 0 else {
            context.draw(Image(nsImage: image), in: rect)
            return
        }
        // Only the outer right ear bends. The cheek, ear root and paws retain
        // their original registration against the card, including during blinks.
        let ear = CGRect(x: rect.minX + rect.width * 0.85, y: rect.minY,
                         width: rect.width * 0.15, height: rect.height * 0.87)
        var fixed = context
        var mask = Path(rect)
        mask.addRect(ear)
        fixed.clip(to: mask, style: FillStyle(eoFill: true))
        fixed.draw(Image(nsImage: image), in: rect)
        let slices = 24
        for index in 0..<slices {
            let fraction = Double(index) / Double(slices)
            let bend = fraction * fraction * (3 - 2 * fraction)
            var strip = context
            strip.clip(to: Path(CGRect(x: ear.minX + ear.width * fraction, y: ear.minY,
                                      width: ear.width / Double(slices), height: ear.height)),
                       style: FillStyle(antialiased: false))
            strip.draw(Image(nsImage: image), in: rect.offsetBy(dx: 0, dy: -rect.height * 0.025 * twitch * bend))
        }
    }

}
