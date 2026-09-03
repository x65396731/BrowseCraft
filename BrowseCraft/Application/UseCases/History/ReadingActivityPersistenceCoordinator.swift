import Foundation

struct ComicChapterHistoryTransfer: Sendable {
    let value: ComicChapterHistory
}

struct RSSReadingHistoryTransfer: Sendable {
    let value: RSSReadingHistory
}

struct VideoWatchHistoryTransfer: Sendable {
    let value: VideoWatchHistory
}

/// Serializes reading-history and ad-point writes outside MainActor.
actor ReadingActivityPersistenceCoordinator {
    private let saveRSSReadingHistoryUseCase: SaveRSSReadingHistoryUseCase
    private let saveComicChapterHistoryUseCase: SaveComicChapterHistoryUseCase
    private let loadLatestComicChapterHistoryUseCase: LoadLatestComicChapterHistoryUseCase
    private let saveVideoWatchHistoryUseCase: SaveVideoWatchHistoryUseCase
    private let loadVideoWatchHistoryUseCase: LoadVideoWatchHistoryUseCase
    private let accumulateAdPointsUseCase: AccumulateAdPointsUseCase

    init(
        rssRepository: RSSReadingHistoryRepository,
        comicRepository: ComicChapterHistoryRepository,
        videoRepository: VideoWatchHistoryRepository,
        appUserRepository: AppUserRepository,
        activeAppUser: any ActiveAppUserProviding
    ) {
        self.saveRSSReadingHistoryUseCase = SaveRSSReadingHistoryUseCase(repository: rssRepository)
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

    func saveRSSHistory(
        _ history: RSSReadingHistoryTransfer,
        adPoints: Int
    ) throws -> AdPointAccumulationResult {
        try self.saveRSSReadingHistoryUseCase.execute(history: history.value)
        return try self.accumulateAdPointsUseCase.execute(points: adPoints)
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

    func saveVideoHistory(_ history: VideoWatchHistoryTransfer) throws {
        try self.saveVideoWatchHistoryUseCase.execute(history: history.value)
    }

    func accumulateAdPoints(_ points: Int) throws -> AdPointAccumulationResult {
        return try self.accumulateAdPointsUseCase.execute(points: points)
    }
}
