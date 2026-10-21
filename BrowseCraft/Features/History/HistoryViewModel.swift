import Observation
@preconcurrency import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftLog
import Foundation

// 中文注释：HistoryViewModel 负责历史页数据加载、类型筛选、继续条目、按天分组、看到哪里、来源状态、删除与选择模式下的批量删除
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

    /// 中文注释：条目或筛选一变就把计数、筛选结果、继续条目、按天分组算一次存起来（2026-10-10 复审 B-8）：
    /// 之前都是计算属性，一次 body 把 1000 条过滤七遍、取日 1000 次，19 ms。
    private(set) var readingHistoryEntries: [ReadingHistoryEntry] = [] {
        didSet { self.rebuildDerivedState() }
    }
    private(set) var sources: [Source] = []
    var kindFilter: KindFilter = .all {
        didSet { self.rebuildDerivedState() }
    }
    /// 当前筛选下的条目，按访问时间倒序。
    private(set) var filteredEntries: [ReadingHistoryEntry] = []
    /// 继续卡片：当前筛选下最近的一条；它不再在下方列表重复出现。
    private(set) var continueEntry: ReadingHistoryEntry?
    /// 继续卡片以外的条目，按访问时间倒序、按天分组。
    private(set) var dayGroups: [DayGroup] = []
    /// 选择模式下继续卡片收回列表：当前筛选下的全部条目按天分组（设计文档 2.6）。
    private(set) var selectionDayGroups: [DayGroup] = []
    private var countsByFilter: [KindFilter: Int] = [:]
    var videoPlaybackRoute: VideoPlaybackRoute?
    var errorMessage: String?
    /// 选择模式（设计文档 2.6）：勾选的条目只在当前筛选范围内。
    private(set) var isSelecting: Bool = false
    private(set) var selectedIDs: Set<String> = []

    @ObservationIgnored private var imageRequestConfigs: [String: RequestConfig] = [:]

    private let persistenceCoordinator: HistoryPersistenceCoordinator
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let fallbackUserID: String
    private let videoPlayerViewModelFactory: @MainActor (VideoWatchHistory, Source) -> VideoPlayerViewModel
    private let resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase
    private let now: () -> Date

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
    /// 中文注释：读取三类历史并按访问时间倒序合并；失败只给错误文案。
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
            AppLog.error(.database, "history-load-failed", ["error": .error(error)])
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - 筛选、继续条目与分组

    func count(for filter: KindFilter) -> Int {
        return self.countsByFilter[filter] ?? 0
    }

    /// 条目或筛选变了：一遍过数四类计数，再算筛选结果、继续条目与按天分组。
    private func rebuildDerivedState() {
        var counts: [KindFilter: Int] = [:]
        for filter: KindFilter in KindFilter.allCases {
            counts[filter] = 0
        }
        var filtered: [ReadingHistoryEntry] = []
        for entry: ReadingHistoryEntry in self.readingHistoryEntries {
            for filter: KindFilter in KindFilter.allCases where Self.matches(entry, filter) {
                counts[filter, default: 0] += 1
            }
            if Self.matches(entry, self.kindFilter) {
                filtered.append(entry)
            }
        }
        self.countsByFilter = counts
        self.filteredEntries = filtered
        self.continueEntry = filtered.first
        self.dayGroups = self.groupByDay(Array(filtered.dropFirst()))
        self.selectionDayGroups = self.groupByDay(filtered)

        // 中文注释：数据变了（同步、别处删除）时，勾选只留还在当前筛选里的条目；历史变空就退出选择模式。
        if self.isSelecting {
            if self.readingHistoryEntries.isEmpty {
                self.endSelection()
            } else {
                self.selectedIDs.formIntersection(filtered.map(\.id))
            }
        }
    }

    private func groupByDay(_ entries: [ReadingHistoryEntry]) -> [DayGroup] {
        let now: Date = self.now()
        let calendar: Calendar = .current
        var groups: [DayGroup] = []
        var currentDay: CatalogPersonalTimeline.Day?
        var currentEntries: [ReadingHistoryEntry] = []
        for entry: ReadingHistoryEntry in entries {
            let day: CatalogPersonalTimeline.Day = CatalogPersonalTimeline.day(
                for: entry.visitedAt,
                now: now,
                calendar: calendar
            )
            if day != currentDay {
                if let finishedDay: CatalogPersonalTimeline.Day = currentDay {
                    groups.append(DayGroup(day: finishedDay, entries: currentEntries))
                }
                currentDay = day
                currentEntries = []
            }
            currentEntries.append(entry)
        }
        if let finishedDay: CatalogPersonalTimeline.Day = currentDay {
            groups.append(DayGroup(day: finishedDay, entries: currentEntries))
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

    /// 埋点的内容类型：历史条目分不出有声书，书一律报 book；临时资源按自身类型。
    static func analyticsKind(of entry: ReadingHistoryEntry) -> AnalyticsContentKind {
        switch Self.catalogKind(of: entry) {
        case .video:
            return .video
        case .comic:
            return .comic
        case .book:
            return .book
        }
    }

    static func analyticsKind(of filter: KindFilter) -> AnalyticsContentKind {
        switch filter {
        case .all:
            return .all
        case .video:
            return .video
        case .comic:
            return .comic
        case .book:
            return .book
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
            if let chapter: String = TrimmedText.nonEmpty(history.chapterTitle) {
                parts.append(chapter)
            }
            if let pageIndex: Int = history.lastPageIndex, pageIndex >= 0 {
                parts.append(String(format: NSLocalizedString("history_progress_page", comment: ""), pageIndex + 1))
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .book:
            guard let chapter: String = TrimmedText.nonEmpty(entry.bookHistory?.chapterTitle) else {
                return nil
            }
            let key: String = self.isAudiobook(entry) ? "history_progress_listened_to" : "history_progress_read_to"
            return String(format: NSLocalizedString(key, comment: ""), chapter)
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
        if let episode: String = TrimmedText.nonEmpty(history.episodeTitle) {
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
            return TrimmedText.nonEmpty(entry.bookHistory?.detailURL)
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

    /// 中文注释：条目所属来源是否整站有声——与库页同一口径（`ResolveLibrarySourcePresentationUseCase.isAudiobookSource`），
    /// 有声书的措辞改成「上次听到 / 听到 / 继续听」；来源已不在（只剩快照）时按快照判。
    func isAudiobook(_ entry: ReadingHistoryEntry) -> Bool {
        guard entry.kind == .book, let source: Source = self.source(for: entry) else {
            return false
        }
        return self.resolveLibrarySourcePresentationUseCase.isAudiobookSource(for: source)
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
            ?? TrimmedText.nonEmpty(entry.videoHistory?.sourceName)
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

    // MARK: - 删除

    /// 单条删除（左滑、长按）：按作品删掉全部记录，不弹确认，也没有撤销（2026-10-17 用户裁定）。返回是否成功，页面据此上报埋点。
    @MainActor
    @discardableResult
    func delete(_ entry: ReadingHistoryEntry) async -> Bool {
        return await self.delete([entry])
    }

    @MainActor
    private func delete(_ entries: [ReadingHistoryEntry]) async -> Bool {
        do {
            _ = try await self.persistenceCoordinator.delete(
                ReadingHistoryEntriesTransfer(values: entries)
            )
            let deletedIDs: Set<String> = Set(entries.map(\.id))
            self.readingHistoryEntries.removeAll { deletedIDs.contains($0.id) }
            return true
        } catch {
            AppLog.error(.database, "history-delete-failed", ["error": .error(error)])
            self.errorMessage = error.localizedDescription
            await self.load()
            return false
        }
    }

    // MARK: - 选择与批量删除（设计文档 2.6）

    var selectedCount: Int {
        return self.selectedIDs.count
    }

    var isAllVisibleSelected: Bool {
        return self.filteredEntries.isEmpty == false
            && self.filteredEntries.allSatisfy { self.selectedIDs.contains($0.id) }
    }

    func isSelected(_ entry: ReadingHistoryEntry) -> Bool {
        return self.selectedIDs.contains(entry.id)
    }

    /// 进入选择模式；从长按菜单「选择多项」进来时预先选中那一条。
    func beginSelection(preselecting entry: ReadingHistoryEntry? = nil) {
        self.isSelecting = true
        self.selectedIDs = entry.map { [$0.id] } ?? []
    }

    func endSelection() {
        self.isSelecting = false
        self.selectedIDs = []
    }

    func toggleSelection(_ entry: ReadingHistoryEntry) {
        if self.selectedIDs.contains(entry.id) {
            self.selectedIDs.remove(entry.id)
        } else {
            self.selectedIDs.insert(entry.id)
        }
    }

    /// 「全选 / 全不选」：全部选中时清空，否则选中当前筛选下的全部条目（含继续卡片那一条）。
    func toggleSelectAll() {
        if self.isAllVisibleSelected {
            self.selectedIDs = []
        } else {
            self.selectedIDs = Set(self.filteredEntries.map(\.id))
        }
    }

    /// 确认框里点了「删除」：一次删掉所选作品，然后退出选择模式。返回删了几条（失败或没选为 0），页面据此上报埋点。
    @MainActor
    @discardableResult
    func deleteSelected() async -> Int {
        let entries: [ReadingHistoryEntry] = self.filteredEntries.filter { self.selectedIDs.contains($0.id) }
        guard entries.isEmpty == false else {
            return 0
        }
        let isDeleted: Bool = await self.delete(entries)
        self.endSelection()
        return isDeleted ? entries.count : 0
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

    private var currentUserID: String {
        return self.activeAppUser?.currentUserID.uuidString ?? self.fallbackUserID
    }
}
