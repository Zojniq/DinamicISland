import Foundation
import AppKit

/// Immutable snapshot of the global system Now Playing media track.
struct NowPlayingInfo: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    let isPlaying: Bool
    let artworkData: Data?
    let timestamp: Date

    var trackID: String {
        "\(title)|\(artist)|\(album)|\(duration)"
    }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return position }
        let delta = date.timeIntervalSince(timestamp)
        let extrapolated = position + delta
        return duration > 0 ? min(extrapolated, duration) : max(extrapolated, 0)
    }

    func with(isPlaying: Bool, at date: Date = Date()) -> NowPlayingInfo {
        NowPlayingInfo(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: elapsed(at: date),
            isPlaying: isPlaying,
            artworkData: artworkData,
            timestamp: date
        )
    }

    func isEquivalent(to other: NowPlayingInfo?) -> Bool {
        guard let other else { return false }
        return trackID == other.trackID
            && isPlaying == other.isPlaying
            && abs(elapsed(at: other.timestamp) - other.position) < 1.5
    }
}
