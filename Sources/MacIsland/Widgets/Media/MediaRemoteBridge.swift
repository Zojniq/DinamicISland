import Foundation
import AppKit
import Darwin

final class MediaRemoteBridge: @unchecked Sendable {

    static let shared = MediaRemoteBridge()

    enum Command: Int32, Sendable {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case stop = 3
        case nextTrack = 4
        case previousTrack = 5
    }

    enum SourceApp: Sendable, Equatable {
        case spotify
        case appleMusic
        case chromium(appName: String)
        case safari
        case systemKey
    }

    struct ProbedMedia: Sendable {
        let videoID: String?
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let position: Double
        let isPlaying: Bool
        let artworkURL: String?
        let source: SourceApp
    }

    private let NX_KEYTYPE_PLAY: Int32 = 16
    private let NX_KEYTYPE_NEXT: Int32 = 17
    private let NX_KEYTYPE_PREVIOUS: Int32 = 18

    private let workerQueue = DispatchQueue(label: "com.macisland.mediabridge", qos: .userInitiated)

    var isAvailable: Bool { true }

    private init() {}

    func sendCommand(_ command: Command, to source: SourceApp) {
        workerQueue.async {
            switch source {
            case .spotify:
                Self.controlPlayer(appName: "Spotify", command: command)
            case .appleMusic:
                Self.controlPlayer(appName: "Music", command: command)
            case .chromium(let appName):
                if !Self.controlChromiumTab(appName: appName, command: command) {
                    self.sendHardwareKey(for: command)
                }
            case .safari, .systemKey:
                self.sendHardwareKey(for: command)
            }
        }
    }

    private static func controlPlayer(appName: String, command: Command) {
        let action: String
        switch command {
        case .play: action = "play"
        case .pause: action = "pause"
        case .togglePlayPause: action = "playpause"
        case .stop: action = "stop"
        case .nextTrack: action = "next track"
        case .previousTrack: action = "previous track"
        }
        _ = runOSAScript("tell application \"\(appName)\" to \(action)")
    }

    private static func controlChromiumTab(appName: String, command: Command) -> Bool {
        let js: String
        switch command {
        case .play:
            js = "(function(){var v=document.querySelector('video,audio');if(v&&v.paused){var b=document.querySelector('ytmusic-player-bar #play-pause-button, #play-pause-button, .ytp-play-button');if(b){b.click();}else{v.play();}return 'ok';}return 'ok';})()"
        case .pause, .stop:
            js = "(function(){var v=document.querySelector('video,audio');if(v&&!v.paused){var b=document.querySelector('ytmusic-player-bar #play-pause-button, #play-pause-button, .ytp-play-button');if(b){b.click();}else{v.pause();}return 'ok';}return 'ok';})()"
        case .togglePlayPause:
            js = "(function(){var b=document.querySelector('ytmusic-player-bar #play-pause-button, #play-pause-button, .ytp-play-button');if(b){b.click();return 'ok';}var v=document.querySelector('video,audio');if(v){if(v.paused)v.play();else v.pause();return 'ok';}return '';})()"
        case .nextTrack:
            js = "(function(){var b=document.querySelector('ytmusic-player-bar .next-button, .next-button.ytmusic-player-bar, .ytp-next-button');if(b){b.click();return 'ok';}var v=document.querySelector('video,audio');if(v){v.currentTime=v.duration||99999;return 'ok';}return '';})()"
        case .previousTrack:
            js = "(function(){var b=document.querySelector('ytmusic-player-bar .previous-button, .previous-button.ytmusic-player-bar, .ytp-prev-button');if(b){b.click();return 'ok';}var v=document.querySelector('video,audio');if(v){v.currentTime=0;return 'ok';}return '';})()"
        }

        let script = """
        tell application "\(appName)"
            repeat with w in windows
                repeat with t in tabs of w
                    set u to URL of t
                    if u contains "music.youtube.com/watch" or u contains "youtube.com/watch" then
                        try
                            set r to execute t javascript "\(js)"
                            if r is "ok" then return "ok"
                        end try
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
        return runOSAScript(script) == "ok"
    }

    private func sendHardwareKey(for command: Command) {
        let key: Int32
        switch command {
        case .play, .pause, .togglePlayPause, .stop:
            key = NX_KEYTYPE_PLAY
        case .nextTrack:
            key = NX_KEYTYPE_NEXT
        case .previousTrack:
            key = NX_KEYTYPE_PREVIOUS
        }

        DispatchQueue.main.async {
            func postKey(down: Bool) {
                let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
                let data1 = Int((key << 16) | ((down ? 0xa : 0xb) << 8))

                if let ev = NSEvent.otherEvent(
                    with: .systemDefined,
                    location: .zero,
                    modifierFlags: flags,
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    subtype: 8,
                    data1: data1,
                    data2: -1
                ) {
                    ev.cgEvent?.post(tap: .cghidEventTap)
                }
            }
            postKey(down: true)
            postKey(down: false)
        }
    }

    func probeActiveMedia(completion: @escaping @MainActor @Sendable (ProbedMedia?) -> Void) {
        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        )

        workerQueue.async {
            let result = Self.probeSync(runningBundleIDs: runningBundleIDs)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private static func probeSync(runningBundleIDs: Set<String>) -> ProbedMedia? {
        var pausedCandidate: ProbedMedia?

        if runningBundleIDs.contains("com.spotify.client"),
           let spot = querySpotify() {
            if spot.isPlaying { return spot }
            pausedCandidate = spot
        }

        if runningBundleIDs.contains("com.apple.Music"),
           let music = queryAppleMusic() {
            if music.isPlaying { return music }
            if pausedCandidate == nil { pausedCandidate = music }
        }

        let chromiumTargets: [(bundleID: String, appName: String)] = [
            ("com.google.Chrome", "Google Chrome"),
            ("company.thebrowser.Browser", "Arc"),
            ("com.brave.Browser", "Brave Browser")
        ]

        for target in chromiumTargets where runningBundleIDs.contains(target.bundleID) {
            if let web = queryChromium(appName: target.appName) {
                return web
            }
        }

        if runningBundleIDs.contains("com.apple.Safari"),
           let safari = querySafari() {
            return safari
        }

        return pausedCandidate
    }

    private static func runOSAScript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private static func querySpotify() -> ProbedMedia? {
        let script = """
        tell application "Spotify"
            if player state is stopped then return ""
            set st to (player state as string)
            set t to name of current track
            set a to artist of current track
            set al to album of current track
            set d to (duration of current track) / 1000.0
            set p to player position
            set art to artwork url of current track
            return st & "|||" & t & "|||" & a & "|||" & al & "|||" & (d as string) & "|||" & (p as string) & "|||" & art
        end tell
        """
        guard let raw = runOSAScript(script), !raw.isEmpty else { return nil }
        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 7 else { return nil }

        let isPlaying = parts[0].lowercased().contains("playing")
        let duration = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
        let position = Double(parts[5].replacingOccurrences(of: ",", with: ".")) ?? 0

        return ProbedMedia(
            videoID: nil,
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            duration: duration,
            position: position,
            isPlaying: isPlaying,
            artworkURL: parts[6].isEmpty ? nil : parts[6],
            source: .spotify
        )
    }

    private static func queryAppleMusic() -> ProbedMedia? {
        let script = """
        tell application "Music"
            if player state is stopped then return ""
            set st to (player state as string)
            set t to name of current track
            set a to artist of current track
            set al to album of current track
            set d to duration of current track
            set p to player position
            return st & "|||" & t & "|||" & a & "|||" & al & "|||" & (d as string) & "|||" & (p as string)
        end tell
        """
        guard let raw = runOSAScript(script), !raw.isEmpty else { return nil }
        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }

        let isPlaying = parts[0].lowercased().contains("playing")
        let duration = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
        let position = Double(parts[5].replacingOccurrences(of: ",", with: ".")) ?? 0
        let query = "\(parts[2]) \(parts[1])".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        return ProbedMedia(
            videoID: nil,
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            duration: duration,
            position: position,
            isPlaying: isPlaying,
            artworkURL: query.isEmpty ? nil : "itunes://\(query)",
            source: .appleMusic
        )
    }

    private static func queryChromium(appName: String) -> ProbedMedia? {
        let script = """
        tell application "\(appName)"
            repeat with w in windows
                repeat with t in tabs of w
                    set u to URL of t
                    if u contains "music.youtube.com/watch" or u contains "youtube.com/watch" then
                        return (title of t) & "|||" & u
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
        guard let raw = runOSAScript(script), !raw.isEmpty else { return nil }
        return parseWebTab(raw: raw, browserName: appName, source: .chromium(appName: appName))
    }

