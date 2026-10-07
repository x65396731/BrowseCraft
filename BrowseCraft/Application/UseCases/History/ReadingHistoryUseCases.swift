import BrowseCraftCore
import BrowseCraftDomain
import Foundation

// 中文注释：ReadingHistoryUseCases 承接漫画、视频和站点书历史保存与读取用例。

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

/// 中文注释：保存站点书阅读历史（一本书一条）；触发点在 BookReaderViewModel 打开与落进度处。
struct SaveBookReadingHistoryUseCase {
    private let repository: BookReadingHistoryRepository

    init(repository: BookReadingHistoryRepository) {
        self.repository = repository
    }

    func execute(history: BookReadingHistory) throws {
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

    /// 中文注释：影视详情页「继续看」：本作品最近一条历史（`docs/design/Video-Detail-Page-Redesign-Design.md` 第七节）。
    /// 同来源、详情页地址相同为准；详情页地址对不上时退到 `vodID`（规则换过取法时地址会变）。
    func latest(
        userID: String,
        sourceID: String,
        detailURL: URL?,
        vodID: String?
    ) throws -> VideoWatchHistory? {
        let histories: [VideoWatchHistory] = try self.repository.fetchHistory(userID: userID)
            .filter { history in history.sourceID == sourceID }
        let byDetailURL: VideoWatchHistory? = detailURL.flatMap { url in
            histories
                .filter { history in history.detailURL == url }
                .max { lhs, rhs in lhs.updatedAt < rhs.updatedAt }
        }
        if let byDetailURL {
            return byDetailURL
        }
        guard let vodID: String = vodID?.trimmingCharacters(in: .whitespacesAndNewlines), vodID.isEmpty == false else {
            return nil
        }
        return histories
            .filter { history in history.vodID == vodID }
            .max { lhs, rhs in lhs.updatedAt < rhs.updatedAt }
    }
}

/// 中文注释：聚合漫画、视频和站点书历史，供 History 页面按访问时间倒序展示。
struct LoadReadingHistoryEntriesUseCase {
    private let comicRepository: ComicChapterHistoryRepository
    private let videoRepository: VideoWatchHistoryRepository
    private let bookRepository: BookReadingHistoryRepository
    private let temporaryRepository: TemporaryResourceHistoryRepository

    init(
        comicRepository: ComicChapterHistoryRepository,
        videoRepository: VideoWatchHistoryRepository,
        bookRepository: BookReadingHistoryRepository,
        temporaryRepository: TemporaryResourceHistoryRepository
    ) {
        self.comicRepository = comicRepository
        self.videoRepository = videoRepository
        self.bookRepository = bookRepository
        self.temporaryRepository = temporaryRepository
    }

    func execute(userID: String) throws -> [ReadingHistoryEntry] {
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
        // 中文注释：仓储本身一本书一条，不需要再按作品聚合。
        let bookEntries: [ReadingHistoryEntry] = try self.bookRepository
            .fetchHistory(userID: userID)
            .map { history in
                return ReadingHistoryEntry(bookHistory: history)
            }
        let temporaryEntries: [ReadingHistoryEntry] = try self.temporaryRepository
            .fetchHistory(userID: userID)
            .map { history in
                return ReadingHistoryEntry(temporaryHistory: history)
            }

        return (comicEntries + videoEntries + bookEntries + temporaryEntries).sorted { lhs, rhs in
            return lhs.visitedAt > rhs.visitedAt
        }
    }

