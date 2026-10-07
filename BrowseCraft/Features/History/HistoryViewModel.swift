import Observation
@preconcurrency import BrowseCraftCore
import BrowseCraftDomain
import Foundation

// 中文注释：HistoryViewModel 负责历史页数据加载、类型筛选、继续条目、按天分组、看到哪里、来源状态与删除 / 撤销
// （`docs/design/History-Page-Redesign-Design.md`）。

@MainActor
@Observable
final class HistoryViewModel {
    /// 顶部类型筛选：「全部」与三个类型一直显示，没有历史的类型计数为 0；临时资源按自身类型归入视频或漫画。
    enum KindFilter: Hashable, CaseIterable {
        case all
        case video
        case comic
        case book
    }

    /// 历史条目所属来源此刻的状态，决定这一行怎么显示、点了去哪里。
    enum SourceState: Equatable {
        /// 来源还在且占着位置：点行接着看。
        case available
        /// 来源因位置不够被暂停：点行打开来源页的启用来源窗口。
        case paused
        /// 来源已删除，但历史里存了来源快照：整行变淡，仍用快照尝试打开。
        case deleted
        /// 来源找不到也没有快照：行不可点，只能删除。
        case unknown
        /// 临时资源没有来源：第三行显示主机名，照常打开。
        case temporary
    }

    struct DayGroup: Identifiable {
        let day: CatalogPersonalTimeline.Day
        let entries: [ReadingHistoryEntry]

        var id: CatalogPersonalTimeline.Day {
            return self.day
        }
    }

    private(set) var readingHistoryEntries: [ReadingHistoryEntry] = []
    private(set) var sources: [Source] = []
    var kindFilter: KindFilter = .all
    var videoPlaybackRoute: VideoPlaybackRoute?
    var errorMessage: String?
    /// 刚在本页删除、还能撤销的条目；底部提示随它出现和消失。
    private(set) var undoableEntry: ReadingHistoryEntry?

    @ObservationIgnored private var pendingRemoval: ReadingHistoryRemoval?
    @ObservationIgnored private var undoDismissTask: Task<Void, Never>?
    @ObservationIgnored private var imageRequestConfigs: [String: RequestConfig] = [:]

    private let persistenceCoordinator: HistoryPersistenceCoordinator
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let fallbackUserID: String
    private let videoPlayerViewModelFactory: @MainActor (VideoWatchHistory, Source) -> VideoPlayerViewModel
    private let resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase
    private let now: () -> Date

    /// 撤销提示停留的时长，与收藏页相同。
    static let undoDuration: Duration = .seconds(4)
    /// 视频看到最后这一段就算看完。
    static let finishedThreshold: Double = 0.95

    init(
        persistenceCoordinator: HistoryPersistenceCoordinator,
        activeAppUser: (any ActiveAppUserProviding)? = nil,
        userID: String = AppUser.localDefaultID,
        videoPlayerViewModelFactory: @escaping @MainActor (VideoWatchHistory, Source) -> VideoPlayerViewModel,
        resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase =
            ResolveLibrarySourcePresentationUseCase(),
        now: @escaping () -> Date = Date.init
    ) {
        self.persistenceCoordinator = persistenceCoordinator
        self.activeAppUser = activeAppUser
        self.fallbackUserID = userID
        self.videoPlayerViewModelFactory = videoPlayerViewModelFactory
        self.resolveLibrarySourcePresentationUseCase = resolveLibrarySourcePresentationUseCase
        self.now = now
    }

