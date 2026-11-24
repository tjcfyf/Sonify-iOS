import AVFoundation
import Combine
import MediaPlayer

/// 播放内核。对应 Android 的 `object MediaController`（全应用唯一状态源）。
///
/// 与 Android 的差异：
/// - Android 用 `MediaSessionService` 维持后台；iOS 靠 `AVAudioSession(.playback)` + `UIBackgroundModes: audio`。
/// - Android 用 `Media3 SimpleCache` 边下边播；这里 M0 只做本地文件，在线曲留到 M3（见方案 §3.2/§3.4）。
/// - 队列不交给 `AVQueuePlayer`：AVQueuePlayer 无法任意跳转/重排，自己维护索引更稳。
@MainActor
final class PlayerEngine: ObservableObject {

    static let shared = PlayerEngine()

    // MARK: - 对外状态

    @Published private(set) var queue: [Track] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var playbackRate: Float = 1.0
    @Published private(set) var errorMessage: String?
    @Published private(set) var sleepRemaining: TimeInterval?
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var isShuffled = false

    /// 锁屏是否把当前歌词行写进副标题（设置项）。
    var lockScreenLyricEnabled = true

    enum RepeatMode: String, CaseIterable, Codable {
        case off, one, all

        var next: RepeatMode {
            switch self {
            case .off: return .all
            case .all: return .one
            case .one: return .off
            }
        }

        var icon: String {
            switch self {
            case .off, .all: return "repeat"
            case .one: return "repeat.1"
            }
        }
    }

    var currentTrack: Track? {
        guard queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    // MARK: - 私有

    private let player = AVPlayer()
    private let nowPlaying = NowPlayingCenter()

    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?

    private var statusObservation: NSKeyValueObservation?
    private var sleepTimer: Timer?
    private var sleepDeadline: Date?

    private var desiredRate: Float = 1.0
    private var pendingSeek: Double?
    private var isSeekingByUser = false
    private var lastNowPlayingRefresh = Date.distantPast

    private let stateKey = "sonify.playback.state"

    // MARK: - 生命周期

    private var didBootstrap = false

    /// init 里只做最轻的初始化。音频会话、远程控制、时间观察者全部延后到首帧之后，
    /// 避免启动期触碰 AVAudioSession / MPRemoteCommandCenter 引发闪退。
    private init() {
        configurePlayer()
    }

    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        configureAudioSession()
        configureObservers()
        configureRemoteCommands()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // .playback 才能息屏/后台继续出声；mixWithOthers 关掉，避免被别的 App 抢。
        do {
            try session.setCategory(.playback, mode: .default, options: [])
        } catch {
            errorMessage = "音频会话初始化失败：\(error.localizedDescription)"
        }
    }

    private func configurePlayer() {
        player.actionAtItemEnd = .pause
        player.volume = 1.0
    }

    private func configureRemoteCommands() {
        nowPlaying.activate(
            handlers: NowPlayingCenter.Handlers(
                play: { [weak self] in self?.resume() },
                pause: { [weak self] in self?.pause() },
                toggle: { [weak self] in self?.togglePlayPause() },
                next: { [weak self] in self?.next() },
                previous: { [weak self] in self?.previous() },
                seek: { [weak self] position in self?.seek(to: position) },
                rate: { [weak self] rate in self?.setRate(rate) }
            )
        )
    }

