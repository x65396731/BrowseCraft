import BrowseCraftDomain
import Foundation

// 中文注释：设计文档 D（库、搜索与站点登录）、E（阅读与播放）、F（收藏、历史与内容锁定）三组事件的上报方法。

extension AppAnalytics {
    // MARK: - D. 库、搜索与站点登录

    func logLibraryCategorySelected(source: Source?) {
        self.log(.libraryCategorySelected, parameters: Self.sourceParameters(source))
    }

    func logSearchSubmitted(source: Source?, result: SearchResult, resultCount: Int) {
        var parameters: [String: Any] = Self.sourceParameters(source)
        parameters[Parameter.result] = result.rawValue
        parameters[Parameter.resultCountBucket] = Self.countBucket(resultCount)
        self.log(.searchSubmitted, parameters: parameters)
    }

    func logContentOpened(source: Source?, kind: AnalyticsContentKind? = nil, entry: ContentOpenEntry) {
        var parameters: [String: Any] = Self.sourceParameters(source, kind: kind)
        parameters[Parameter.entry] = entry.rawValue
        self.log(.contentOpened, parameters: parameters)
    }

    func logSourceLoginResult(source: Source?, entry: SourceLoginEntry, result: AnalyticsResult) {
        var parameters: [String: Any] = Self.sourceParameters(source)
        parameters[Parameter.entry] = entry.rawValue
        parameters[Parameter.result] = result.rawValue
        self.log(.sourceLoginResult, parameters: parameters)
    }

    func logSourceLogout(source: Source?) {
        self.log(.sourceLogout, parameters: Self.sourceParameters(source))
    }

    /// 中文注释：单条收藏 / 取消收藏。批量取消用 `logFavoritesRemoved(count:)`。
    func logFavoriteChanged(isFavorite: Bool, source: Source?, kind: AnalyticsContentKind? = nil, entry: FavoriteEntry) {
        var parameters: [String: Any] = Self.sourceParameters(source, kind: kind)
        parameters[Parameter.entry] = entry.rawValue
        if isFavorite == false {
            parameters[Parameter.itemCountBucket] = Self.countBucket(1)
        }
        self.log(isFavorite ? .favoriteAdded : .favoriteRemoved, parameters: parameters)
    }

    /// 中文注释：收藏页批量取消收藏，只报一次；跨来源，所以不带来源哈希。
    func logFavoritesRemoved(count: Int, kind: AnalyticsContentKind) {
        self.log(.favoriteRemoved, parameters: [
            Parameter.contentKind: kind.rawValue,
            Parameter.entry: FavoriteEntry.favoritesBatch.rawValue,
            Parameter.itemCountBucket: Self.countBucket(count)
        ])
    }

    // MARK: - E. 阅读与播放

    func logReaderOpened(source: Source?, kind: AnalyticsContentKind? = nil, entry: ReaderOpenEntry) {
        var parameters: [String: Any] = Self.sourceParameters(source, kind: kind)
        parameters[Parameter.entry] = entry.rawValue
        self.log(.readerOpened, parameters: parameters)
    }

    func logChapterOpened(source: Source?, kind: AnalyticsContentKind? = nil, navigation: ChapterNavigation) {
        var parameters: [String: Any] = Self.sourceParameters(source, kind: kind)
        parameters[Parameter.navigation] = navigation.rawValue
        self.log(.chapterOpened, parameters: parameters)
    }

    func logReaderClosed(kind: AnalyticsContentKind, duration: TimeInterval, chapterCount: Int) {
        self.log(.readerClosed, parameters: [
            Parameter.contentKind: kind.rawValue,
            Parameter.durationBucket: Self.durationBucket(duration),
            Parameter.itemCountBucket: Self.countBucket(chapterCount)
        ])
    }

    func logReaderBookmarkChanged(isAdded: Bool, kind: AnalyticsContentKind) {
        self.log(isAdded ? .readerBookmarkAdded : .readerBookmarkRemoved, parameters: [
            Parameter.contentKind: kind.rawValue
        ])
    }

    func logPlaybackStarted(
        source: Source?,
        kind: AnalyticsContentKind? = nil,
        playerType: PlayerType,
        entry: PlaybackEntry
    ) {
        var parameters: [String: Any] = Self.sourceParameters(source, kind: kind)
        parameters[Parameter.playerType] = playerType.rawValue
        parameters[Parameter.entry] = entry.rawValue
        self.log(.playbackStarted, parameters: parameters)
    }

