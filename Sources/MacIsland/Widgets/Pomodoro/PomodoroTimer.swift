import AppKit
import Combine

/// Pomodoro state machine: focus → short break → … → (every Nth) long break → focus.
///
/// Time is tracked as an absolute `endDate`, never by decrementing a counter: timers are
/// coalesced by App Nap and frozen during sleep, so "remaining -= 1" drifts. With an end
/// date, the first tick after waking simply notices the phase is over.
@MainActor
final class PomodoroTimer: ObservableObject {

    enum Phase: String, CaseIterable, Sendable {
        case focus, shortBreak, longBreak

        var title: String {
            switch self {
            case .focus:      return "Focus"
            case .shortBreak: return "Short Break"
            case .longBreak:  return "Long Break"
            }
        }

        var symbol: String {
            switch self {
            case .focus:      return "brain.head.profile"
            case .shortBreak: return "cup.and.saucer.fill"
            case .longBreak:  return "figure.walk"
            }
        }
    }

    enum RunState: Equatable {
        case idle, running, paused
    }

    struct Configuration: Equatable {
        var focusDuration: TimeInterval = 25 * 60
        var shortBreakDuration: TimeInterval = 5 * 60
        var longBreakDuration: TimeInterval = 15 * 60
        var sessionsBeforeLongBreak = 4
        var autoStartBreaks = true
        var autoStartFocus = false
        var playsSound = true

        func duration(for phase: Phase) -> TimeInterval {
            switch phase {
            case .focus:      return focusDuration
            case .shortBreak: return shortBreakDuration
            case .longBreak:  return longBreakDuration
            }
        }
    }

    @Published private(set) var phase: Phase = .focus
    @Published private(set) var runState: RunState = .idle
    @Published private(set) var remaining: TimeInterval
    @Published private(set) var completedFocusSessions = 0
    @Published var configuration = Configuration() {
        didSet { if runState == .idle { remaining = configuration.duration(for: phase) } }
    }

    /// Emits the phase that just finished naturally (not skipped).
    let phaseCompleted = PassthroughSubject<Phase, Never>()

    private var endDate: Date?
    private var ticker: AnyCancellable?
    private var activity: NSObjectProtocol?

    init() {
        remaining = Configuration().focusDuration
    }

    // MARK: Derived

    var totalDuration: TimeInterval { configuration.duration(for: phase) }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return min(max(1 - remaining / totalDuration, 0), 1)
    }

    /// "MM:SS", rounded *up* so the display reads 25:00 at start and 00:01 in the last second.
    var displayTime: String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// Dots filled in the current cycle (0…sessionsBeforeLongBreak).
    var sessionsInCycle: Int {
        let n = max(configuration.sessionsBeforeLongBreak, 1)
        let mod = completedFocusSessions % n
        return (mod == 0 && completedFocusSessions > 0 && phase == .longBreak) ? n : mod
    }

    // MARK: Intents

    func toggle() {
        switch runState {
        case .idle:    start()
        case .running: pause()
        case .paused:  resume()
        }
    }

    func start() {
        remaining = totalDuration
        resume()
    }

    func resume() {
        guard runState != .running else { return }
        endDate = Date().addingTimeInterval(remaining)
        runState = .running
        startTicker()
    }

    func pause() {
        guard runState == .running, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        runState = .paused
        stopTicker()
    }

    /// Stops and rewinds the current phase.
    func reset() {
        stopTicker()
        endDate = nil
        runState = .idle
        remaining = totalDuration
    }

    /// Jumps to the next phase without counting the current one as completed.
    func skip() {
        advance(completedNaturally: false)
    }

    // MARK: Engine

    private func startTicker() {
        // `.common` run-loop mode keeps ticking while a menu is open / during event tracking.
        ticker = Timer.publish(every: 1, tolerance: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }

        // Opt out of App Nap while running: an accessory app whose only window is a tiny
        // overlay is a prime candidate for timer coalescing (ticks every ~10s).
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
                reason: "Pomodoro timer running"
            )
        }
    }

    private func stopTicker() {
        ticker = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func tick() {
        guard let endDate else { return }
        let left = endDate.timeIntervalSinceNow
        if left <= 0 {
            remaining = 0
            complete()
        } else {
            remaining = left
        }
    }

    private func complete() {
        let finished = phase
        if configuration.playsSound {
            NSSound(named: finished == .focus ? "Glass" : "Hero")?.play()
        }
        advance(completedNaturally: true)
        phaseCompleted.send(finished)
    }

    private func advance(completedNaturally: Bool) {
        let wasActive = runState != .idle
        let finished = phase

        if finished == .focus, completedNaturally {
            completedFocusSessions += 1
        }

        let next: Phase
        switch finished {
        case .focus:
            let n = max(configuration.sessionsBeforeLongBreak, 1)
            next = (completedNaturally && completedFocusSessions % n == 0) ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            next = .focus
        }

        stopTicker()
        endDate = nil
        runState = .idle
        phase = next
        remaining = configuration.duration(for: next)

        let autoStart = next == .focus ? configuration.autoStartFocus : configuration.autoStartBreaks
        if wasActive, autoStart {
            resume()
        }
    }
}