    private func latestComicHistoriesByComic(_ histories: [ComicChapterHistory]) -> [ComicChapterHistory] {
        var latestByComicID: [String: ComicChapterHistory] = [:]

        for history: ComicChapterHistory in histories {
            let comicID: String = history.comicWorkKey
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
}

/// 中文注释：一次删除从历史表里拿走的全部记录；撤销时由 `RestoreReadingHistoryUseCase` 原样写回。
struct ReadingHistoryRemoval: Sendable {
    var comicHistories: [ComicChapterHistory] = []
    var videoHistories: [VideoWatchHistory] = []
    var bookHistories: [BookReadingHistory] = []
    var temporaryHistories: [TemporaryResourceHistory] = []
}

/// 中文注释：删除历史记录，只影响记录所在的历史表，不删除 Source、收藏与站点书续读位置。
/// 历史页一行是一部作品（`docs/design/History-Page-Redesign-Design.md`），所以按作品删：
/// 漫画删掉这部漫画的全部章节记录、视频删掉这部作品的全部剧集记录，刷新后不会冒出上一章 / 上一集。
struct DeleteReadingHistoryEntryUseCase {
    private let comicRepository: ComicChapterHistoryRepository
    private let videoRepository: VideoWatchHistoryRepository
    private let bookRepository: BookReadingHistoryRepository
    private let temporaryRepository: TemporaryResourceHistoryRepository

    init(
        comicRepository: ComicChapterHistoryRepository,
        videoRepository: VideoWatchHistoryRepository,
        bookRepository: BookReadingHistoryRepository,
        temporaryRepository: TemporaryResourceHistoryRepository
    ) {
        self.comicRepository = comicRepository
        self.videoRepository = videoRepository
        self.bookRepository = bookRepository
        self.temporaryRepository = temporaryRepository
    }

    @discardableResult
    func execute(_ entry: ReadingHistoryEntry) throws -> ReadingHistoryRemoval {
        return try self.execute([entry])
    }

    /// 中文注释：按历史表分组后批量删除，每张表最多一个写事务；单条删除只是它的特例。
    /// 返回被删的全部记录，供撤销原样写回。
    @discardableResult
    func execute(_ entries: [ReadingHistoryEntry]) throws -> ReadingHistoryRemoval {
        let comicTargets: [ComicChapterHistory] = entries.compactMap { $0.kind == .comic ? $0.comicHistory : nil }
        let videoTargets: [VideoWatchHistory] = entries.compactMap { $0.kind == .video ? $0.videoHistory : nil }
        var removal: ReadingHistoryRemoval = ReadingHistoryRemoval(
            bookHistories: entries.compactMap { $0.kind == .book ? $0.bookHistory : nil },
            temporaryHistories: entries.compactMap { $0.kind == .temporary ? $0.temporaryHistory : nil }
        )

        if comicTargets.isEmpty == false {
            let workKeys: Set<String> = Set(comicTargets.map(\.comicWorkKey))
            let siblings: [ComicChapterHistory] = try Set(comicTargets.map(\.userID)).flatMap { userID in
                return try self.comicRepository.fetchHistory(userID: userID).filter { workKeys.contains($0.comicWorkKey) }
            }
            removal.comicHistories = Self.merging(siblings, comicTargets, id: \.id)
            try self.comicRepository.delete(removal.comicHistories)
        }
        if videoTargets.isEmpty == false {
            let workKeys: Set<String> = Set(videoTargets.map(\.workHistoryKey))
            let siblings: [VideoWatchHistory] = try Set(videoTargets.map(\.userID)).flatMap { userID in
                return try self.videoRepository.fetchHistory(userID: userID).filter { workKeys.contains($0.workHistoryKey) }
            }
            removal.videoHistories = Self.merging(siblings, videoTargets, id: \.id)
            try self.videoRepository.delete(removal.videoHistories)
        }
        if removal.bookHistories.isEmpty == false {
            try self.bookRepository.delete(removal.bookHistories)
        }
        if removal.temporaryHistories.isEmpty == false {
            try self.temporaryRepository.delete(removal.temporaryHistories)
        }
        return removal
    }

    /// 中文注释：仓储里查到的同作品记录，补上调用方传进来却没查到的那几条（不重复）。
    private static func merging<Value>(_ stored: [Value], _ targets: [Value], id: KeyPath<Value, String>) -> [Value] {
        var seen: Set<String> = Set(stored.map { $0[keyPath: id] })
        var merged: [Value] = stored
        for target: Value in targets where seen.insert(target[keyPath: id]).inserted {
            merged.append(target)
        }
        return merged
    }
}

/// 中文注释：撤销删除，把 `DeleteReadingHistoryEntryUseCase` 拿走的记录原样写回（含原访问时间），
/// 条目因此回到历史页原来的日期分组。
struct RestoreReadingHistoryUseCase {
    private let comicRepository: ComicChapterHistoryRepository
    private let videoRepository: VideoWatchHistoryRepository
    private let bookRepository: BookReadingHistoryRepository
    private let temporaryRepository: TemporaryResourceHistoryRepository

    init(
        comicRepository: ComicChapterHistoryRepository,
        videoRepository: VideoWatchHistoryRepository,
        bookRepository: BookReadingHistoryRepository,
        temporaryRepository: TemporaryResourceHistoryRepository
    ) {
        self.comicRepository = comicRepository
        self.videoRepository = videoRepository
        self.bookRepository = bookRepository
        self.temporaryRepository = temporaryRepository
    }

    func execute(_ removal: ReadingHistoryRemoval) throws {
        for history: ComicChapterHistory in removal.comicHistories {
            try self.comicRepository.save(history)
        }
        // 中文注释：视频仓储保存时按作品覆盖旧记录；先写旧的、后写新的，留下的是最近一条。
        for history: VideoWatchHistory in removal.videoHistories.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            try self.videoRepository.save(history)
        }
        for history: BookReadingHistory in removal.bookHistories {
            try self.bookRepository.save(history)
        }
        for history: TemporaryResourceHistory in removal.temporaryHistories {
            try self.temporaryRepository.save(history)
        }
    }
}

private extension ComicChapterHistory {
    /// 中文注释：同一部漫画的全部章节记录共用的作品键；历史页按它聚合，也按它整部删除。
    var comicWorkKey: String {
        return [
            self.userID,
            self.sourceID,
            self.comicItemID
        ].joined(separator: "::")
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
