import Foundation
import BrowseCraftCore

// 中文注释：VideoPlayerViewModel 管理单集播放历史的初始保存、自动保存和退出保存。
@MainActor
final class VideoPlayerViewModel: ObservableObject {
    @Published private(set) var currentPlaybackTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval?
    @Published private(set) var isPrepared: Bool = false
    @Published private(set) var isLoadingEpisodeSwitch: Bool = false
    @Published private(set) var shouldPlayAd: Bool = false
    @Published var errorMessage: String?

    let source: Source
    @Published private(set) var reference: SourceVideoPlaybackReference
    let videoTitle: String
    let detailURL: URL?
    let coverURL: URL?

    private let saveVideoWatchHistoryUseCase: SaveVideoWatchHistoryUseCase
    private let loadVideoWatchHistoryUseCase: LoadVideoWatchHistoryUseCase
    private let accumulateAdPointsUseCase: AccumulateAdPointsUseCase?
    private let runtimeResolver: any SourceRuntimeResolving
    private let userID: String
    private let now: () -> Date
    private var autosaveTask: Task<Void, Never>?
    private var didSeekToRestoredTime: Bool = false
    private var lastSavedPlaybackTime: TimeInterval?
    private var lastVideoAdPointCheckAt: Date?
    private var accumulatedVideoAdPointInterval: TimeInterval = 0

    init(
        source: Source,
        reference: SourceVideoPlaybackReference,
        videoTitle: String,
        detailURL: URL?,
        coverURL: URL?,
        saveVideoWatchHistoryUseCase: SaveVideoWatchHistoryUseCase,
        loadVideoWatchHistoryUseCase: LoadVideoWatchHistoryUseCase,
        accumulateAdPointsUseCase: AccumulateAdPointsUseCase? = nil,
        runtimeResolver: any SourceRuntimeResolving,
        userID: String = AppUser.localDefaultID,
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.reference = reference
        self.videoTitle = videoTitle
        self.detailURL = detailURL
        self.coverURL = coverURL
        self.saveVideoWatchHistoryUseCase = saveVideoWatchHistoryUseCase
        self.loadVideoWatchHistoryUseCase = loadVideoWatchHistoryUseCase
        self.accumulateAdPointsUseCase = accumulateAdPointsUseCase
        self.runtimeResolver = runtimeResolver
        self.userID = userID
        self.now = now
    }

    deinit {
        self.autosaveTask?.cancel()
    }

    var displayTitle: String {
        guard let episodeTitle: String = self.reference.episodeTitle,
              episodeTitle.isEmpty == false,
              episodeTitle != self.videoTitle else {
            return self.videoTitle
        }

        return "\(self.videoTitle) - \(episodeTitle)"
    }

    var canOpenPreviousEpisode: Bool {
        return self.reference.previousEpisodeURL != nil && self.isLoadingEpisodeSwitch == false
    }

    var canOpenNextEpisode: Bool {
        return self.reference.nextEpisodeURL != nil && self.isLoadingEpisodeSwitch == false
    }

    var nativeMediaURL: URL? {
        guard self.reference.status == .playable else {
            return nil
        }

        switch self.reference.candidateMediaKind {
        case .m3u8, .mp4:
            return self.reference.candidateMediaURL
        case .iframePlayer, .unknown:
            return nil
        }
    }

    var playbackDestination: VideoPlaybackDestination {
        if let nativeMediaURL: URL = self.nativeMediaURL {
            return .native(nativeMediaURL)
        }

        switch self.reference.status {
        case .pageOnly:
            return .web(VideoWebPlayerRequest(reference: self.reference))
        case .playable:
            return .unavailable(
                title: "Unsupported Media",
                message: "This episode did not expose a direct mp4 or m3u8 URL.",
                systemImage: "play.slash"
            )
        case .restricted(let restriction):
            return .unavailable(
                title: "Playback Restricted",
                message: self.restrictionMessage(restriction),
                systemImage: "lock.fill"
            )
        case .failed(let failure):
            return .unavailable(
                title: "Playback Unavailable",
                message: self.failureMessage(failure),
                systemImage: "exclamationmark.triangle.fill"
            )
        }
    }

    var restoredPlaybackTime: TimeInterval {
        return self.currentPlaybackTime
    }

