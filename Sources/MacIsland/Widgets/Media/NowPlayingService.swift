import AppKit
import Combine
import Foundation

@MainActor
final class NowPlayingService: ObservableObject {

    @Published private(set) var info: NowPlayingInfo?
    @Published private(set) var artwork: NSImage?

    var isPlaying: Bool { info?.isPlaying ?? false }

    private let bridge = MediaRemoteBridge.shared
    private var cancellables = Set<AnyCancellable>()
    private var lastArtworkKey: String?
    private var currentSource: MediaRemoteBridge.SourceApp = .systemKey
    private var videoMetaCache: [String: (title: String, artist: String)] = [:]

    init() {
        let distCenter = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            distCenter.publisher(for: Notification.Name(name))
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &cancellables)
        }

        Timer.publish(every: 1.2, tolerance: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        refresh()
    }

    func playPause() {
        if let current = info {
            self.info = current.with(isPlaying: !current.isPlaying)
        }
        bridge.sendCommand(.togglePlayPause, to: currentSource)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refresh()
        }
    }

    func nextTrack() {
        bridge.sendCommand(.nextTrack, to: currentSource)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refresh()
        }
    }

    func previousTrack() {
        bridge.sendCommand(.previousTrack, to: currentSource)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refresh()
        }
    }

    func refresh() {
        bridge.probeActiveMedia { [weak self] probed in
            guard let self else { return }
            self.applyProbedMedia(probed)
        }
    }

    private func applyProbedMedia(_ probed: MediaRemoteBridge.ProbedMedia?) {
        guard let probed else {
            if self.info != nil {
                self.info = nil
                self.artwork = nil
                self.lastArtworkKey = nil
            }
            return
        }

        self.currentSource = probed.source

        var resolvedTitle = probed.title
        var resolvedArtist = probed.artist

        if let vid = probed.videoID {
            if !resolvedTitle.isEmpty {
                videoMetaCache[vid] = (resolvedTitle, resolvedArtist)
            } else if let cached = videoMetaCache[vid] {
                resolvedTitle = cached.title
                resolvedArtist = cached.artist
            } else {
                resolvedTitle = "YouTube Music"
                fetchYouTubeMeta(videoID: vid)
            }
        }

        if resolvedTitle.isEmpty {
            resolvedTitle = "Web Media"
        }

        let newInfo = NowPlayingInfo(
            title: resolvedTitle,
            artist: resolvedArtist,
            album: probed.album,
            duration: probed.duration,
            position: probed.position,
            isPlaying: probed.isPlaying,
            artworkData: nil,
            timestamp: Date()
        )

        if !newInfo.isEquivalent(to: self.info) {
            self.info = newInfo
        }

        if let artKey = probed.artworkURL {
            if artKey != self.lastArtworkKey || self.artwork == nil {
                self.lastArtworkKey = artKey
                fetchArtwork(for: artKey)
            }
        } else if self.artwork != nil {
            self.lastArtworkKey = nil
            self.artwork = nil
        }
    }

    private func fetchYouTubeMeta(videoID: String) {
        guard let url = URL(string: "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoID)&format=json") else { return }
        Task.detached(priority: .userInitiated) {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawTitle = json["title"] as? String else { return }

            let author = (json["author_name"] as? String)?.replacingOccurrences(of: " - Topic", with: "") ?? "YouTube Music"
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.videoMetaCache[videoID] = (rawTitle, author)
                self.refresh()
            }
        }
    }

    private func fetchArtwork(for key: String) {
        Task.detached(priority: .userInitiated) {
            var resolvedData: Data?

            if key.hasPrefix("itunes://") {
                let query = String(key.dropFirst("itunes://".count))
                if let searchURL = URL(string: "https://itunes.apple.com/search?term=\(query)&entity=song&limit=1"),
                   let (jsonData, _) = try? await URLSession.shared.data(from: searchURL),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let results = json["results"] as? [[String: Any]],
                   let first = results.first,
                   var artURLStr = first["artworkUrl100"] as? String {
                    artURLStr = artURLStr.replacingOccurrences(of: "100x100bb", with: "300x300bb")
                    if let artURL = URL(string: artURLStr),
                       let (imgData, _) = try? await URLSession.shared.data(from: artURL) {
                        resolvedData = imgData
                    }
                }
            } else if let url = URL(string: key),
                      let (imgData, _) = try? await URLSession.shared.data(from: url) {
                resolvedData = imgData
            }

            guard let data = resolvedData, let img = NSImage(data: data) else { return }

            await MainActor.run { [weak self] in
                guard let self, self.lastArtworkKey == key else { return }
                self.artwork = img
            }
        }
    }
}
