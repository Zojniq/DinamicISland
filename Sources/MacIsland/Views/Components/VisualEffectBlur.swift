import AppKit
import SwiftUI

/// Behind-window blur (`NSVisualEffectView`) with square top corners and rounded bottom
/// corners, matching the island body below the notch band.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var bottomCornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        // `.behindWindow` samples the desktop/apps *behind* our transparent panel — real
        // frosted glass. (`.withinWindow` would blur our own, empty, canvas.)
        view.blendingMode = .behindWindow
        // CRITICAL WORKAROUND: the default `.followsWindowActiveState` renders the material
        // as a flat opaque grey whenever the window isn't key — which for our non-activating
        // panel is ~always. Force the live, active appearance.
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.maskImage = Self.maskImage(bottomRadius: bottomCornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.maskImage = Self.maskImage(bottomRadius: bottomCornerRadius)
    }

    /// WORKAROUND: behind-window vibrancy is composited by the WindowServer, so SwiftUI
    /// `.clipShape` / `layer.cornerRadius` are NOT reliably honoured on it. `maskImage`
    /// is the officially supported way to shape it. A 9-slice image (`capInsets` +
    /// `.stretch`) scales to any size without re-rendering on resize.
    private static func maskImage(bottomRadius r: CGFloat) -> NSImage {
        let side = r * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY + r))
            path.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: rect.minY + r),
                           radius: r, startAngle: 0, endAngle: 270, clockwise: true)
            path.line(to: NSPoint(x: rect.minX + r, y: rect.minY))
            path.appendArc(withCenter: NSPoint(x: rect.minX + r, y: rect.minY + r),
                           radius: r, startAngle: 270, endAngle: 180, clockwise: true)
            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }
}
