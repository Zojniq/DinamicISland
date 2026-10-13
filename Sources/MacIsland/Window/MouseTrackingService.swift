import AppKit
import Combine

/// System-wide mouse tracking without Accessibility permission.
///
/// Why monitors instead of `NSTrackingArea`? Tracking areas only fire while the window
/// receives mouse events — but our panel is click-through (`ignoresMouseEvents = true`)
/// most of the time, so it would never "see" the cursor approaching the notch.
///
/// - Global monitor: events delivered to OTHER apps (the common case, panel is click-through).
/// - Local monitor:  events delivered to OUR app (panel is interactive / Settings is open).
/// Both are required; each one is blind to the other's events.
///
/// Mouse event monitors do NOT require Accessibility/Input Monitoring permission
/// (only key-event monitors do), so the island works out of the box.
@MainActor
final class MouseTrackingService {

    enum Event {
        case moved(CGPoint)
        case dragged(CGPoint)      // used later for drag-and-drop of files onto the island
        case mouseDown(CGPoint)
        case mouseUp(CGPoint)
    }

    /// Positions are in global AppKit screen coordinates (same space as `NSScreen.frame`).
    let events = PassthroughSubject<Event, Never>()

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private let mask: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged,
        .leftMouseDown, .rightMouseDown, .leftMouseUp
    ]

    func start() {
        guard globalMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event // never swallow — SwiftUI must still receive the event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        // `event.locationInWindow` is window-relative for local events but screen-relative
        // for global ones. `NSEvent.mouseLocation` is always global screen coordinates.
        let location = NSEvent.mouseLocation

        switch event.type {
        case .mouseMoved:
            events.send(.moved(location))
        case .leftMouseDragged, .rightMouseDragged:
            events.send(.dragged(location))
        case .leftMouseDown, .rightMouseDown:
            events.send(.mouseDown(location))
        case .leftMouseUp:
            events.send(.mouseUp(location))
        default:
            break
        }
    }
}
