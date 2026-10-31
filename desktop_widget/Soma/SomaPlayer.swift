// SomaPlayer — streams a SomaFM channel. The channel list comes from somafm.com's
// channels.json (kept for offline starts), the stream from the channel's MP3 playlist
// (.pls, trying each server in turn), and what's playing from its recent-songs feed,
// checked every 20 seconds while playing. Also shows up in Control Center and answers
// the keyboard's play/pause key.
//
// tilderadio, the tildeverse's community station with live DJs, sits above the SomaFM
// channels. It has a stream of its own rather than a playlist, and says what's playing,
// and who's on air, through its AzuraCast server's now-playing API.

import AVFoundation
import AppKit
import Combine
import MediaPlayer

struct Channel: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let genre: String?
    let image: URL?
    let largeimage: URL?
    let listeners: String?
    let playlists: [Playlist]
    /// For stations other than SomaFM: the stream itself, the station's site, its name, and
    /// an AzuraCast now-playing address.
    var stream: URL? = nil
    var site: URL? = nil
    var station: String? = nil
    var nowPlaying: URL? = nil

    struct Playlist: Decodable, Hashable {
        let url: URL
        let format: String
    }

    var streamPlaylist: URL? { (playlists.first { $0.format == "mp3" } ?? playlists.first)?.url }
    var page: URL { site ?? URL(string: "https://somafm.com/\(id)/")! }
    var network: String { station ?? "SomaFM" }

    enum CodingKeys: String, CodingKey { case id, title, description, genre, image, largeimage, listeners, playlists }

    static let tilderadio = Channel(
        id: "tilderadio", title: "tilderadio",
        description: "The tildeverse's community radio, with live DJs", genre: "community",
        image: URL(string: "https://tilderadio.org/logos/tilderadio.png"), largeimage: nil, listeners: nil, playlists: [],
        stream: URL(string: "https://tilderadio.org/listen/mp3/192k"), site: URL(string: "https://tilderadio.org"),
        station: "tilderadio", nowPlaying: URL(string: "https://azuracast.tilderadio.org/api/nowplaying/tilderadio"))
}

struct Song: Decodable, Equatable {
    let title: String?
    let artist: String?
    let album: String?
}

@MainActor
final class SomaPlayer: ObservableObject {
    static let shared = SomaPlayer()

    enum State: Equatable { case stopped, connecting, playing, failed(String) }

    /// Stations other than SomaFM, at the top of the menu.
    let stations = [Channel.tilderadio]
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var channel: Channel?
    @Published private(set) var song: Song?
    @Published private(set) var state = State.stopped
    @Published var isMuted = false { didSet { player.isMuted = isMuted } }
    /// From a station's now-playing API: the song's art, how many are listening, and the DJ on air.
    @Published private(set) var songArt: URL?
    @Published private(set) var listeners: String?
    @Published private(set) var liveHost: String?

    private let player = AVPlayer()
    private var streams: [URL] = []
    private var streamIndex = 0
    private var attempt = 0 // bumped on every play/stop/switch, so stale async work is dropped
    private var observers: Set<AnyCancellable> = []
    private var itemObservers: Set<AnyCancellable> = []
    private var songTimer: Timer?
    private var artwork: NSImage?

    private static let channelsURL = URL(string: "https://somafm.com/channels.json")!

