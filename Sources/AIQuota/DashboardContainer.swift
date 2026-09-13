import SwiftUI
import AppKit

@MainActor final class DashboardViewport: ObservableObject {
    @Published var limit = CGSize(width: 416, height: 620)
    @Published var contentHeight: CGFloat = 620
    var preferredSize: CGSize { CGSize(width: limit.width, height: min(contentHeight, limit.height)) }
    func update(_ size: CGSize) { if limit != size { limit = size } }
}

private struct DashboardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct DashboardContainer: View {
    @ObservedObject var viewport: DashboardViewport
    let dashboard: DashboardView
    var body: some View {
        ScrollView(.vertical) {
            dashboard.frame(width: viewport.limit.width).fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: DashboardHeightKey.self, value: geometry.size.height)
                })
        }
        .frame(width: viewport.limit.width, height: viewport.preferredSize.height)
        .background {
            WatchingGlass(store: dashboard.store).allowsHitTesting(false)
        }
        .onPreferenceChange(DashboardHeightKey.self) { height in
            if height > 0, abs(viewport.contentHeight - height) > 0.5 { viewport.contentHeight = height }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

private struct WatchingGlass: View {
    @ObservedObject var store: QuotaStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var watching: Bool { store.watchSeconds > 0 }
    var body: some View {
        ZStack {
            DashboardGlass()
            Color(white: 0.08).opacity(0.18)
            LinearGradient(colors: [Color(red: 0.32, green: 0.36, blue: 0.39),
                                    Color(red: 0.22, green: 0.25, blue: 0.28),
                                    Color(red: 0.27, green: 0.30, blue: 0.32)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(watching ? 0.94 : 0)
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .white.opacity(0.05)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                .opacity(watching ? 1 : 0)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: watching ? 0.8 : 1.6), value: watching)
    }
}

private struct DashboardGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
