import Foundation

// 中文注释：ReadingHistoryUseCases 承接 RSS、漫画和视频历史保存与读取用例。

/// 中文注释：保存 RSS 详情页历史；具体触发点会在 RSS 详情页接入小节处理。
struct SaveRSSReadingHistoryUseCase {
    private let repository: RSSReadingHistoryRepository

    init(repository: RSSReadingHistoryRepository) {
        self.repository = repository
    }

    func execute(history: RSSReadingHistory) throws {
        try self.repository.save(history)
    }
}

/// 中文注释：保存漫画章节阅读历史；具体触发点会在 Reader 接入小节处理。
struct SaveComicChapterHistoryUseCase {
    private let repository: ComicChapterHistoryRepository

    init(repository: ComicChapterHistoryRepository) {
        self.repository = repository
    }

    func execute(history: ComicChapterHistory) throws {
        try self.repository.save(history)
    }
}

/// 中文注释：读取指定漫画最近访问的章节历史，用于详情页恢复阅读进度。
struct LoadLatestComicChapterHistoryUseCase {
    private let repository: ComicChapterHistoryRepository

    init(repository: ComicChapterHistoryRepository) {
        self.repository = repository
    }

    func execute(
        userID: String,
        sourceID: String,
        comicItemID: String
    ) throws -> ComicChapterHistory? {
        return try self.repository.fetchLatest(
            userID: userID,
            sourceID: sourceID,
            comicItemID: comicItemID
        )
    }
}

/// 中文注释：保存视频观看历史；播放器接入后会在进入播放、离开播放和自动保存时调用。
struct SaveVideoWatchHistoryUseCase {
    private let repository: VideoWatchHistoryRepository

    init(repository: VideoWatchHistoryRepository) {
        self.repository = repository
    }

    func execute(history: VideoWatchHistory) throws {
        try self.repository.save(history)
    }

    func execute(
        userID: String,
        source: Source,
        reference: SourceVideoPlaybackReference,
        videoTitle: String,
        detailURL: URL?,
        coverURL: URL?,
        lastPlaybackTime: TimeInterval,
        duration: TimeInterval?,
        visitedAt: Date = Date()
    ) throws {
        let history: VideoWatchHistory = VideoWatchHistory(
            userID: userID,
            sourceID: source.id,
            vodID: reference.vodID,
            videoTitle: videoTitle,
            episodeTitle: reference.episodeTitle,
            episodeKey: reference.episodeKey,
            sourceIndex: reference.sourceIndex,
            episodeIndex: reference.episodeIndex,
            detailURL: detailURL,
            playPageURL: reference.playPageURL,
            candidateMediaURL: reference.candidateMediaURL,
            candidateMediaKind: reference.candidateMediaKind,
            playbackStatus: reference.status,
            playbackRequestConfig: reference.playbackRequestConfig,
            coverURL: coverURL,
            sourceName: reference.sourceName ?? source.name,
            lastPlaybackTime: lastPlaybackTime,
            duration: duration,
            visitedAt: visitedAt,
            updatedAt: visitedAt,
            previousEpisodeURL: reference.previousEpisodeURL,
            nextEpisodeURL: reference.nextEpisodeURL,
            sourceSnapshot: SourceSnapshot(source: source)
        )

        try self.execute(history: history)
    }
}

/// 中文注释：保存临时资源历史；不绑定 Source，不参与 Source 删除级联。
struct SaveTemporaryResourceHistoryUseCase {
    private let repository: TemporaryResourceHistoryRepository

    init(repository: TemporaryResourceHistoryRepository) {
        self.repository = repository
    }

    func execute(history: TemporaryResourceHistory) throws {
        try self.repository.save(history)
    }
}

/// 中文注释：读取某一视频单集的观看历史，用于播放器恢复播放时间。
struct LoadVideoWatchHistoryUseCase {
    private let repository: VideoWatchHistoryRepository

    init(repository: VideoWatchHistoryRepository) {
        self.repository = repository
    }

    func execute(
        userID: String,
        sourceID: String,
        vodID: String,
        sourceIndex: Int,
        episodeIndex: Int
    ) throws -> VideoWatchHistory? {
        return try self.repository.fetchHistory(
            userID: userID,
            sourceID: sourceID,
            vodID: vodID,
            sourceIndex: sourceIndex,
            episodeIndex: episodeIndex
        )
    }
}

/// 中文注释：聚合 RSS、漫画和视频历史，供 History 页面按访问时间倒序展示。
struct LoadReadingHistoryEntriesUseCase {
    private let rssRepository: RSSReadingHistoryRepository
    private let comicRepository: ComicChapterHistoryRepository
    private let videoRepository: VideoWatchHistoryRepository
    private let temporaryRepository: TemporaryResourceHistoryRepository

