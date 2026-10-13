import SwiftUI

/// Expanded state: header row in the notch band + paginated widget dashboard below.
///
///  ┌──(date)────────[ notch ]────────(⚙︎)──┐
///  │ ┌───────── Page 0 / 1 ────────────┐   │
///  │ └─────────────────────────────────┘   │
///  │         [ ● Media ]  ○                │
///  ╰───────────────────────────────────────╯
struct ExpandedIslandView: View {
    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        let size = viewModel.size(for: .expanded)
        let notch = viewModel.notchSize
        let radii = viewModel.radii(for: .expanded)

        VStack(spacing: 0) {
            header(notchWidth: notch.width)
                .frame(height: notch.height)

            // Content Pages
            ZStack {
                switch viewModel.activePage {
                case .mediaAndFocus:
                    HStack(spacing: 8) {
                        MediaWidgetView(service: viewModel.nowPlaying)
                        PomodoroWidgetView(timer: viewModel.pomodoro)
                            .frame(width: 128)
                    }
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(x: -20)),
                            removal: .opacity.combined(with: .offset(x: -20))
                        )
                    )

                case .systemAndNotes:
                    HStack(spacing: 8) {
                        SystemMonitorWidgetView(service: viewModel.systemMonitor)
                        ScratchpadWidgetView(service: viewModel.scratchpad)
                            .frame(width: 142)
                    }
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(x: 20)),
                            removal: .opacity.combined(with: .offset(x: 20))
                        )
                    )
                }
            }
            .padding(.top, 2)
            .frame(maxHeight: .infinity)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: viewModel.activePage)

            // Pagination Dots & Switcher
            paginationBar
                .padding(.top, 3)
                .padding(.bottom, 6)
        }
        .padding(.horizontal, radii.top + 10)
        .frame(width: size.width, height: size.height)
    }

    private func header(notchWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Calendar placeholder
            Label {
                Text(Date(), format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
            } icon: {
                Image(systemName: "calendar")
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)

            Spacer(minLength: notchWidth + 12)

            IslandIconButton(systemName: "gearshape.fill", size: 11, frame: 22) {
                AppDelegate.openSettings()
            }
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var paginationBar: some View {
        HStack(spacing: 8) {
            ForEach(ExpandedPage.allCases) { page in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        viewModel.activePage = page
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.activePage == page ? Color.white : Color.white.opacity(0.28))
                            .frame(
                                width: viewModel.activePage == page ? 5.5 : 4.5,
                                height: viewModel.activePage == page ? 5.5 : 4.5
                            )

                        if viewModel.activePage == page {
                            Text(page.title)
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(viewModel.activePage == page ? Color.white.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}