    private func configureObservers() {
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self = self else { return }
                if !self.isSeekingByUser {
                    self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
                }
                self.refreshDurationIfNeeded()
                self.refreshNowPlayingIfNeeded()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            Task { @MainActor in
                guard let self = self, item === self.player.currentItem else { return }
                self.handlePlaybackEnded()
            }
        }

        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription ?? "播放失败"
            Task { @MainActor in
                self?.errorMessage = message
                self?.isPlaying = false
            }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }
            Task { @MainActor in
                guard let self = self else { return }
                switch type {
                case .began:
                    self.player.pause()
                    self.isPlaying = false
                case .ended:
                    let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    if AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                        self.resume()
                    }
                @unknown default:
                    break
                }
            }
        }

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
            else { return }
            Task { @MainActor in
                // 拔耳机暂停：与 Android 耳机拔出行为对齐。
                if reason == .oldDeviceUnavailable {
                    self?.pause()
                }
            }
        }
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        for observer in [endObserver, failureObserver, interruptionObserver, routeObserver] {
            if let observer = observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        sleepTimer?.invalidate()
    }

    // MARK: - 队列控制

    func play(track: Track) {
        if let existing = queue.firstIndex(where: { $0.id == track.id }) {
            play(at: existing)
            return
        }
        queue = [track]
        index = 0
        loadCurrentTrack(autoPlay: true)
    }

    func play(queue newQueue: [Track], startAt startIndex: Int) {
        guard !newQueue.isEmpty else { return }
        queue = newQueue
        index = min(max(0, startIndex), newQueue.count - 1)
        loadCurrentTrack(autoPlay: true)
    }

    func play(at position: Int) {
        guard queue.indices.contains(position) else { return }
        index = position
        loadCurrentTrack(autoPlay: true)
    }

    func next() {
        guard !queue.isEmpty else { return }
        let wasPlaying = isPlaying
        index = nextIndex(forward: true)
        loadCurrentTrack(autoPlay: wasPlaying)
    }

    private func nextIndex(forward: Bool) -> Int {
        guard queue.count > 1 else { return index }
        if isShuffled {
            // 随机模式：避开当前曲目，避免"随机到同一首"的观感。
            var candidate = index
            for _ in 0..<8 {
                candidate = Int.random(in: 0..<queue.count)
                if candidate != index { break }
            }
            return candidate
        }
        return forward ? (index + 1) % queue.count : (index - 1 + queue.count) % queue.count
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.next
    }

    func toggleShuffle() {
        isShuffled.toggle()
        refreshNowPlaying(force: true)
    }

    /// 队列拖拽排序后要跟着当前曲目走，否则 index 会指错。
    func moveQueue(fromOffsets source: IndexSet, toOffset destination: Int) {
        let currentID = currentTrack?.id
        queue.move(fromOffsets: source, toOffset: destination)
        if let currentID = currentID, let newIndex = queue.firstIndex(where: { $0.id == currentID }) {
            index = newIndex
        } else if !queue.isEmpty {
            index = min(index, queue.count - 1)
        }
        persistState()
    }

    func previous() {
        guard !queue.isEmpty else { return }
        // 与 Android 一致：播过 3 秒先回本曲开头，否则上一首。
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        let wasPlaying = isPlaying
        index = (index - 1 + queue.count) % queue.count
        loadCurrentTrack(autoPlay: wasPlaying)
    }

    func append(_ tracks: [Track]) {
        queue.append(contentsOf: tracks.filter { newTrack in
            !queue.contains(where: { $0.id == newTrack.id })
        })
    }

    func removeFromQueue(at position: Int) {
        guard queue.indices.contains(position) else { return }
        let removingCurrent = position == index
        queue.remove(at: position)
        if queue.isEmpty {
            stop()
            return
        }
        if position < index {
            index -= 1
        } else if removingCurrent {
            index = min(index, queue.count - 1)
            loadCurrentTrack(autoPlay: isPlaying)
        }
    }

    /// 曲库删除某首歌时同步清掉队列；删的是当前曲目就顺延。
    func handleTrackDeleted(_ trackID: String) {
        guard let position = queue.firstIndex(where: { $0.id == trackID }) else { return }
        removeFromQueue(at: position)
    }

    func removeFromQueue(at offsets: IndexSet) {
        // 倒序删除，避免前面的删除把后面的索引位移。
        for position in offsets.sorted(by: >) {
            removeFromQueue(at: position)
        }
    }

    // MARK: - 播放控制

    func resume() {
        bootstrapIfNeeded()
        guard currentTrack != nil else { return }
        if player.currentItem == nil {
            loadCurrentTrack(autoPlay: true)
            return
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            errorMessage = "无法激活音频会话：\(error.localizedDescription)"
        }
        player.play()
        // player.play() 会把 rate 拉回 1.0，必须重新贴一遍目标倍速。
        if desiredRate != 1.0 {
            player.rate = desiredRate
        }
        isPlaying = true
        persistState()
        refreshNowPlaying(force: true)
    }

    func pause() {
        player.pause()
        isPlaying = false
        persistState()
        refreshNowPlaying(force: true)
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        queue = []
        index = 0
        isPlaying = false
        currentTime = 0
        duration = 0
        NowPlayingCenter.currentLyricLine = nil
        nowPlaying.update(track: nil, elapsed: 0, duration: 0, isPlaying: false, rate: 1)
        clearPersistedState()
    }

    func seek(to time: Double) {
        guard player.currentItem != nil else { return }
        let clamped = max(0, min(time, duration > 0 ? duration : time))
        currentTime = clamped
        isSeekingByUser = false
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        persistState()
        refreshNowPlaying(force: true)
    }

    /// Slider 拖动期间只改 UI 时间，松手才真正 seek，避免每次拖动都发 seek 引发解码风暴。
    func beginScrubbing() {
        isSeekingByUser = true
    }

    func scrub(to time: Double) {
        currentTime = max(0, min(time, duration > 0 ? duration : time))
    }

    func endScrubbing() {
        isSeekingByUser = false
        seek(to: currentTime)
    }

    func setRate(_ rate: Float) {
        let clamped = min(max(rate, 0.5), 3.0)
        desiredRate = clamped
        playbackRate = clamped
        if isPlaying {
            player.rate = clamped
        }
        // 慢放用 timeDomain 保音调（Android ExoPlayer 的 Sonic 等价能力）。
        player.currentItem?.audioTimePitchAlgorithm = clamped < 1.0 ? .timeDomain : .spectral
        refreshNowPlaying(force: true)
        persistState()
    }

    // MARK: - 睡眠定时（对应 Android sleep timer）

    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        guard minutes > 0 else { return }
        sleepDeadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepRemaining = TimeInterval(minutes * 60)
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickSleepTimer() }
        }
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepDeadline = nil
        sleepRemaining = nil
        player.volume = 1
    }

    private func tickSleepTimer() {
        guard let deadline = sleepDeadline else { return }
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 {
            sleepRemaining = 0
            pause()
            cancelSleepTimer()
            return
        }
        sleepRemaining = remaining
        // 最后 20 秒线性淡出，避免"突然断声"。
        if remaining <= 20 {
            player.volume = Float(max(0.05, remaining / 20))
        }
    }

    // MARK: - 内部装载

    private func loadCurrentTrack(autoPlay: Bool) {
        guard let track = currentTrack else { return }
        guard let url = track.fileURL else {
            errorMessage = "在线曲需要在 M3 接入酷狗会话后才能播放（当前版本仅支持本地文件）"
            isPlaying = false
            return
        }

        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = desiredRate < 1.0 ? .timeDomain : .spectral
        player.replaceCurrentItem(with: item)
        player.volume = 1
        errorMessage = nil
        currentTime = 0
        duration = track.duration

        // KVO：等到 readyToPlay 再应用恢复进度，比固定延时可预期得多（M1 替换 M0 的 sleep 方案）。
        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] observed, _ in
            guard observed.status == .readyToPlay else { return }
            Task { @MainActor in
                guard let self = self, self.player.currentItem === observed else { return }
                let itemDuration = observed.duration.seconds
                if itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
                if let pending = self.pendingSeek {
                    self.pendingSeek = nil
                    self.seek(to: pending)
                    if !self.isPlaying {
                        self.player.pause()
                    }
                }
                self.persistState()
                self.refreshNowPlaying(force: true)
            }
        }

        if autoPlay {
            resume()
        } else {
            isPlaying = false
            refreshNowPlaying(force: true)
        }
        persistState()
    }

    private func handlePlaybackEnded() {
        switch repeatMode {
        case .one:
            seek(to: 0)
            resume()
        case .all:
            next()
        case .off:
            if index + 1 < queue.count {
                next()
            } else {
                isPlaying = false
                currentTime = duration
                refreshNowPlaying(force: true)
            }
        }
    }

    private func refreshDurationIfNeeded() {
        guard let itemDuration = player.currentItem?.duration.seconds,
              itemDuration.isFinite,
              itemDuration > 0
        else { return }
        if abs(itemDuration - duration) > 0.5 {
            duration = itemDuration
        }
    }

    // MARK: - 锁屏信息

    private func refreshNowPlayingIfNeeded() {
        guard Date().timeIntervalSince(lastNowPlayingRefresh) > 1.0 else { return }
        refreshNowPlaying(force: false)
    }

    private func refreshNowPlaying(force: Bool) {
        guard force || Date().timeIntervalSince(lastNowPlayingRefresh) > 1.0 else { return }
        lastNowPlayingRefresh = Date()
        if !lockScreenLyricEnabled {
            NowPlayingCenter.currentLyricLine = nil
        }
        nowPlaying.update(
            track: currentTrack,
            elapsed: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            rate: desiredRate
        )
    }

    /// 给设置页用：改完锁屏歌词开关后立刻重刷一次 Now Playing。
    func refreshLockScreenInfo() {
        refreshNowPlaying(force: true)
    }

    // MARK: - 状态持久化（对应 Android PlaybackRestoreGate）

    private struct PersistedState: Codable {
        var tracks: [Track]
        var index: Int
        var time: Double
        var rate: Float
    }

    func persistState() {
        // 队列为空时保留上一次快照：App 启动时先 setRate 再 restore，若这里清空会丢队列。
        guard !queue.isEmpty else { return }
        // 封面与歌词不进恢复快照，避免 UserDefaults 膨胀。
        let slim = queue.map { track -> Track in
            var copy = track
            copy.artworkData = nil
            copy.lyricText = nil
            return copy
        }
        let state = PersistedState(tracks: slim, index: index, time: currentTime, rate: desiredRate)
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: stateKey)
    }

    func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: stateKey)
    }

    /// 冷启动恢复。只恢复队列与进度，不自动播放（防止一开 App 就出声）。
    func restoreLastSession() {
        guard queue.isEmpty,
              let data = UserDefaults.standard.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data),
              !state.tracks.isEmpty
        else { return }

        queue = state.tracks
        index = min(max(0, state.index), state.tracks.count - 1)
        desiredRate = state.rate
        playbackRate = state.rate
        pendingSeek = state.time
        currentTime = state.time
        // 进度由 KVO readyToPlay 回调应用，这里不再 sleep。
        loadCurrentTrack(autoPlay: false)
    }
}

// MARK: - 进度条桥接

extension PlayerEngine {
    /// 播放进度 0…1，给 Slider 用。
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }
}
