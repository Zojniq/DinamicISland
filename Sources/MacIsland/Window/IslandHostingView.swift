import SwiftUI

/// `NSHostingView` that is "hollow": clicks outside the island shape fall through.
///
/// Two layers of click-through are needed:
/// 1. `NotchPanel.ignoresMouseEvents` (toggled by the controller) — handled by the
///    WindowServer, so events outside the island reach the app underneath. This is the
///    one that really matters: if the window accepts mouse events, the WindowServer routes
///    clicks to it even over fully transparent pixels and `hitTest` returning `nil` would
///    merely *swallow* them.
/// 2. This `hitTest` override — precise per-frame filtering while the window *is*
///    interactive (e.g. the corner areas of the canvas during a spring animation).
final class IslandHostingView<Content: View>: NSHostingView<Content> {

    /// Returns the interactive island rect in **window** coordinates.
    var interactiveRectProvider: (() -> CGRect)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        // WORKAROUND (macOS 13+): NSHostingView otherwise resizes its window to the SwiftUI
        // ideal size on every layout pass — the window would visibly jump during springs.
        // The window is a fixed canvas; SwiftUI animates *inside* it.
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's (theme frame's) coordinate system → convert to window
        // coordinates, which are non-flipped and match `convertFromScreen`.
        guard let provider = interactiveRectProvider,
              let superview else { return super.hitTest(point) }
        let pointInWindow = superview.convert(point, to: nil)
        return provider().contains(pointInWindow) ? super.hitTest(point) : nil
    }

    /// Lets the very first click on an inactive (non-key) panel trigger SwiftUI buttons
    /// instead of being consumed as a "focus" click — essential for play/pause etc.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
