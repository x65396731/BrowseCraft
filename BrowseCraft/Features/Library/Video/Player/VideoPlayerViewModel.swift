import Observation
import Foundation
@preconcurrency import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftRuntime

// 中文注释：VideoPlayerViewModel 管理单集播放历史的初始保存、自动保存和退出保存。
@MainActor
@Observable
final class VideoPlayerViewModel {
    private(set) var currentPlaybackTime: TimeInterval = 0
    private(set) var duration: TimeInterval?
    private(set) var isPrepared: Bool = false
    private(set) var isLoadingEpisodeSwitch: Bool = false
    private(set) var shouldPlayAd: Bool = false
    private(set) var requestedSourceLogin: LibrarySourceLoginState?
    var errorMessage: String?

    let source: Source
    private(set) var reference: SourceVideoPlaybackReference
    let videoTitle: String
    let detailURL: URL?
    let coverURL: URL?

    private let persistenceCoordinator: ReadingActivityPersistenceCoordinator
    private let runtimeResolver: any SourceRuntimeResolving
    private let playbackRequestResolver: VideoPlaybackRequestResolver
    private let sourceCredentialStore: (any SourceCredentialStoring)?
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let fallbackUserID: String
    private let now: () -> Date
    /// 中文注释：任务句柄不是界面状态，且 deinit 需要直接触碰存储属性——排除观察。
    @ObservationIgnored
    private var autosaveTask: Task<Void, Never>?
    private var didSeekToRestoredTime: Bool = false
    private var lastSavedPlaybackTime: TimeInterval?
    private var credentialRevision: Int = 0
    /// 中文注释：异步保存可能乱序返回；只有最新一轮保存可以更新 ViewModel 的已保存位置。
    private var progressSaveRevision: UInt64 = 0
    private var lastVideoAdPointCheckAt: Date?
    private var accumulatedVideoAdPointInterval: TimeInterval = 0

