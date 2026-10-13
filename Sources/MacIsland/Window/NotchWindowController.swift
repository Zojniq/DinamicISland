import AppKit
import Combine
import SwiftUI

/// Owns the `NotchPanel`, keeps it glued to the notch across display changes, and turns
/// raw mouse positions into island state transitions (hover-to-expand, leave-to-collapse).
@MainActor
final class NotchWindowController: NSWindowController {

    private let viewModel: IslandViewModel
    private let mouse = MouseTrackingService()
    private var cancellables = Set<AnyCancellable>()

    private var expandWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?

    // MARK: Hover tuning

    /// Dwell before expanding: filters out the cursor merely flying past to a menu item.
    private let expandDelay: TimeInterval = 0.08
    /// Grace period before collapsing: forgives brief overshoots while moving to a button.
    private let collapseDelay: TimeInterval = 0.30
    /// Hysteresis: expanded island keeps its hover zone slightly larger than its shape.
    private let expandedHoverSlop: CGFloat = 14
    /// Collapsed hot zone is a bit wider than the notch to be easy to hit.
    private let collapsedHoverSlop: CGFloat = 10

    private var panel: NotchPanel { window as! NotchPanel }

    // MARK: Init

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel

        let screen = NSScreen.preferredIslandScreen ?? NSScreen.screens[0]
        let geometry = NotchGeometry.detect(on: screen)
        viewModel.update(geometry: geometry)

        let panel = NotchPanel(contentRect: Self.panelFrame(for: geometry))
        super.init(window: panel)

        let hostingView = IslandHostingView(rootView: DynamicIslandView(viewModel: viewModel))
        hostingView.interactiveRectProvider = { [weak self] in
            self?.interactiveRectInWindow ?? .zero
        }
        panel.contentView = hostingView

        bindMouse()
        bindSystemNotifications()
        bindState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func showIsland() {
        // `orderFrontRegardless` shows the panel without activating MacIsland
        // (`makeKeyAndOrderFront` would steal focus from the user's current app).
        panel.orderFrontRegardless()
        mouse.start()
    }

    // MARK: Geometry

    /// The panel is a fixed canvas, top-centred on the screen, flush with the top edge.
    private static func panelFrame(for geometry: NotchGeometry) -> CGRect {
        geometry.islandRect(size: IslandViewModel.canvasSize)
    }

    /// Current island rect in global screen coordinates (target size, not mid-animation).
    private var islandRectOnScreen: CGRect {
        guard let geometry = viewModel.geometry else { return .zero }
        return geometry.islandRect(size: viewModel.currentSize)
    }

    private var interactiveRectInWindow: CGRect {
        panel.convertFromScreen(islandRectOnScreen)
    }

    /// Re-detects the notch and re-pins the panel. Called on any display reconfiguration:
    /// resolution change, external monitor plug/unplug, lid open/close (clamshell), wake.
    private func repositionPanel() {
        guard let screen = NSScreen.preferredIslandScreen else { return }
        let geometry = NotchGeometry.detect(on: screen)
        viewModel.update(geometry: geometry)
        // `display: false` — SwiftUI will redraw itself; avoids a synchronous flash.
        panel.setFrame(Self.panelFrame(for: geometry), display: false)
        panel.orderFrontRegardless()
    }

    // MARK: Mouse → state machine

    private func bindMouse() {
        mouse.events
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)
    }

    private func handle(_ event: MouseTrackingService.Event) {
        switch event {
        case .moved(let point), .dragged(let point):
            updateHover(at: point)

        case .mouseDown(let point):
            // Click outside an expanded island dismisses it immediately (like a popover).
            if viewModel.state == .expanded,
               !islandRectOnScreen.insetBy(dx: -expandedHoverSlop, dy: -expandedHoverSlop).contains(point) {
                cancelPendingTransitions()
                viewModel.collapse()
            }

        case .mouseUp:
            break
        }
    }

    private func updateHover(at point: CGPoint) {
        let isInside = hoverZone.contains(point)

        // Flip WindowServer-level click-through only when the answer changes:
        // each assignment is an IPC call to the WindowServer.
        let shouldIgnore = !isInside
        if panel.ignoresMouseEvents != shouldIgnore {
            panel.ignoresMouseEvents = shouldIgnore
        }
        viewModel.isHovering = isInside

        if isInside {
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            guard viewModel.state != .expanded, expandWorkItem == nil else { return }
            let item = DispatchWorkItem { [weak self] in
                self?.expandWorkItem = nil
                self?.viewModel.expand()
            }
            expandWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + expandDelay, execute: item)
        } else {
            expandWorkItem?.cancel()
            expandWorkItem = nil
            guard viewModel.state == .expanded, collapseWorkItem == nil else { return }
            let item = DispatchWorkItem { [weak self] in
                self?.collapseWorkItem = nil
                self?.viewModel.collapse()
            }
            collapseWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: item)
        }
    }

    private var hoverZone: CGRect {
        let rect = islandRectOnScreen
        let slop = viewModel.state == .expanded ? expandedHoverSlop : collapsedHoverSlop
        var zone = rect.insetBy(dx: -slop, dy: -slop)
        // Fitts's law: the cursor "slammed" to the top edge can report y == screen.maxY
        // exactly; make sure the zone reaches (and slightly exceeds) the top of the display.
        if let geometry = viewModel.geometry {
            zone.size.height = geometry.screenFrame.maxY + 2 - zone.minY
        }
        return zone
    }

    private func cancelPendingTransitions() {
        expandWorkItem?.cancel(); expandWorkItem = nil
        collapseWorkItem?.cancel(); collapseWorkItem = nil
    }

    // MARK: State side effects

    private func bindState() {
        viewModel.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                // Key focus only while expanded (Quick Notes text field, Phase 4).
                self.panel.allowsKeyFocus = (state == .expanded)
                if state != .expanded, self.panel.isKeyWindow {
                    // Hand focus back without activating anyone; the previously
                    // frontmost app regains key status automatically.
                    self.panel.resignKey()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: System notifications

    private func bindSystemNotifications() {
        let screenChanges = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .map { _ in () }

        let workspace = NSWorkspace.shared.notificationCenter
        // Displays are re-enumerated on wake; notch metrics may be stale until then.
        let wake = workspace.publisher(for: NSWorkspace.didWakeNotification).map { _ in () }
        let screensWake = workspace.publisher(for: NSWorkspace.screensDidWakeNotification).map { _ in () }

        // These fire in bursts (often 3–5× for one plug event) → debounce.
        Publishers.Merge3(screenChanges, wake, screensWake)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] in self?.repositionPanel() }
            .store(in: &cancellables)

        // WORKAROUND: after full-screen transitions / Space switches, non-activating panels
        // occasionally end up ordered behind the new Space's windows despite
        // `.canJoinAllSpaces`. Re-ordering front on every Space change is cheap and robust.
        workspace.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.panel.orderFrontRegardless() }
            .store(in: &cancellables)
    }
}
