import SwiftUI

/// Compact state: live-activity "ears" on both sides of the hardware notch.
struct CompactIslandView: View {
    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        let notch = viewModel.notchSize
        let radii = viewModel.radii(for: .compact)
        let ear = IslandViewModel.compactEarWidth

        HStack(spacing: 0) {
            leading
                .padding(.leading, 8)
                .frame(width: ear, alignment: .leading)
            // Nothing may be drawn under the camera housing.
            Color.clear.frame(width: notch.width)
            trailing
                .padding(.trailing, 8)
                .frame(width: ear, alignment: .trailing)
        }
        .padding(.horizontal, radii.top)
        .frame(width: viewModel.size(for: .compact).width, height: notch.height)
    }

    @ViewBuilder private var leading: some View {
        switch viewModel.liveActivity {
        case .timer: PomodoroCompactLeading(timer: viewModel.pomodoro)
        case .media: MediaCompactLeading(service: viewModel.nowPlaying)
        case .none:  EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch viewModel.liveActivity {
        case .timer: PomodoroCompactTrailing(timer: viewModel.pomodoro)
        case .media: MediaCompactTrailing(service: viewModel.nowPlaying)
        case .none:  EmptyView()
        }
    }
}
