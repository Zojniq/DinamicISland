import SwiftUI

struct DynamicIslandView: View {
    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        let state = viewModel.state
        let size = viewModel.currentSize
        let radii = viewModel.radii(for: state)
        let shape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)

        ZStack(alignment: .top) {
            shape
                .fill(Color.black)

            switch state {
            case .expanded:
                ExpandedIslandView(viewModel: viewModel)
                    .transition(.islandContent)

            case .compact:
                CompactIslandView(viewModel: viewModel)
                    .id(viewModel.liveActivity)
                    .transition(.islandContent)

            case .minimal:
                EmptyView()
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .shadow(color: .black.opacity(state == .expanded ? 0.55 : 0), radius: 18, x: 0, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(IslandAnimation.morph(to: state), value: state)
        .animation(IslandAnimation.activitySwap, value: viewModel.liveActivity)
        .animation(IslandAnimation.morph(to: state), value: viewModel.scale)
        .environment(\.colorScheme, .dark)
    }
}