    init(
        rssRepository: RSSReadingHistoryRepository,
        comicRepository: ComicChapterHistoryRepository,
        videoRepository: VideoWatchHistoryRepository,
        temporaryRepository: TemporaryResourceHistoryRepository
    ) {
        self.rssRepository = rssRepository
        self.comicRepository = comicRepository
        self.videoRepository = videoRepository
        self.temporaryRepository = temporaryRepository
    }

    func execute(userID: String) throws -> [ReadingHistoryEntry] {
        let rssEntries: [ReadingHistoryEntry] = try self.rssRepository
            .fetchHistory(userID: userID)
            .map { history in
                return ReadingHistoryEntry(rssHistory: history)
            }
        let comicEntries: [ReadingHistoryEntry] = self.latestComicHistoriesByComic(
            try self.comicRepository.fetchHistory(userID: userID)
        )
            .map { history in
                return ReadingHistoryEntry(comicHistory: history)
            }
        let videoEntries: [ReadingHistoryEntry] = try self.videoRepository
            .fetchHistory(userID: userID)
            .latestVideoHistoriesByWork()
            .map { history in
                return ReadingHistoryEntry(videoHistory: history)
            }
        let temporaryEntries: [ReadingHistoryEntry] = try self.temporaryRepository
            .fetchHistory(userID: userID)
            .map { history in
                return ReadingHistoryEntry(temporaryHistory: history)
            }

        return (rssEntries + comicEntries + videoEntries + temporaryEntries).sorted { lhs, rhs in
            return lhs.visitedAt > rhs.visitedAt
        }
    }

    private func latestComicHistoriesByComic(_ histories: [ComicChapterHistory]) -> [ComicChapterHistory] {
        var latestByComicID: [String: ComicChapterHistory] = [:]

        for history: ComicChapterHistory in histories {
            let comicID: String = self.comicHistoryGroupID(history)
            if let existingHistory: ComicChapterHistory = latestByComicID[comicID],
               existingHistory.visitedAt >= history.visitedAt {
                continue
            }

            latestByComicID[comicID] = history
        }

        return latestByComicID.values.sorted { lhs, rhs in
            return lhs.visitedAt > rhs.visitedAt
        }
    }

    private func comicHistoryGroupID(_ history: ComicChapterHistory) -> String {
        return [
            history.userID,
            history.sourceID,
            history.comicItemID
        ].joined(separator: "::")
    }
}

/// 中文注释：删除单条历史记录，只影响该记录所在历史表，不删除 Source。
struct DeleteReadingHistoryEntryUseCase {
    private let rssRepository: RSSReadingHistoryRepository
    private let comicRepository: ComicChapterHistoryRepository
    private let videoRepository: VideoWatchHistoryRepository
    private let temporaryRepository: TemporaryResourceHistoryRepository

    init(
        rssRepository: RSSReadingHistoryRepository,
        comicRepository: ComicChapterHistoryRepository,
        videoRepository: VideoWatchHistoryRepository,
        temporaryRepository: TemporaryResourceHistoryRepository
    ) {
        self.rssRepository = rssRepository
        self.comicRepository = comicRepository
        self.videoRepository = videoRepository
        self.temporaryRepository = temporaryRepository
    }

    func execute(_ entry: ReadingHistoryEntry) throws {
        switch entry.kind {
        case .rss:
            if let history: RSSReadingHistory = entry.rssHistory {
                try self.rssRepository.delete(history)
            }
        case .comic:
            if let history: ComicChapterHistory = entry.comicHistory {
                try self.comicRepository.delete(history)
            }
        case .video:
            if let history: VideoWatchHistory = entry.videoHistory {
                try self.videoRepository.delete(history)
            }
        case .temporary:
            if let history: TemporaryResourceHistory = entry.temporaryHistory {
                try self.temporaryRepository.delete(history)
            }
        }
    }
}

private extension Array where Element == VideoWatchHistory {
    func latestVideoHistoriesByWork() -> [VideoWatchHistory] {
        var latestByWorkID: [String: VideoWatchHistory] = [:]

        for history: VideoWatchHistory in self {
            let workID: String = history.workHistoryKey
            if let existingHistory: VideoWatchHistory = latestByWorkID[workID],
               existingHistory.updatedAt >= history.updatedAt {
                continue
            }

            latestByWorkID[workID] = history
        }

        return latestByWorkID.values.sorted { lhs, rhs in
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}
