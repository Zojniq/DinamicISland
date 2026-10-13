import SwiftUI

extension PomodoroTimer.Phase {
    var tint: Color {
        switch self {
        case .focus:      return Color(red: 1.0, green: 0.58, blue: 0.25)
        case .shortBreak: return Color(red: 0.35, green: 0.85, blue: 0.55)
        case .longBreak:  return Color(red: 0.35, green: 0.70, blue: 1.0)
        }
    }
}

// MARK: - Expanded

struct PomodoroWidgetView: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        let tint = timer.phase.tint

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: timer.phase.symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(timer.phase.title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.4)
                    .lineLimit(1)
                Spacer(minLength: 2)
                SessionDots(filled: timer.sessionsInCycle,
                            total: timer.configuration.sessionsBeforeLongBreak,
                            tint: tint)
            }
            .foregroundStyle(tint)

            HStack(spacing: 8) {
                ProgressRing(progress: timer.progress, tint: tint, lineWidth: 3)
                    .frame(width: 22, height: 22)
                Text(timer.displayTime)
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(timer.runState == .paused ? 0.55 : 1))
            }

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                IslandIconButton(systemName: "arrow.counterclockwise", size: 10) { timer.reset() }
                    .foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
                IslandIconButton(systemName: timer.runState == .running ? "pause.fill" : "play.fill",
                                 size: 14) { timer.toggle() }
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                IslandIconButton(systemName: "forward.end.fill", size: 10) { timer.skip() }
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(height: 20)
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .islandCard()
    }
}

private struct SessionDots: View {
    let filled: Int
    let total: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Circle()
                    .fill(i < filled ? tint : tint.opacity(0.25))
                    .frame(width: 4, height: 4)
            }
        }
    }
}

// MARK: - Compact (stays visible in the collapsed island)

struct PomodoroCompactLeading: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        ProgressRing(progress: timer.progress, tint: timer.phase.tint, lineWidth: 2.5)
            .frame(width: 14, height: 14)
            .opacity(timer.runState == .paused ? 0.5 : 1)
    }
}

struct PomodoroCompactTrailing: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        Text(timer.displayTime)
            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(timer.phase.tint.opacity(timer.runState == .paused ? 0.5 : 1))
            .lineLimit(1)
            .fixedSize()
    }
}