    private static func querySafari() -> ProbedMedia? {
        let script = """
        tell application "Safari"
            repeat with w in windows
                repeat with t in tabs of w
                    set u to URL of t
                    if u contains "music.youtube.com/watch" or u contains "youtube.com/watch" then
                        return (name of t) & "|||" & u
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
        guard let raw = runOSAScript(script), !raw.isEmpty else { return nil }
        return parseWebTab(raw: raw, browserName: "Safari", source: .safari)
    }

    private static func parseWebTab(raw: String, browserName: String, source: SourceApp) -> ProbedMedia? {
        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 2 else { return nil }

        var rawTitle = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let url = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

        let suffixes = [" - YouTube Music", " - YouTube", " — YouTube"]
        for suffix in suffixes where rawTitle.hasSuffix(suffix) {
            rawTitle = String(rawTitle.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let range = rawTitle.range(of: #"^\(\d+\)\s*"#, options: .regularExpression) {
            rawTitle.removeSubrange(range)
        }

        let videoID = URLComponents(string: url)?.queryItems?.first(where: { $0.name == "v" })?.value
        let artworkURL = (videoID != nil && !videoID!.isEmpty) ? "https://i.ytimg.com/vi/\(videoID!)/hqdefault.jpg" : nil

        // KEY DISCOVERY: YouTube Music sets tab title to "YouTube Music" whenever paused,
        // and to the actual song title whenever playing!
        let isGenericTitle = rawTitle.isEmpty || rawTitle.lowercased() == "youtube music" || rawTitle.lowercased() == "youtube"
        let isPlaying = !isGenericTitle

        let title: String
        let artist: String
        if isGenericTitle {
            title = ""
            artist = "YouTube Music"
        } else if let dashRange = rawTitle.range(of: " - ") {
            artist = String(rawTitle[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            title = String(rawTitle[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            title = rawTitle
            artist = url.contains("music.youtube.com") ? "YouTube Music" : browserName
        }

        return ProbedMedia(
            videoID: videoID,
            title: title,
            artist: artist,
            album: browserName,
            duration: 0,
            position: 0,
            isPlaying: isPlaying,
            artworkURL: artworkURL,
            source: source
        )
    }
}