    func prepareForPlayback() {
        if self.isPrepared {
            return
        }

        self.isPrepared = true

        do {
            if let history: VideoWatchHistory = try self.loadVideoWatchHistoryUseCase.execute(
                userID: self.userID,
                sourceID: self.source.id,
                vodID: self.reference.vodID,
                sourceIndex: self.reference.sourceIndex,
                episodeIndex: self.reference.episodeIndex
            ) {
                self.currentPlaybackTime = history.lastPlaybackTime
                self.duration = history.duration
            }

            self.saveCurrentProgress(force: true)
            self.startAutosaveIfNeeded()
        } catch {
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    func recordPlaybackProgress(currentTime: TimeInterval, totalTime: TimeInterval) {
        guard currentTime.isFinite,
              totalTime.isFinite else {
            return
        }

        self.currentPlaybackTime = max(0, currentTime)
        if totalTime > 0 {
            self.duration = totalTime
        }
        self.startAutosaveIfNeeded()
    }

    func markReadyToPlay(seek: (TimeInterval) -> Void) {
        guard self.didSeekToRestoredTime == false,
              self.restoredPlaybackTime > 1 else {
            return
        }

        self.didSeekToRestoredTime = true
        seek(self.restoredPlaybackTime)
    }

    func saveOnDisappear() {
        self.autosaveTask?.cancel()
        self.autosaveTask = nil
        self.resetVideoAdPointTimer()
        self.saveCurrentProgress(force: true)
    }

    func markAdPlaybackHandled() {
        #if DEBUG
        print(
            "[BrowseCraftAdPlayback] video mark handled " +
            "sourceID=\(self.source.id) vodID=\(self.reference.vodID) " +
            "episodeKey=\(self.reference.episodeKey) previousShouldPlayAd=\(self.shouldPlayAd)"
        )
        #endif
        self.shouldPlayAd = false
    }

    func openPreviousEpisode() async {
        await self.openEpisode(playPageURL: self.reference.previousEpisodeURL)
    }

    func openNextEpisode() async {
        await self.openEpisode(playPageURL: self.reference.nextEpisodeURL)
    }

    private func openEpisode(playPageURL: URL?) async {
        guard let playPageURL: URL = playPageURL,
              self.isLoadingEpisodeSwitch == false else {
            return
        }

        self.saveCurrentProgress(force: true)
        self.isLoadingEpisodeSwitch = true
        defer {
            self.isLoadingEpisodeSwitch = false
        }

        do {
            let runtime: any SourceRuntime = try self.runtimeResolver.runtime(for: self.source)
            guard let playbackRuntime: any VideoPlaybackRuntimeCapability = runtime as? any VideoPlaybackRuntimeCapability else {
                throw SourceRuntimeError.unsupported(
                    .custom("Selected source does not expose video playback runtime.")
                )
            }

            let output: SourceVideoPlaybackOutput = try await playbackRuntime.loadPlayback(
                SourceVideoPlaybackInput(
                    playPageURL: playPageURL,
                    context: self.runtimeContext()
                )
            )

            self.autosaveTask?.cancel()
            self.autosaveTask = nil
            self.reference = output.reference
            self.currentPlaybackTime = 0
            self.duration = nil
            self.isPrepared = false
            self.didSeekToRestoredTime = false
            self.lastSavedPlaybackTime = nil
            self.resetVideoAdPointTimer()
            self.prepareForPlayback()
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: "video-episode-switch-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    private func runtimeContext() -> SourceRuntimeContext {
        return SourceRuntimeContext(
            sourceID: self.source.id,
            pageID: nil,
            tabID: nil,
            sectionID: nil,
            sectionRole: nil,
            ruleID: nil,
            requestOverride: nil,
            debugMode: false,
            operation: nil
        )
    }

    private func startAutosaveIfNeeded() {
        guard self.autosaveTask == nil else {
            return
        }

        self.lastVideoAdPointCheckAt = self.now()
        self.autosaveTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: Self.autosaveIntervalNanoseconds)
                self?.handleAutosaveTick()
            }
        }
    }

    private func handleAutosaveTick() {
        self.saveCurrentProgress(force: false)
        self.accumulateVideoAdPointsIfNeeded()
    }