    init(
        source: Source,
        reference: SourceVideoPlaybackReference,
        videoTitle: String,
        detailURL: URL?,
        coverURL: URL?,
        persistenceCoordinator: ReadingActivityPersistenceCoordinator,
        runtimeResolver: any SourceRuntimeResolving,
        credentialProvider: any SourceCredentialProviding = EmptySourceCredentialProvider(),
        systemCookieHeaderProvider: any SystemCookieHeaderProviding = EmptySystemCookieHeaderProvider(),
        activeAppUser: (any ActiveAppUserProviding)? = nil,
        userID: String = AppUser.localDefaultID,
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.reference = reference
        self.videoTitle = videoTitle
        self.detailURL = detailURL
        self.coverURL = coverURL
        self.persistenceCoordinator = persistenceCoordinator
        self.runtimeResolver = runtimeResolver
        self.playbackRequestResolver = VideoPlaybackRequestResolver(
            credentialProvider: credentialProvider,
            systemCookieHeaderProvider: systemCookieHeaderProvider
        )
        self.sourceCredentialStore = credentialProvider as? any SourceCredentialStoring
        self.activeAppUser = activeAppUser
        self.fallbackUserID = userID
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

    var resolvedPlaybackRequestConfig: SourcePlaybackRequestConfig? {
        let resourceURL: URL = self.reference.candidateMediaURL ?? self.reference.playPageURL
        return self.playbackRequestResolver.resolve(
            self.reference.playbackRequestConfig,
            source: self.source,
            resourceURL: resourceURL
        )
    }

    var playbackDestination: VideoPlaybackDestination {
        if let nativeMediaURL: URL = self.nativeMediaURL {
            return .native(nativeMediaURL)
        }

        switch self.reference.status {
        case .pageOnly:
            return .web(
                VideoWebPlayerRequest(
                    reference: self.reference,
                    requestConfig: self.resolvedPlaybackRequestConfig
                )
            )
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

    var restrictedLoginState: LibrarySourceLoginState? {
        _ = self.credentialRevision
        guard case .restricted(.requiresLogin) = self.reference.status,
              let sourceCredentialStore: any SourceCredentialStoring = self.sourceCredentialStore else {
            return nil
        }

        return LibrarySourceLoginStateResolver(
            credentialStore: sourceCredentialStore
        ).resolve(source: self.source)
    }

    var restoredPlaybackTime: TimeInterval {
        return self.currentPlaybackTime
    }

    func prepareForPlayback() async {
        CrashDiagnostics.shared.setRuleStage(.videoPlayback)
        if self.isPrepared {
            return
        }

        self.isPrepared = true

        do {
            if let history: VideoWatchHistory = try await self.persistenceCoordinator.loadVideoHistory(
                userID: self.currentUserID,
                sourceID: self.source.id,
                vodID: self.reference.vodID,
                sourceIndex: self.reference.sourceIndex,
                episodeIndex: self.reference.episodeIndex
            )?.value {
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

    func requestSourceLogin() {
        self.requestedSourceLogin = self.restrictedLoginState
    }

    func dismissRequestedSourceLogin() {
        self.requestedSourceLogin = nil
    }

    func completeRequestedSourceLogin(credential: SourceCredential) async {
        guard credential.sourceID == self.requestedSourceLogin?.sourceID,
              let sourceCredentialStore: any SourceCredentialStoring = self.sourceCredentialStore else {
            return
        }

        sourceCredentialStore.save(credential)
        self.credentialRevision += 1
        self.requestedSourceLogin = nil
        await self.reloadPlaybackAfterLogin()
    }

    func markAdPlaybackHandled() {
        #if DEBUG
        AppDebugLog.write(
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
        CrashDiagnostics.shared.setRuleStage(.videoPlayback)
        guard let playPageURL: URL = playPageURL,
              self.isLoadingEpisodeSwitch == false else {
            return
        }

        self.saveCurrentProgress(force: true)
        await self.loadPlayback(
            playPageURL: playPageURL,
            handoff: self.reference.handoff?.selecting(playPageURL: playPageURL),
            failureEvent: "video-episode-switch-error"
        )
    }

    private func reloadPlaybackAfterLogin() async {
        guard self.isLoadingEpisodeSwitch == false else {
            return
        }

        await self.loadPlayback(
            playPageURL: self.reference.playPageURL,
            handoff: self.reference.handoff,
            failureEvent: "video-login-playback-refresh-error"
        )
    }

    private func loadPlayback(
        playPageURL: URL,
        handoff: SourceVideoPlaybackHandoff?,
        failureEvent: String
    ) async {
        self.isLoadingEpisodeSwitch = true
        defer {
            self.isLoadingEpisodeSwitch = false
        }

        do {
            let runtime: any SourceRuntime = try self.runtimeResolver.runtime(for: self.source)
            guard let playbackRuntime: any SourceVideoPlaybackRuntime = runtime as? any SourceVideoPlaybackRuntime else {
                throw SourceRuntimeError.unsupported(
                    .custom("Selected source does not expose video playback runtime.")
                )
            }

            let output: SourceVideoPlaybackOutput = try await playbackRuntime.loadPlayback(
                SourceVideoPlaybackInput(
                    playPageURL: playPageURL,
                    context: self.runtimeContext(),
                    handoff: handoff
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
            await self.prepareForPlayback()
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .playback, event: failureEvent)
            AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .videoPlayback, errorCode: failureEvent)
            CrashDiagnostics.shared.record(
                error: error,
                category: .playback,
                errorCode: failureEvent,
                event: failureEvent
            )
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
            operation: .playback
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

        let playbackTime: TimeInterval = self.currentPlaybackTime
        let history: VideoWatchHistoryTransfer = VideoWatchHistoryTransfer(
            value: self.currentHistory(visitedAt: self.now())
        )
        self.progressSaveRevision &+= 1
        let saveRevision: UInt64 = self.progressSaveRevision
        Task { [persistenceCoordinator] in
            do {
                try await persistenceCoordinator.saveVideoHistory(history)
                guard self.progressSaveRevision == saveRevision else {
                    return
                }
                self.lastSavedPlaybackTime = playbackTime
            } catch {
                guard self.progressSaveRevision == saveRevision else {
                    return
                }
                self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            }
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
        AppDebugLog.write(
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
        Task { [persistenceCoordinator] in
            do {
                let result: AdPointAccumulationResult = try await persistenceCoordinator
                    .accumulateAdPoints(points)
                if result.shouldPlayAd {
                    self.shouldPlayAd = true
                }
            } catch {
                AppLog.error(
                    .sync,
                    event: "video-ad-points-save-failed",
                    metadata: ["error": AppLog.safeErrorCode(error)]
                )
            }
        }
    }

    private func currentHistory(visitedAt: Date) -> VideoWatchHistory {
        return VideoWatchHistory(
            userID: self.currentUserID,
            sourceID: self.source.id,
            vodID: self.reference.vodID,
            videoTitle: self.videoTitle,
            episodeTitle: self.reference.episodeTitle,
            episodeKey: self.reference.episodeKey,
            sourceIndex: self.reference.sourceIndex,
            episodeIndex: self.reference.episodeIndex,
            detailURL: self.detailURL,
            playPageURL: self.reference.playPageURL,
            candidateMediaURL: self.reference.candidateMediaURL,
            candidateMediaKind: self.reference.candidateMediaKind,
            playbackStatus: self.reference.status,
            playbackRequestConfig: self.reference.playbackRequestConfig,
            coverURL: self.coverURL,
            sourceName: self.reference.sourceName ?? self.source.name,
            lastPlaybackTime: self.currentPlaybackTime,
            duration: self.duration,
            visitedAt: visitedAt,
            updatedAt: visitedAt,
            previousEpisodeURL: self.reference.previousEpisodeURL,
            nextEpisodeURL: self.reference.nextEpisodeURL,
            sourceSnapshot: SourceSnapshot(source: self.source)
        )
    }

    private var currentUserID: String {
        return self.activeAppUser?.currentUserID.uuidString ?? self.fallbackUserID
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