    private init() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.timeControlChanged(status) }
            .store(in: &observers)
        setUpRemoteCommands()
        if let saved = UserDefaults.standard.string(forKey: "channel"), let station = stations.first(where: { $0.id == saved }) {
            channel = station
            channelChanged()
        }
        Task { await loadChannels() }
    }

    // MARK: - Channels

    private func loadChannels() async {
        if let cached = UserDefaults.standard.data(forKey: "channels") { show(channelsJSON: cached) }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.channelsURL)
            show(channelsJSON: data)
            UserDefaults.standard.set(data, forKey: "channels")
        } catch {
            if channels.isEmpty { state = .failed("Can't reach somafm.com") }
        }
    }

    private func show(channelsJSON data: Data) {
        struct List: Decodable { let channels: [Channel] }
        guard let list = try? JSONDecoder().decode(List.self, from: data) else { return }
        channels = list.channels.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let saved = UserDefaults.standard.string(forKey: "channel") ?? "groovesalad"
        if let channel, stations.contains(channel) { return }
        let current = channels.first { $0.id == (channel?.id ?? saved) } ?? channels.first
        if current?.id != channel?.id || channel == nil {
            channel = current
            channelChanged()
        } else {
            channel = current // fresh listener count
        }
    }

    func select(_ next: Channel) {
        guard next.id != channel?.id else { return }
        let wasOn = state == .playing || state == .connecting
        channel = next
        UserDefaults.standard.set(next.id, forKey: "channel")
        channelChanged()
        if wasOn { play() }
    }

    private func channelChanged() {
        song = nil
        artwork = nil
        songArt = nil
        listeners = nil
        liveHost = nil
        Task { await refreshSong() }
        guard let url = channel?.largeimage ?? channel?.image else { return }
        let id = channel?.id
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url), channel?.id == id else { return }
            artwork = NSImage(data: data)
            updateNowPlaying()
        }
    }

    // MARK: - Playing

    func toggle() {
        if state == .playing || state == .connecting { stop() } else { play() }
    }

    func play() {
        guard let channel, let playlist = channel.stream ?? channel.streamPlaylist else { return }
        attempt += 1
        let mine = attempt
        state = .connecting
        player.replaceCurrentItem(with: nil)
        if channel.stream != nil {
            streams = [playlist]
            streamIndex = 0
            startStream()
        } else { Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: playlist)
                guard mine == attempt else { return }
                streams = Self.parsePLS(data)
                streamIndex = 0
                guard !streams.isEmpty else { throw URLError(.badServerResponse) }
                startStream()
            } catch {
                if mine == attempt { fail("Can't load the stream") }
            }
        } }
        songTimer?.invalidate()
        songTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { await self?.refreshSong() }
        }
        updateNowPlaying()
    }

    func stop() {
        attempt += 1
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemObservers = []
        songTimer?.invalidate()
        state = .stopped
        updateNowPlaying()
    }

    private func fail(_ message: String) {
        stop()
        state = .failed(message)
    }

    private func startStream() {
        let item = AVPlayerItem(url: streams[streamIndex])
        let mine = attempt
        itemObservers = []
        // A server that won't play, or drops out, hands over to the next one in the playlist.
        item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                if status == .failed, self?.attempt == mine { self?.nextStream() }
            }
            .store(in: &itemObservers)
        NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                if self?.attempt == mine { self?.nextStream() }
            }
            .store(in: &itemObservers)
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func nextStream() {
        streamIndex += 1
        if streamIndex < streams.count {
            state = .connecting
            startStream()
        } else {
            fail("Stream unavailable")
        }
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus) {
        guard player.currentItem != nil else { return }
        switch status {
        case .playing: state = .playing
        case .waitingToPlayAtSpecifiedRate: state = .connecting
        default: break
        }
        updateNowPlaying()
    }

    /// File1=…, File2=… from a .pls playlist.
    static func parsePLS(_ data: Data) -> [URL] {
        String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .filter { $0.lowercased().hasPrefix("file") }
            .compactMap { $0.split(separator: "=", maxSplits: 1).last.flatMap { URL(string: String($0)) } }
    }

    // MARK: - Now playing

    func refreshSong() async {
        if let url = channel?.nowPlaying { return await refreshStation(url) }
        guard let id = channel?.id, let url = URL(string: "https://somafm.com/songs/\(id).json") else { return }
        struct Feed: Decodable { let songs: [Song] }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let feed = try? JSONDecoder().decode(Feed.self, from: data),
              channel?.id == id else { return }
        if song != feed.songs.first {
            song = feed.songs.first
            updateNowPlaying()
        }
    }

    /// What's on a station with an AzuraCast server: the song, its art, the listeners, and
    /// the DJ when someone is broadcasting live.
    private func refreshStation(_ url: URL) async {
        struct NowPlaying: Decodable {
            struct Playing: Decodable { let song: Track }
            struct Track: Decodable { let title: String?; let artist: String?; let album: String?; let art: URL? }
            struct Listeners: Decodable { let current: Int }
            struct Live: Decodable { let is_live: Bool; let streamer_name: String? }
            let now_playing: Playing
            let listeners: Listeners
            let live: Live?
        }
        let id = channel?.id
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let now = try? JSONDecoder().decode(NowPlaying.self, from: data), channel?.id == id else { return }
        let track = now.now_playing.song
        let next = Song(title: track.title.flatMap { $0.isEmpty ? nil : $0 }, artist: track.artist.flatMap { $0.isEmpty ? nil : $0 },
                        album: track.album)
        listeners = "\(now.listeners.current)"
        liveHost = now.live?.is_live == true ? now.live?.streamer_name.flatMap { $0.isEmpty ? nil : $0 } : nil
        if songArt != track.art {
            songArt = track.art
            if let art = track.art, let (image, _) = try? await URLSession.shared.data(from: art), channel?.id == id {
                artwork = NSImage(data: image)
            }
        }
        if song != next {
            song = next
            updateNowPlaying()
        }
    }

    private func setUpRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        func handle(_ command: MPRemoteCommand, _ action: @escaping @MainActor (SomaPlayer) -> Void) {
            command.addTarget { [weak self] _ in
                guard let self else { return .commandFailed }
                MainActor.assumeIsolated { action(self) }
                return .success
            }
        }
        handle(commands.togglePlayPauseCommand) { $0.toggle() }
        handle(commands.playCommand) { $0.play() }
        handle(commands.pauseCommand) { $0.stop() }
        handle(commands.stopCommand) { $0.stop() }
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let channel, state == .playing || state == .connecting else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song?.title ?? channel.title,
            MPMediaItemPropertyArtist: song?.artist ?? channel.network,
            MPMediaItemPropertyAlbumTitle: channel.network == channel.title ? channel.title : "\(channel.network) · \(channel.title)",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        center.nowPlayingInfo = info
        center.playbackState = state == .playing ? .playing : .paused
    }
}