    func logPlaybackFailed(
        source: Source?,
        kind: AnalyticsContentKind? = nil,
        playerType: PlayerType,
        failure: PlaybackFailureCode
    ) {
        var parameters: [String: Any] = Self.sourceParameters(source, kind: kind)
        parameters[Parameter.playerType] = playerType.rawValue
        parameters[Parameter.errorCode] = AnalyticsErrorCode(failure).value
        self.log(.playbackFailed, parameters: parameters)
    }

    func logPlaybackCompleted(kind: AnalyticsContentKind, playerType: PlayerType) {
        self.log(.playbackCompleted, parameters: [
            Parameter.contentKind: kind.rawValue,
            Parameter.playerType: playerType.rawValue
        ])
    }

    func logPlaybackClosed(kind: AnalyticsContentKind, playerType: PlayerType, duration: TimeInterval) {
        self.log(.playbackClosed, parameters: [
            Parameter.contentKind: kind.rawValue,
            Parameter.playerType: playerType.rawValue,
            Parameter.durationBucket: Self.durationBucket(duration)
        ])
    }

    func logPlaybackFallbackTapped(_ action: PlaybackFallbackAction) {
        self.log(.playbackFallbackTapped, parameters: [
            Parameter.entry: action.rawValue
        ])
    }

    func logVideoLineSwitched(source: Source?) {
        var parameters: [String: Any] = [:]
        if let source: Source {
            parameters[Parameter.sourceIdHash] = Self.hashIdentifier(source.id)
        }
        self.log(.videoLineSwitched, parameters: parameters)
    }

    /// 中文注释：积分满额、页面即将弹广告。去广告用户不累计积分，所以不会产生这个事件。
    func logAdPointsThreshold(trigger: RewardedAdPlaybackTrigger) {
        self.log(.adPointsThreshold, parameters: [
            Parameter.adTrigger: trigger.rawValue
        ])
    }

    /// 中文注释：一次激励广告的结局。只报类别，不报余额与用户标识。
    func logRewardedAdResult(
        trigger: RewardedAdPlaybackTrigger,
        result: RewardedAdPresentationResult,
        signedIn: Bool
    ) {
        self.log(.rewardedAdResult, parameters: [
            Parameter.adTrigger: trigger.rawValue,
            Parameter.adResult: Self.adResultBucket(result),
            Parameter.signedIn: Self.boolValue(signedIn)
        ])
    }

    /// 中文注释：已有广告在播、这次唤起被跳过时报 `ad_result = busy`。
    func logRewardedAdSkippedBusy(trigger: RewardedAdPlaybackTrigger, signedIn: Bool) {
        self.log(.rewardedAdResult, parameters: [
            Parameter.adTrigger: trigger.rawValue,
            Parameter.adResult: "busy",
            Parameter.signedIn: Self.boolValue(signedIn)
        ])
    }

    static func adResultBucket(_ result: RewardedAdPresentationResult) -> String {
        switch result {
        case .completed:
            return "completed"
        case .skipped:
            return "skipped"
        case .unavailable:
            return "unavailable"
        case .failed:
            return "failed"
        }
    }

    func logAdRewardCredited(_ result: AdRewardCreditResult) {
        self.log(.adRewardCredited, parameters: [
            Parameter.result: result.rawValue
        ])
    }

    func logTrackingAuthorizationResult(_ result: TrackingAuthorizationResult) {
        self.log(.trackingAuthorizationResult, parameters: [
            Parameter.result: result.rawValue
        ])
    }

    // MARK: - F. 收藏、历史与内容锁定

    func logContentFilterChanged(screen: DiagnosticScreen, kind: AnalyticsContentKind) {
        self.log(.contentFilterChanged, parameters: [
            Parameter.screenName: screen.rawValue,
            Parameter.contentKind: kind.rawValue
        ])
    }

    func logSelectionModeEntered(screen: DiagnosticScreen, entry: SelectionModeEntry) {
        self.log(.selectionModeEntered, parameters: [
            Parameter.screenName: screen.rawValue,
            Parameter.entry: entry.rawValue
        ])
    }

    func logHistoryDeleted(entry: HistoryDeleteEntry, count: Int) {
        self.log(.historyDeleted, parameters: [
            Parameter.entry: entry.rawValue,
            Parameter.itemCountBucket: Self.countBucket(count)
        ])
    }

    func logOpenInLibraryTapped(screen: DiagnosticScreen) {
        self.log(.openInLibraryTapped, parameters: [
            Parameter.screenName: screen.rawValue
        ])
    }

    func logContentUnlockResult(trigger: ContentUnlockTrigger, result: AnalyticsResult) {
        self.log(.contentUnlockResult, parameters: [
            Parameter.trigger: trigger.rawValue,
            Parameter.result: result.rawValue
        ])
    }
}
