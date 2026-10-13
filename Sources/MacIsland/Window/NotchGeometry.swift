import AppKit

/// Physical geometry of the camera housing ("notch") on a given screen.
///
/// All rects are in **global AppKit screen coordinates** (origin bottom-left of the primary
/// display, y grows upward) — the same space as `NSScreen.frame` and `NSEvent.mouseLocation`,
/// so hit-testing never needs coordinate flipping.
struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let notchSize: CGSize
    /// `false` on external displays / clamshell mode, where we draw a "virtual" notch.
    let hasPhysicalNotch: Bool
    let backingScale: CGFloat

    static func detect(on screen: NSScreen) -> NotchGeometry {
        // `safeAreaInsets.top` is > 0 only on displays with a camera housing (macOS 12+).
        // On a 13.6" M2 Air it's 32pt at default scaling and 37–38pt in "More Space".
        let topInset = screen.safeAreaInsets.top

        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            // `auxiliaryTop{Left,Right}Area` are the usable menu-bar strips on either side of
            // the housing. Whatever is left in the middle IS the notch. This adapts to every
            // "Display ▸ Scaled" resolution, unlike hard-coded 200×32 values.
            let notchWidth = screen.frame.width - left.width - right.width
            return NotchGeometry(
                screenFrame: screen.frame,
                notchSize: CGSize(width: notchWidth, height: topInset),
                hasPhysicalNotch: true,
                backingScale: screen.backingScaleFactor
            )
        }

        // Fallback: no notch → emulate one with the height of the menu bar.
        // `frame.maxY - visibleFrame.maxY` is 0 when the menu bar auto-hides, hence the floor.
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(
            screenFrame: screen.frame,
            notchSize: CGSize(width: 190, height: max(menuBarHeight, 24)),
            hasPhysicalNotch: false,
            backingScale: screen.backingScaleFactor
        )
    }

    /// Rect of a top-anchored, horizontally centred island of `size`.
    /// The island's top edge is flush with the top of the screen so it "grows out of" the notch.
    func islandRect(size: CGSize) -> CGRect {
        let rect = CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return rect.pixelAligned(scale: backingScale)
    }

    var notchRect: CGRect { islandRect(size: notchSize) }
}

extension CGRect {
    /// Snaps to the physical pixel grid. A half-point offset on a 2× panel produces a
    /// 1px grey seam between our black shape and the real notch — very visible on M2 Airs.
    func pixelAligned(scale: CGFloat) -> CGRect {
        guard scale > 0 else { return self }
        let minX = (self.minX * scale).rounded() / scale
        let minY = (self.minY * scale).rounded() / scale
        let maxX = (self.maxX * scale).rounded() / scale
        let maxY = (self.maxY * scale).rounded() / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var isBuiltIn: Bool {
        guard let id = displayID else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }

    var hasNotch: Bool { safeAreaInsets.top > 0 }

    /// Screen the island should live on:
    /// 1. the notched display, 2. the built-in display, 3. the primary (menu-bar) display.
    ///
    /// NOTE: `NSScreen.main` is *not* the primary display — it's the one with the key window,
    /// which changes as the user clicks around. `screens.first` is always the menu-bar screen.
    static var preferredIslandScreen: NSScreen? {
        screens.first(where: \.hasNotch)
            ?? screens.first(where: \.isBuiltIn)
            ?? screens.first
    }
}