    @MainActor
    /// 中文注释：load 方法封装当前类型的一段业务或界面行为。
    func load() async {
        do {
            let snapshot: HistoryPersistenceSnapshot = try await self.persistenceCoordinator.load(
                userID: self.currentUserID
            )
            self.sources = snapshot.sources
            self.readingHistoryEntries = self.deduplicatedVideoEntries(
                snapshot.entries
            )
            self.imageRequestConfigs = self.makeImageRequestConfigs()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - 筛选、继续条目与分组

    func count(for filter: KindFilter) -> Int {
        return self.readingHistoryEntries.filter { entry in
            return Self.matches(entry, filter)
        }.count
    }

    /// 当前筛选下的条目，按访问时间倒序。
    var filteredEntries: [ReadingHistoryEntry] {
        return self.readingHistoryEntries.filter { entry in
            return Self.matches(entry, self.kindFilter)
        }
    }

    /// 继续卡片：当前筛选下最近的一条；它不再在下方列表重复出现。
    var continueEntry: ReadingHistoryEntry? {
        return self.filteredEntries.first
    }

    /// 继续卡片以外的条目，按访问时间倒序、按天分组。
    var dayGroups: [DayGroup] {
        let now: Date = self.now()
        let calendar: Calendar = .current
        var groups: [DayGroup] = []
        for entry: ReadingHistoryEntry in self.filteredEntries.dropFirst() {
            let day: CatalogPersonalTimeline.Day = CatalogPersonalTimeline.day(
                for: entry.visitedAt,
                now: now,
                calendar: calendar
            )
            if let last: DayGroup = groups.last, last.day == day {
                groups[groups.count - 1] = DayGroup(day: day, entries: last.entries + [entry])
            } else {
                groups.append(DayGroup(day: day, entries: [entry]))
            }
        }
        return groups
    }

    static func catalogKind(of entry: ReadingHistoryEntry) -> CatalogSourceKind {
        switch entry.kind {
        case .video:
            return .video
        case .comic:
            return .comic
        case .book:
            return .book
        case .temporary:
            return entry.temporaryHistory?.kind == .comic ? .comic : .video
        }
    }

    private static func matches(_ entry: ReadingHistoryEntry, _ filter: KindFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .video:
            return Self.catalogKind(of: entry) == .video
        case .comic:
            return Self.catalogKind(of: entry) == .comic
        case .book:
            return Self.catalogKind(of: entry) == .book
        }
    }

    // MARK: - 一行显示什么

    /// 第二行「看到哪里」，只用历史里已有的字段；什么都没有时为 nil。
    func progressText(for entry: ReadingHistoryEntry) -> String? {
        switch entry.kind {
        case .video:
            guard let history: VideoWatchHistory = entry.videoHistory else {
                return nil
            }
            return Self.videoProgressText(for: history)
        case .comic:
            guard let history: ComicChapterHistory = entry.comicHistory else {
                return nil
            }
            var parts: [String] = []
            if let chapter: String = Self.nonEmpty(history.chapterTitle) {
                parts.append(chapter)
            }
            if let pageIndex: Int = history.lastPageIndex, pageIndex >= 0 {
                parts.append(String(format: NSLocalizedString("history_progress_page", comment: ""), pageIndex + 1))
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .book:
            guard let chapter: String = Self.nonEmpty(entry.bookHistory?.chapterTitle) else {
                return nil
            }
            return String(format: NSLocalizedString("history_progress_read_to", comment: ""), chapter)
        case .temporary:
            return entry.temporaryHistory?.kind == .comic
                ? NSLocalizedString("history_temporary_comic", comment: "")
                : NSLocalizedString("history_temporary_video", comment: "")
        }
    }

    /// 视频知道时长时的播放进度（0...1），用来在封面底边画进度条；其余为 nil。
    func playbackProgress(for entry: ReadingHistoryEntry) -> Double? {
        guard let history: VideoWatchHistory = entry.videoHistory else {
            return nil
        }
        return Self.playbackProgress(for: history)
    }

    /// 视频「看到哪里」：「第12集 · 看到 23:14 / 45:00」；库页「上次看到」瓷砖共用（`docs/design/Library-Video-Page-Redesign-Design.md` 第六节）。
    static func videoProgressText(for history: VideoWatchHistory) -> String? {
        var parts: [String] = []
        if let episode: String = Self.nonEmpty(history.episodeTitle) {
            parts.append(episode)
        }
        if let duration: TimeInterval = history.duration, duration > 0,
           history.lastPlaybackTime >= duration * Self.finishedThreshold {
            parts.append(NSLocalizedString("history_progress_finished", comment: ""))
        } else if let duration: TimeInterval = history.duration, duration > 0 {
            parts.append(String(
                format: NSLocalizedString("history_progress_watched_of", comment: ""),
                Self.clockText(history.lastPlaybackTime),
                Self.clockText(duration)
            ))
        } else if history.lastPlaybackTime > 0 {
            parts.append(String(
                format: NSLocalizedString("history_progress_watched", comment: ""),
                Self.clockText(history.lastPlaybackTime)
            ))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func playbackProgress(for history: VideoWatchHistory) -> Double? {
        guard let duration: TimeInterval = history.duration, duration > 0 else {
            return nil
        }
        return min(max(history.lastPlaybackTime / duration, 0), 1)
    }

    func coverURL(for entry: ReadingHistoryEntry) -> String? {
        let url: URL?
        switch entry.kind {
        case .video:
            url = entry.videoHistory?.coverURL
        case .comic:
            url = entry.comicHistory?.coverURL
        case .book:
            url = entry.bookHistory?.coverURL
        case .temporary:
            url = entry.temporaryHistory?.coverURL
        }
        return url?.absoluteString
    }

    /// 封面请求带的 Referer：作品详情页，没有时退到章节 / 播放页。
    func refererURL(for entry: ReadingHistoryEntry) -> String? {
        switch entry.kind {
        case .video:
            return (entry.videoHistory?.detailURL ?? entry.videoHistory?.playPageURL)?.absoluteString
        case .comic:
            return entry.comicHistory?.chapterURL?.absoluteString
        case .book:
            return Self.nonEmpty(entry.bookHistory?.detailURL)
        case .temporary:
            return (entry.temporaryHistory?.sourcePageURL ?? entry.temporaryHistory?.resourceURL)?.absoluteString
        }
    }

    /// 封面请求沿用来源规则里的图片请求配置（与库页同一份），按来源缓存。
    func imageRequestConfig(for entry: ReadingHistoryEntry) -> RequestConfig? {
        return self.imageRequestConfigs[entry.sourceID]
    }

    // MARK: - 来源

    func source(for sourceID: String) -> Source? {
        return self.sources.first { source in
            return source.id == sourceID
        }
    }

    func source(for history: ComicChapterHistory) -> Source? {
        return self.source(for: history.sourceID) ?? history.fallbackSource()
    }

    func source(for history: VideoWatchHistory) -> Source? {
        return self.source(for: history.sourceID) ?? history.fallbackSource()
    }

    func source(for history: BookReadingHistory) -> Source? {
        return self.source(for: history.sourceID) ?? history.fallbackSource()
    }

    /// 条目的来源：当前来源优先，没有时用历史里存的来源快照。
    func source(for entry: ReadingHistoryEntry) -> Source? {
        switch entry.kind {
        case .video:
            return entry.videoHistory.flatMap { self.source(for: $0) }
        case .comic:
            return entry.comicHistory.flatMap { self.source(for: $0) }
        case .book:
            return entry.bookHistory.flatMap { self.source(for: $0) }
        case .temporary:
            return nil
        }
    }

    func sourceState(for entry: ReadingHistoryEntry) -> SourceState {
        if entry.kind == .temporary {
            return .temporary
        }
        if let currentSource: Source = self.source(for: entry.sourceID) {
            return currentSource.accessState == .lockedBySlotLimit ? .paused : .available
        }
        return self.source(for: entry) == nil ? .unknown : .deleted
    }

    /// 第三行开头：来源名；临时资源是主机名。
    func sourceName(for entry: ReadingHistoryEntry) -> String {
        if entry.kind == .temporary {
            return entry.temporaryHistory?.resourceURL.host ?? ""
        }
        return self.source(for: entry)?.name
            ?? Self.nonEmpty(entry.videoHistory?.sourceName)
            ?? NSLocalizedString("favorites_unknown_source", comment: "")
    }

    // MARK: - 打开

    @MainActor
    func openVideoHistory(_ history: VideoWatchHistory) {
        guard let source: Source = self.source(for: history) else {
            self.errorMessage = NSLocalizedString("history_error_missing_video_source", comment: "")
            return
        }

        let viewModel: VideoPlayerViewModel = self.videoPlayerViewModelFactory(history, source)
        self.videoPlaybackRoute = VideoPlaybackRoute(
            id: history.id,
            viewModel: viewModel
        )
    }

    // MARK: - 删除与撤销

    /// 删除不弹确认（2026-10-03 用户裁定）：按作品删掉全部记录，底部给出可撤销提示。
    @MainActor
    func delete(_ entry: ReadingHistoryEntry) async {
        do {
            let removal: ReadingHistoryRemoval = try await self.persistenceCoordinator.delete(
                ReadingHistoryEntriesTransfer(values: [entry])
            )
            self.readingHistoryEntries.removeAll { $0.id == entry.id }
            self.showUndo(for: entry, removal: removal)
        } catch {
            self.errorMessage = error.localizedDescription
            await self.load()
        }
    }

    /// 撤销：把删掉的记录原样写回，条目回到原来的日期分组。
    @MainActor
    func undoDelete() async {
        guard let removal: ReadingHistoryRemoval = self.pendingRemoval else {
            return
        }
        self.dismissUndo()
        do {
            try await self.persistenceCoordinator.restore(removal)
        } catch {
            self.errorMessage = error.localizedDescription
        }
        await self.load()
    }

    func dismissUndo() {
        self.undoDismissTask?.cancel()
        self.undoDismissTask = nil
        self.undoableEntry = nil
        self.pendingRemoval = nil
    }

    private func showUndo(for entry: ReadingHistoryEntry, removal: ReadingHistoryRemoval) {
        self.undoDismissTask?.cancel()
        self.undoableEntry = entry
        self.pendingRemoval = removal
        self.undoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.undoDuration)
            guard Task.isCancelled == false,
                  let self = self,
                  self.undoableEntry?.id == entry.id else {
                return
            }
            self.undoableEntry = nil
            self.pendingRemoval = nil
        }
    }

    // MARK: - 私有

    private func makeImageRequestConfigs() -> [String: RequestConfig] {
        var configs: [String: RequestConfig] = [:]
        for entry: ReadingHistoryEntry in self.readingHistoryEntries where configs[entry.sourceID] == nil {
            guard let source: Source = self.source(for: entry),
                  let config: RequestConfig = self.resolveLibrarySourcePresentationUseCase.imageRequestConfig(
                    for: source,
                    listTab: nil
                  ) else {
                continue
            }
            configs[entry.sourceID] = config
        }
        return configs
    }

    private func deduplicatedVideoEntries(_ entries: [ReadingHistoryEntry]) -> [ReadingHistoryEntry] {
        var latestVideoEntriesByWorkID: [String: ReadingHistoryEntry] = [:]
        var deduplicatedEntries: [ReadingHistoryEntry] = []

        for entry: ReadingHistoryEntry in entries {
            guard let videoHistory: VideoWatchHistory = entry.videoHistory else {
                deduplicatedEntries.append(entry)
                continue
            }

            let workID: String = videoHistory.workHistoryKey
            if let existingEntry: ReadingHistoryEntry = latestVideoEntriesByWorkID[workID],
               existingEntry.visitedAt >= entry.visitedAt {
                continue
            }

            latestVideoEntriesByWorkID[workID] = entry
        }

        deduplicatedEntries.append(contentsOf: latestVideoEntriesByWorkID.values)
        return deduplicatedEntries.sorted { lhs, rhs in
            return lhs.visitedAt > rhs.visitedAt
        }
    }

    /// 「23:14」「1:02:30」：不足一小时不写小时。
    static func clockText(_ interval: TimeInterval) -> String {
        let total: Int = max(Int(interval.rounded(.down)), 0)
        let hours: Int = total / 3600
        let minutes: Int = (total % 3600) / 60
        let seconds: Int = total % 60
        if hours > 0 {
            return String(format: "%ld:%02ld:%02ld", hours, minutes, seconds)
        }
        return String(format: "%02ld:%02ld", minutes, seconds)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed: String = text?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    private var currentUserID: String {
        return self.activeAppUser?.currentUserID.uuidString ?? self.fallbackUserID
    }
}
