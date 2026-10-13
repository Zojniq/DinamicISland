import Combine
import SwiftUI

/// The three Dynamic-Island presentation states.
enum IslandState: Equatable {
    /// Island == physical notch. Visually invisible (black on black).
    case minimal
    /// Notch + "ears" on both sides for a live activity (timer, now playing).
    case compact
    /// Full widget dashboard.
    case expanded
}

/// What the compact island shows while resting. Priority: timer > media.
enum LiveActivity: Equatable {
    case none
    case timer
    case media
}

/// The available pages in the expanded island dashboard.
enum ExpandedPage: Int, CaseIterable, Identifiable {
    case mediaAndFocus = 0
    case systemAndNotes = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .mediaAndFocus:  return "Media & Focus"
        case .systemAndNotes: return "System & Notes"
        }
    }

    var icon: String {
        switch self {
        case .mediaAndFocus:  return "music.note"
        case .systemAndNotes: return "cpu"
        }
    }
}

/// Corner radii of `NotchShape` per state.
struct IslandRadii: Equatable {
    /// Concave "shoulders" that melt into the top bezel.
    let top: CGFloat
    /// Convex bottom corners.
    let bottom: CGFloat
}

/// Single source of truth for the island. The window controller *drives* hover transitions;
/// widgets drive the resting state via `liveActivity`; SwiftUI renders.
@MainActor
final class IslandViewModel: ObservableObject {

    @Published private(set) var state: IslandState = .minimal
    @Published private(set) var geometry: NotchGeometry?
    @Published private(set) var liveActivity: LiveActivity = .none
    @Published var activePage: ExpandedPage = .mediaAndFocus

    /// User-adjustable island scale (Settings, Phase 5). Clamped so it always fits the canvas.
    @Published var scale: CGFloat = 1.0 {
        didSet { scale = min(max(scale, Self.minScale), Self.maxScale) }
    }

    let nowPlaying: NowPlayingService
    let pomodoro: PomodoroTimer
    let systemMonitor: SystemMonitorService
    let scratchpad: ScratchpadService

    /// Written by `NotchWindowController` on every mouse move (not @Published: no UI depends on it).
    var isHovering = false

    private var cancellables = Set<AnyCancellable>()
    private var alertWorkItem: DispatchWorkItem?

    // MARK: Layout constants
    //
    // Everything is derived from the *physical notch*, so the island stays proportional on
    // every MacBook / "Scaled" resolution instead of being a fixed slab of pixels.

    static let minScale: CGFloat = 0.9
    static let maxScale: CGFloat = 1.25
    /// Expanded width = notch width × this factor (≈ 410pt on a 13.6" M2 Air).
    static let expandedWidthFactor: CGFloat = 2.2
    static let expandedWidthRange: ClosedRange<CGFloat> = 380...460
    /// Height of the widget area *below* the notch band (includes widgets + pagination bar).
    static let expandedBodyHeight: CGFloat = 118
    /// Width of each compact "ear" next to the notch.
    static let compactEarWidth: CGFloat = 52
    /// Padding around the max expanded island so SwiftUI shadows aren't clipped by the window.
    static let shadowPadding: CGFloat = 40

    /// Fixed window canvas, large enough for the biggest expanded island + shadow.
    /// The window NEVER resizes: SwiftUI animates inside the canvas (see Phase 2).
    static var canvasSize: CGSize {
        CGSize(
            width: expandedWidthRange.upperBound * maxScale + shadowPadding * 2,
            height: 40 + expandedBodyHeight * maxScale + shadowPadding
        )
    }

    convenience init() {
        self.init(
            nowPlaying: NowPlayingService(),
            pomodoro: PomodoroTimer(),
            systemMonitor: SystemMonitorService(),
            scratchpad: ScratchpadService()
        )
    }

    init(
        nowPlaying: NowPlayingService,
        pomodoro: PomodoroTimer,
        systemMonitor: SystemMonitorService,
        scratchpad: ScratchpadService
    ) {
        self.nowPlaying = nowPlaying
        self.pomodoro = pomodoro
        self.systemMonitor = systemMonitor
        self.scratchpad = scratchpad

        // Derive the resting live activity from the widgets.
        Publishers.CombineLatest(pomodoro.$runState, nowPlaying.$info)
            .map { runState, info -> LiveActivity in
                if runState != .idle { return .timer }
                if info?.isPlaying == true { return .media }
                return .none
            }
            .removeDuplicates()
            .sink { [weak self] activity in self?.setLiveActivity(activity) }
            .store(in: &cancellables)

        // A finished Pomodoro phase briefly pops the island open, like an iOS alert.
        pomodoro.phaseCompleted
            .sink { [weak self] _ in self?.presentAlert() }
            .store(in: &cancellables)
    }

    // MARK: Geometry

    var notchSize: CGSize { geometry?.notchSize ?? CGSize(width: 190, height: 32) }

    var restingState: IslandState { liveActivity == .none ? .minimal : .compact }

    func radii(for state: IslandState) -> IslandRadii {
        switch state {
        case .minimal:  return IslandRadii(top: 4, bottom: 10)
        case .compact:  return IslandRadii(top: 6, bottom: 12)
        case .expanded: return IslandRadii(top: 14, bottom: 26)
        }
    }

    /// Full island size *including* the concave shoulders (`radii.top` on each side),
    /// so the island's body is exactly as wide as the notch (+ ears).
    func size(for state: IslandState) -> CGSize {
        let notch = notchSize
        let shoulders = radii(for: state).top * 2
        switch state {
        case .minimal:
            return CGSize(width: notch.width + shoulders, height: notch.height)
        case .compact:
            return CGSize(width: notch.width + Self.compactEarWidth * 2 + shoulders, height: notch.height)
        case .expanded:
            let base = min(max(notch.width * Self.expandedWidthFactor, Self.expandedWidthRange.lowerBound),
                           Self.expandedWidthRange.upperBound)
            // The notch band keeps its physical height; only the widget body scales.
            return CGSize(width: base * scale, height: notch.height + Self.expandedBodyHeight * scale)
        }
    }

    var currentSize: CGSize { size(for: state) }

    // MARK: Intents

    func update(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    func expand() {
        guard state != .expanded else { return }
        state = .expanded
    }

    func collapse() {
        alertWorkItem?.cancel()
        alertWorkItem = nil
        guard state != restingState else { return }
        state = restingState
    }

    private func setLiveActivity(_ activity: LiveActivity) {
        liveActivity = activity
        if state != .expanded { state = restingState }
    }

    private func presentAlert() {
        expand()
        alertWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isHovering else { return }
            self.collapse()
        }
        alertWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }
}
