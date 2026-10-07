import Foundation

struct ComicChapterHistoryTransfer: Sendable {
    let value: ComicChapterHistory
}

struct VideoWatchHistoryTransfer: Sendable {
    let value: VideoWatchHistory
}

/// Serializes reading-history and ad-point writes outside MainActor.
actor ReadingActivityPersistenceCoordinator {
    private let saveComicChapterHistoryUseCase: SaveComicChapterHistoryUseCase
    private let loadLatestComicChapterHistoryUseCase: LoadLatestComicChapterHistoryUseCase
    private let saveVideoWatchHistoryUseCase: SaveVideoWatchHistoryUseCase
    private let loadVideoWatchHistoryUseCase: LoadVideoWatchHistoryUseCase
    private let accumulateAdPointsUseCase: AccumulateAdPointsUseCase
    private let consumeAdPointsUseCase: ConsumeAdPointsUseCase

    init(
        comicRepository: ComicChapterHistoryRepository,
        videoRepository: VideoWatchHistoryRepository,
        appUserRepository: AppUserRepository,
        activeAppUser: any ActiveAppUserProviding
    ) {
        self.saveComicChapterHistoryUseCase = SaveComicChapterHistoryUseCase(repository: comicRepository)
        self.loadLatestComicChapterHistoryUseCase = LoadLatestComicChapterHistoryUseCase(
            repository: comicRepository
        )
        self.saveVideoWatchHistoryUseCase = SaveVideoWatchHistoryUseCase(repository: videoRepository)
        self.loadVideoWatchHistoryUseCase = LoadVideoWatchHistoryUseCase(repository: videoRepository)
        self.accumulateAdPointsUseCase = AccumulateAdPointsUseCase(
            repository: appUserRepository,
            activeAppUser: activeAppUser
        )
        self.consumeAdPointsUseCase = ConsumeAdPointsUseCase(
            repository: appUserRepository,
            activeAppUser: activeAppUser
        )
    }

    func loadLatestComicHistory(
        userID: String,
        sourceID: String,
        comicItemID: String
    ) throws -> ComicChapterHistoryTransfer? {
        return try self.loadLatestComicChapterHistoryUseCase.execute(
            userID: userID,
            sourceID: sourceID,
            comicItemID: comicItemID
        ).map(ComicChapterHistoryTransfer.init(value:))
    }

    func saveComicHistory(
        _ history: ComicChapterHistoryTransfer,
        adPoints: Int?
    ) throws -> AdPointAccumulationResult? {
        try self.saveComicChapterHistoryUseCase.execute(history: history.value)
        return try adPoints.map { points in
            try self.accumulateAdPointsUseCase.execute(points: points)
        }
    }

    func loadVideoHistory(
        userID: String,
        sourceID: String,
        vodID: String,
        sourceIndex: Int,
        episodeIndex: Int
    ) throws -> VideoWatchHistoryTransfer? {
        return try self.loadVideoWatchHistoryUseCase.execute(
            userID: userID,
            sourceID: sourceID,
            vodID: vodID,
            sourceIndex: sourceIndex,
            episodeIndex: episodeIndex
        ).map(VideoWatchHistoryTransfer.init(value:))
    }

    /// 本作品最近一条视频历史（影视详情页继续看）。
    func loadLatestVideoHistory(
        userID: String,
        sourceID: String,
        detailURL: URL?,
        vodID: String?
    ) throws -> VideoWatchHistoryTransfer? {
        return try self.loadVideoWatchHistoryUseCase.latest(
            userID: userID,
            sourceID: sourceID,
            detailURL: detailURL,
            vodID: vodID
        ).map(VideoWatchHistoryTransfer.init(value:))
    }

    func saveVideoHistory(_ history: VideoWatchHistoryTransfer) throws {
        try self.saveVideoWatchHistoryUseCase.execute(history: history.value)
    }

    func accumulateAdPoints(_ points: Int) throws -> AdPointAccumulationResult {
        return try self.accumulateAdPointsUseCase.execute(points: points)
    }

    /// 广告播过（看完或提前关闭）后清零累计积分；没播出来不调、积分保留（30.8）。
    func consumeAdPoints() throws {
        try self.consumeAdPointsUseCase.execute()
    }
}
