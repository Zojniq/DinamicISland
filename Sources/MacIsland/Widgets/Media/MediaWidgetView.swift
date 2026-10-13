import SwiftUI

// MARK: - Expanded

struct MediaWidgetView: View {
    @ObservedObject var service: NowPlayingService

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(image: service.artwork, size: 56, cornerRadius: 10)

            VStack(alignment: .leading, spacing: 2) {
                if let info = service.info {
                    Text(info.title)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(info.artist.isEmpty ? (info.album.isEmpty ? "System Audio" : info.album) : info.artist)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                    MediaProgressBar(info: info)
                        .padding(.top, 4)
                } else {
                    Text("Nothing Playing")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("Safari, Chrome, Music…")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer(minLength: 0)
                controls
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .islandCard()
    }

    private var controls: some View {
        HStack(spacing: 6) {
            IslandIconButton(systemName: "backward.fill", size: 11) { service.previousTrack() }
            IslandIconButton(systemName: service.isPlaying ? "pause.fill" : "play.fill", size: 15) {
                service.playPause()
            }
            IslandIconButton(systemName: "forward.fill", size: 11) { service.nextTrack() }
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(height: 20)
        .disabled(service.info == nil)
        .opacity(service.info == nil ? 0.35 : 1)
    }
}

struct MediaProgressBar: View {
    let info: NowPlayingInfo

    var body: some View {
        // Extrapolates locally; ticks only while playing.
        TimelineView(.animation(minimumInterval: 1, paused: !info.isPlaying)) { context in
            let progress = info.duration > 0 ? info.elapsed(at: context.date) / info.duration : 0
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    }
            }
            .frame(height: 3)
        }
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: image)
    }
}

// MARK: - Compact

struct MediaCompactLeading: View {
    @ObservedObject var service: NowPlayingService

    var body: some View {
        ArtworkView(image: service.artwork, size: 20, cornerRadius: 5)
    }
}

struct MediaCompactTrailing: View {
    @ObservedObject var service: NowPlayingService

    var body: some View {
        EqualizerBars(isPlaying: service.isPlaying)
    }
}

/// Lightweight fake spectrum: 4 capsules driven by phase-shifted sines at 15 fps.
/// (A real FFT would require Screen-Recording/audio-tap permissions — not worth it here.)
struct EqualizerBars: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let level = barLevel(for: i, time: t)
                    Capsule()
                        .frame(width: 2.5, height: max(3.0, 14.0 * level))
                }
            }
            .frame(height: 14)
        }
        .foregroundStyle(.white.opacity(0.85))
    }

    private func barLevel(for index: Int, time: Double) -> Double {
        guard isPlaying else { return 0.22 }
        let freq = 4.2 + Double(index) * 1.6
        let phase = Double(index) * 0.9
        let wave = abs(sin(time * freq + phase))
        return 0.3 + 0.7 * wave
    }
}
