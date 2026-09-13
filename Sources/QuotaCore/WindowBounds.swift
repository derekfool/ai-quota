import CoreGraphics
import Foundation

public enum WindowBounds {
    public static func dashboardLimit(in visibleFrame: CGRect) -> CGSize {
        CGSize(width: min(416, max(1, visibleFrame.width - 32)), height: max(1, visibleFrame.height - 32))
    }
    public static func contained(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        let bounds = visibleFrame.insetBy(dx: 8, dy: 8)
        let width = min(frame.width, max(1, bounds.width))
        let height = min(frame.height, max(1, bounds.height))
        return CGRect(x: max(bounds.minX, min(frame.minX, bounds.maxX - width)),
                      y: max(bounds.minY, min(frame.minY, bounds.maxY - height)), width: width, height: height)
    }
}