    private func saveCurrentProgress(force: Bool) {
        if force == false,
           let lastSavedPlaybackTime: TimeInterval = self.lastSavedPlaybackTime,
           abs(lastSavedPlaybackTime - self.currentPlaybackTime) < 1 {
            return
        }

        do {
            try self.saveVideoWatchHistoryUseCase.execute(
                userID: self.userID,
                source: self.source,
                reference: self.reference,
                videoTitle: self.videoTitle,
                detailURL: self.detailURL,
                coverURL: self.coverURL,
                lastPlaybackTime: self.currentPlaybackTime,
                duration: self.duration,
                visitedAt: self.now()
            )
            self.lastSavedPlaybackTime = self.currentPlaybackTime
        } catch {
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    private func accumulateVideoAdPointsIfNeeded() {
        let currentDate: Date = self.now()
        guard let lastVideoAdPointCheckAt: Date = self.lastVideoAdPointCheckAt else {
            self.lastVideoAdPointCheckAt = currentDate
            return
        }

        let elapsed: TimeInterval = currentDate.timeIntervalSince(lastVideoAdPointCheckAt)
        guard elapsed > 0 else {
            return
        }

        self.lastVideoAdPointCheckAt = currentDate
        self.accumulatedVideoAdPointInterval += elapsed
        #if DEBUG
        print(
            "[BrowseCraftAdPoints] video timer tick " +
            "sourceID=\(self.source.id) vodID=\(self.reference.vodID) " +
            "episodeKey=\(self.reference.episodeKey) elapsed=\(elapsed) " +
            "accumulatedInterval=\(self.accumulatedVideoAdPointInterval) " +
            "requiredInterval=\(Self.videoAdPointInterval)"
        )
        #endif
        guard self.accumulatedVideoAdPointInterval >= Self.videoAdPointInterval else {
            return
        }

        self.accumulatedVideoAdPointInterval -= Self.videoAdPointInterval
        self.accumulateAdPoints(points: AdPointRule.videoPoints)
    }

    private func resetVideoAdPointTimer() {
        self.lastVideoAdPointCheckAt = nil
        self.accumulatedVideoAdPointInterval = 0
    }

    private func accumulateAdPoints(points: Int) {
        guard let accumulateAdPointsUseCase: AccumulateAdPointsUseCase = self.accumulateAdPointsUseCase else {
            return
        }

        do {
            let result: AdPointAccumulationResult = try accumulateAdPointsUseCase.execute(
                userID: self.userID,
                points: points
            )
            #if DEBUG
            print(
                "[BrowseCraftAdPoints] video result " +
                "sourceID=\(self.source.id) vodID=\(self.reference.vodID) " +
                "episodeKey=\(self.reference.episodeKey) \(result.debugDescription)"
            )
            #endif
            if result.shouldPlayAd {
                #if DEBUG
                print(
                    "[BrowseCraftAdPlayback] video shouldPlayAd=true " +
                    "sourceID=\(self.source.id) vodID=\(self.reference.vodID) " +
                    "episodeKey=\(self.reference.episodeKey)"
                )
                #endif
                self.shouldPlayAd = true
            }
        } catch {
            #if DEBUG
            print(
                "[BrowseCraftAdPoints] video accumulate failed " +
                "sourceID=\(self.source.id) " +
                "vodID=\(self.reference.vodID) " +
                "episodeKey=\(self.reference.episodeKey) " +
                "error=\(error)"
            )
            #endif
        }
    }

    private func restrictionMessage(_ restriction: SourceVideoPlaybackRestriction) -> String {
        switch restriction {
        case .requiresLogin:
            return "This episode requires account login."
        case .vipOnly:
            return "This episode is limited to VIP or paid users."
        case .drm:
            return "This episode appears to use DRM-protected playback."
        case .regionBlocked:
            return "This episode appears to be region blocked."
        case .captchaOrAntiBot:
            return "This episode appears to be blocked by captcha or anti-bot protection."
        }
    }

    private func failureMessage(_ failure: SourceVideoPlaybackFailure) -> String {
        switch failure {
        case .mediaURLNotFound:
            return "The playback page did not expose a playable media URL."
        case .unsupportedMediaKind:
            return "The playback page exposed a media type BrowseCraft cannot play yet."
        case .parsingFailed:
            return "BrowseCraft could not parse this playback page."
        case .iframePlayerDepthExceeded:
            return "The iframe player exceeded the supported resolution depth."
        case .iframePlayerLoopDetected:
            return "The iframe player redirected in a loop."
        }
    }

    private static let autosaveIntervalNanoseconds: UInt64 = 30_000_000_000
    private static let videoAdPointInterval: TimeInterval = 600
}

enum VideoPlaybackDestination: Equatable {
    case native(URL)
    case web(VideoWebPlayerRequest)
    case unavailable(title: String, message: String, systemImage: String)
}
