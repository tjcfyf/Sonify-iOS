import Foundation
import MediaPlayer
import UIKit

/// 锁屏 / 控制中心 / 耳机线控的统一出口。
/// Android 对应 MediaSession；iOS 拆成两半：`MPNowPlayingInfoCenter`（写信息）+ `MPRemoteCommandCenter`（收指令）。
final class NowPlayingCenter {

    struct Handlers {
        var play: () -> Void = {}
        var pause: () -> Void = {}
        var toggle: () -> Void = {}
        var next: () -> Void = {}
        var previous: () -> Void = {}
        var seek: (TimeInterval) -> Void = { _ in }
        var rate: (Float) -> Void = { _ in }
    }

    private var handlers = Handlers()
    private var isActivated = false
    private var artworkCacheKey: String?
    private var artworkCache: UIImage?

    /// 封面解码开销不小，同一首歌只解一次。
    private func cachedArtwork(for key: String, data: Data) -> UIImage? {
        if artworkCacheKey == key, let cached = artworkCache { return cached }
        guard let image = UIImage(data: data) else { return nil }
        artworkCacheKey = key
        artworkCache = image
        return image
    }

    func activate(handlers: Handlers) {
        self.handlers = handlers
        guard !isActivated else { return }
        isActivated = true

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async { self.handlers.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async { self.handlers.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async { self.handlers.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async { self.handlers.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async { self.handlers.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            let position = positionEvent.positionTime
            DispatchQueue.main.async { self.handlers.seek(position) }
            return .success
        }

        center.changePlaybackRateCommand.isEnabled = true
        center.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 1.0, 1.25, 1.5, 2.0]
        center.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let self = self,
                  let rateEvent = event as? MPChangePlaybackRateCommandEvent
            else { return .commandFailed }
            let rate = rateEvent.playbackRate
            DispatchQueue.main.async { self.handlers.rate(rate) }
            return .success
        }
    }

    func update(
        track: Track?,
        elapsed: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        rate: Float
    ) {
        guard let track = track else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            artworkCacheKey = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration > 0 ? duration : track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
        ]

        if let data = track.artworkData, let image = cachedArtwork(for: track.id, data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        // 状态栏歌词的 iOS 降级方案：把"当前歌词行"塞进副标题（非越狱唯一可行途径，见方案 §3.5）。
        if NowPlayingCenter.lyricLineEnabled,
           let line = NowPlayingCenter.currentLyricLine, !line.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = line
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// 由歌词视图在每行变化时写入；为空则显示专辑名。
    static var currentLyricLine: String?

    /// 设置页「锁屏显示当前歌词行」的总开关。
    static var lyricLineEnabled = true
}
