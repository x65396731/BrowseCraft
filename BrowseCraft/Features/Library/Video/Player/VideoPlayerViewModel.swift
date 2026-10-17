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
    /// 中文注释：从历史打开时为 true——先按播放页规则重新解析，拿到当前有效的媒体地址再播；
    /// 存下的直链只在解析失败时作为最后备选。
    private let resolvesPlaybackOnPrepare: Bool
    private var didAttemptPlaybackRecovery: Bool = false
    private let now: () -> Date
    /// 中文注释：任务句柄不是界面状态，且 deinit 需要直接触碰存储属性——排除观察。
    @ObservationIgnored
    private var autosaveTask: Task<Void, Never>?
    /// 中文注释：原生播放器把暂停 / 继续挂在这里（30.8）：广告盖上前暂停，广告结束后继续。web 播放页没有这个能力。
    let playbackControl: VideoPlaybackControlProxy = VideoPlaybackControlProxy()
    private var didSeekToRestoredTime: Bool = false
    private var lastSavedPlaybackTime: TimeInterval?
    private var credentialRevision: Int = 0
    /// 中文注释：异步保存可能乱序返回；只有最新一轮保存可以更新 ViewModel 的已保存位置。
    private var progressSaveRevision: UInt64 = 0
    /// 中文注释：视频积分只计实际播放（30.8）：按播放器上报的进度差累计，暂停、错误页、后台挂起都不动；
    /// 进度跳变（拖动、换集）超过 `maxProgressStepForAdPoints` 的那一段不计。
    private var lastProgressTimeForAdPoints: TimeInterval?
    private var playedIntervalForAdPoints: TimeInterval = 0

    // MARK: 埋点会话
    /// 中文注释：`playback_started` 的入口。工厂按历史建的实例默认算历史页；库页瓷砖、详情「继续观看」建好后改写。
    var playbackEntry: PlaybackEntry
    /// 中文注释：每次打开播放器只报一次开始与一次关闭；开始之后才有关闭。
    private var startedPlayerType: PlayerType?
    private var startedAt: Date?
    private var didReportClose: Bool = false
    private var didReportUnavailable: Bool = false
    /// 中文注释：直链播放器按进度差累计的实际播放时长（与广告积分同一种累计法），`playback_closed` 用。
    private var lastProgressTimeForPlayedDuration: TimeInterval?
    private var playedDuration: TimeInterval = 0

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
        resolvesPlaybackOnPrepare: Bool = false,
        playbackEntry: PlaybackEntry = .history,
        userID: String = AppUser.localDefaultID,
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.playbackEntry = playbackEntry
        self.reference = reference
        self.resolvesPlaybackOnPrepare = resolvesPlaybackOnPrepare
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
                title: NSLocalizedString("Unsupported Media", comment: ""),
                message: NSLocalizedString("This episode did not expose a direct mp4 or m3u8 URL.", comment: ""),
                systemImage: "play.slash"
            )
        case .restricted(let restriction):
            return .unavailable(
                title: NSLocalizedString("Playback Restricted", comment: ""),
                message: self.restrictionMessage(restriction),
                systemImage: "lock.fill"
            )
        case .failed(let failure):
            return .unavailable(
                title: NSLocalizedString("Playback Unavailable", comment: ""),
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

        if self.resolvesPlaybackOnPrepare {
            _ = await self.resolvePlaybackFromRule(failureEvent: "video-history-playback-resolve-error")
        }

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
        self.accumulatePlayedInterval(progressTime: self.currentPlaybackTime)
        self.accumulatePlayedDuration(progressTime: self.currentPlaybackTime)
    }

    func markReadyToPlay(seek: (TimeInterval) -> Void) {
        self.reportPlaybackStartedIfNeeded(playerType: .native)
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
        self.resetPlayedIntervalForAdPoints()
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

    /// 中文注释：广告播过（看完 / 提前关闭）才清零积分；没播出来积分保留、下个计分点再试（30.8）。
    func markAdPlaybackHandled(outcome: RewardedAdPlaybackOutcome) {
        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftAdPlayback] video mark handled " +
            "sourceID=\(self.source.id) vodID=\(self.reference.vodID) " +
            "episodeKey=\(self.reference.episodeKey) previousShouldPlayAd=\(self.shouldPlayAd) " +
            "consumesAdPoints=\(outcome.consumesAdPoints)"
        )
        #endif
        self.shouldPlayAd = false
        self.playbackControl.play()
        guard outcome.consumesAdPoints else {
            return
        }
        Task { [persistenceCoordinator] in
            do {
                try await persistenceCoordinator.consumeAdPoints()
            } catch {
                AppLog.error(
                    .sync,
                    event: "video-ad-points-consume-failed",
                    metadata: ["error": AppLog.safeErrorCode(error)]
                )
            }
        }
    }

    /// 中文注释：直链播放失败（DNS、404、被拒）时按播放页规则重新解析一次；只重试一次，仍失败才报错。
    /// 历史里存的直链会过期换线路，站点上的这一集往往还在。
    @MainActor
    func handleNativePlaybackFailure(_ error: Error) async {
        RuleExecutionErrorClassifier.log(error: error, stage: .playback, event: "video-native-playback-failed")
        self.reportPlaybackFailed(playerType: .native, failure: .nativeFailed)
        guard self.didAttemptPlaybackRecovery == false, self.isLoadingEpisodeSwitch == false else {
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            return
        }
        self.didAttemptPlaybackRecovery = true
        let previousMediaURL: URL? = self.reference.candidateMediaURL
        let resolved: Bool = await self.resolvePlaybackFromRule(failureEvent: "video-playback-recovery-error")
        if resolved == false || self.reference.candidateMediaURL == previousMediaURL {
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
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

    /// 用播放页 URL 走一次规则链，成功则替换当前引用；失败只记日志、保留原引用，返回 false。
    private func resolvePlaybackFromRule(failureEvent: String) async -> Bool {
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
            let input: SourceVideoPlaybackInput = SourceVideoPlaybackInput(
                playPageURL: self.reference.playPageURL,
                context: self.runtimeContext(),
                handoff: self.reference.handoff
            )
            // 中文注释：`BCA-RUNTIME-010`——匹配不到内容时换手机 UA 重做一次。
            let output: SourceVideoPlaybackOutput = try await SourceUserAgentFallback.shared.perform(source: self.source) {
                try await playbackRuntime.loadPlayback(input)
            }
            self.reference = output.reference
            return true
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .playback, event: failureEvent)
            return false
        }
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

            let input: SourceVideoPlaybackInput = SourceVideoPlaybackInput(
                playPageURL: playPageURL,
                context: self.runtimeContext(),
                handoff: handoff
            )
            // 中文注释：`BCA-RUNTIME-010`——匹配不到内容时换手机 UA 重做一次。
            let output: SourceVideoPlaybackOutput = try await SourceUserAgentFallback.shared.perform(source: self.source) {
                try await playbackRuntime.loadPlayback(input)
            }

            self.autosaveTask?.cancel()
            self.autosaveTask = nil
            self.reference = output.reference
            self.didReportUnavailable = false
            self.currentPlaybackTime = 0
            self.duration = nil
            self.isPrepared = false
            self.didSeekToRestoredTime = false
            self.lastSavedPlaybackTime = nil
            self.resetPlayedIntervalForAdPoints()
            await self.prepareForPlayback()
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .playback, event: failureEvent)
            RuleFailureDiagnostics.report(
                error: error,
                kind: RuleExecutionErrorClassifier.diagnosticFailureKind(for: error),
                stage: .videoPlayback,
                point: .videoPlayback,
                source: self.source
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

        self.autosaveTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: Self.autosaveIntervalNanoseconds)
                self?.handleAutosaveTick()
            }
        }
    }

    private func handleAutosaveTick() {
        self.saveCurrentProgress(force: false)
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

    /// 中文注释：按播放器上报的进度差累计实际播放时长；差值为负或超过一步上限视为拖动 / 换集，只重置基准不计。
    private func accumulatePlayedInterval(progressTime: TimeInterval) {
        defer {
            self.lastProgressTimeForAdPoints = progressTime
        }
        guard let lastProgressTime: TimeInterval = self.lastProgressTimeForAdPoints else {
            return
        }

        let step: TimeInterval = progressTime - lastProgressTime
        guard step > 0, step <= AdPointRule.maxPlaybackProgressStep else {
            return
        }

        self.playedIntervalForAdPoints += step
        guard self.playedIntervalForAdPoints >= AdPointRule.videoPlaybackInterval else {
            return
        }

        self.playedIntervalForAdPoints -= AdPointRule.videoPlaybackInterval
        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftAdPoints] video played interval reached " +
            "sourceID=\(self.source.id) vodID=\(self.reference.vodID) " +
            "episodeKey=\(self.reference.episodeKey) requiredInterval=\(AdPointRule.videoPlaybackInterval)"
        )
        #endif
        self.accumulateAdPoints(points: AdPointRule.videoPoints)
    }

    // MARK: - 埋点

    /// 中文注释：直链在 `markReadyToPlay`、网页播放器在首个页面加载完成时调用；每次打开播放器只报第一次。
    func reportPlaybackStartedIfNeeded(playerType: PlayerType) {
        guard self.startedPlayerType == nil else {
            return
        }
        self.startedPlayerType = playerType
        self.startedAt = self.now()
        AppAnalytics.shared.logPlaybackStarted(source: self.source, kind: .video, playerType: playerType, entry: self.playbackEntry)
    }

    func reportPlaybackFailed(playerType: PlayerType, failure: PlaybackFailureCode) {
        AppAnalytics.shared.logPlaybackFailed(source: self.source, kind: .video, playerType: playerType, failure: failure)
    }

    /// 中文注释：`.unavailable` 目的地（受限、解析失败、无直链）没有播放器可言，归到直链类型上报。
    /// 从历史打开时会先按规则重新解析，解析完（`isPrepared` 且不在换集）仍不可播才报；同一份引用只报一次。
    func reportPlaybackUnavailableIfNeeded() {
        guard self.didReportUnavailable == false,
              self.isPrepared,
              self.isLoadingEpisodeSwitch == false,
              case .unavailable = self.playbackDestination else {
            return
        }
        self.didReportUnavailable = true
        self.reportPlaybackFailed(playerType: .native, failure: .unavailable)
    }

    func reportPlaybackCompleted() {
        AppAnalytics.shared.logPlaybackCompleted(kind: .video, playerType: .native)
    }

    /// 中文注释：离开播放器时报一次 `playback_closed`。直链用实际播放时长；网页播放器拿不到进度，用开始到关闭的时长。
    /// 登录页或激励广告盖住播放器时视图也会消失，那不算关闭。
    func reportPlaybackClosedIfNeeded() {
        guard self.didReportClose == false,
              self.requestedSourceLogin == nil,
              self.shouldPlayAd == false,
              let playerType: PlayerType = self.startedPlayerType,
              let startedAt: Date = self.startedAt else {
            return
        }
        self.didReportClose = true
        let duration: TimeInterval = playerType == .native
            ? self.playedDuration
            : self.now().timeIntervalSince(startedAt)
        AppAnalytics.shared.logPlaybackClosed(kind: .video, playerType: playerType, duration: duration)
    }

    private func accumulatePlayedDuration(progressTime: TimeInterval) {
        defer {
            self.lastProgressTimeForPlayedDuration = progressTime
        }
        guard let lastProgressTime: TimeInterval = self.lastProgressTimeForPlayedDuration else {
            return
        }
        let step: TimeInterval = progressTime - lastProgressTime
        guard step > 0, step <= AdPointRule.maxPlaybackProgressStep else {
            return
        }
        self.playedDuration += step
    }

    private func resetPlayedIntervalForAdPoints() {
        self.lastProgressTimeForAdPoints = nil
        self.playedIntervalForAdPoints = 0
    }

    private func accumulateAdPoints(points: Int) {
        Task { [persistenceCoordinator] in
            do {
                let result: AdPointAccumulationResult = try await persistenceCoordinator
                    .accumulateAdPoints(points)
                if result.shouldPlayAd {
                    AppAnalytics.shared.logAdPointsThreshold(trigger: .video)
                    // 中文注释：积分只在播放中累计，所以触发时一定在播；广告结束后 `markAdPlaybackHandled` 恢复播放。
                    self.playbackControl.pause()
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
        case .mediaSourceRejected:
            // 中文注释：`BC-EVIDENCE-082`——片源拒绝了这个地址，整页兜底也会卡住；提示用户换一个片源。
            return NSLocalizedString("video_playback_media_source_rejected", comment: "")
        }
    }

    private static let autosaveIntervalNanoseconds: UInt64 = 30_000_000_000
}

enum VideoPlaybackDestination: Equatable {
    case native(URL)
    case web(VideoWebPlayerRequest)
    case unavailable(title: String, message: String, systemImage: String)
}
