import Observation
@preconcurrency import BrowseCraftCore
import BrowseCraftDomain
import Foundation

// 中文注释：FavoritesViewModel 负责收藏页数据加载、类型筛选、按天分组、来源状态与取消 / 撤销收藏
// （`docs/design/Favorites-Page-Redesign-Design.md`）。

@MainActor
@Observable
final class FavoritesViewModel {
    /// 顶部类型筛选：「全部」与三个类型一直显示，没有收藏的类型计数为 0。
    enum KindFilter: Hashable, CaseIterable {
        case all
        case video
        case comic
        case book
    }

    /// 收藏条目所属来源此刻的状态，决定这一行怎么显示、点了去哪里。
    enum SourceState: Equatable {
        /// 来源还在且占着位置：点行进详情。
        case available
        /// 来源因位置不够被暂停：点行打开来源页的启用来源窗口。
        case paused
        /// 来源已删除，但收藏时存了来源快照：整行变淡，仍可尝试打开详情。
        case deleted
        /// 来源找不到也没有快照：行不可点，只能取消收藏。
        case unknown
    }

    struct DayGroup: Identifiable {
        let day: CatalogPersonalTimeline.Day
        let items: [FavoriteContentItem]

        var id: CatalogPersonalTimeline.Day {
            return self.day
        }
    }

    /// 中文注释：条目或筛选一变就把计数与按天分组算一次存起来（2026-10-10 复审 B-8）：之前是计算属性，
    /// 一次 body 把 1000 条过滤五遍再排序一次，10 ms。
    private(set) var favoriteItems: [FavoriteContentItem] = [] {
        didSet { self.rebuildDerivedState() }
    }
    private(set) var sources: [Source] = []
    var errorMessage: String?
    var kindFilter: KindFilter = .all {
        didSet { self.rebuildDerivedState() }
    }
    /// 当前筛选下的条目，按收藏时间倒序、按天分组。
    private(set) var dayGroups: [DayGroup] = []
    private var countsByFilter: [KindFilter: Int] = [:]
    /// 刚在本页取消收藏、还能撤销的条目；底部提示随它出现和消失。
    private(set) var undoableItem: FavoriteContentItem?
    /// 本页每改动一次收藏集合（取消或撤销）就加一；宿主据此让库页刷新封面上的爱心状态。
    private(set) var changeRevision: Int = 0

    @ObservationIgnored private var imageRequestConfigs: [String: RequestConfig] = [:]
    @ObservationIgnored private var undoDismissTask: Task<Void, Never>?

    private let persistenceCoordinator: FavoritesPersistenceCoordinator
    private let resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase
    private let now: () -> Date

    /// 撤销提示停留的时长。
    static let undoDuration: Duration = .seconds(4)

    init(
        persistenceCoordinator: FavoritesPersistenceCoordinator,
        resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase =
            ResolveLibrarySourcePresentationUseCase(),
        now: @escaping () -> Date = Date.init,
        userID _: String = AppUser.localDefaultID
    ) {
        self.persistenceCoordinator = persistenceCoordinator
        self.resolveLibrarySourcePresentationUseCase = resolveLibrarySourcePresentationUseCase
        self.now = now
    }

    @MainActor
    func load() async {
        do {
            let snapshot: FavoritesPersistenceSnapshot = try await self.persistenceCoordinator.load()
            self.apply(snapshot)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - 筛选与分组

    func count(for filter: KindFilter) -> Int {
        return self.countsByFilter[filter] ?? 0
    }

    /// 条目或筛选变了：一遍过数四类计数，再把当前筛选下的条目按收藏时间倒序、按天分组。
    private func rebuildDerivedState() {
        var counts: [KindFilter: Int] = [:]
        for filter: KindFilter in KindFilter.allCases {
            counts[filter] = 0
        }
        var matched: [(offset: Int, element: FavoriteContentItem)] = []
        for (offset, item) in self.favoriteItems.enumerated() {
            for filter: KindFilter in KindFilter.allCases where Self.matches(item, filter) {
                counts[filter, default: 0] += 1
            }
            if Self.matches(item, self.kindFilter) {
                matched.append((offset: offset, element: item))
            }
        }
        self.countsByFilter = counts

        let sorted: [FavoriteContentItem] = matched
            .sorted { left, right in
                switch (Self.sortDate(left.element), Self.sortDate(right.element)) {
                case (let leftDate?, let rightDate?) where leftDate != rightDate:
                    return leftDate > rightDate
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                default:
                    return left.offset < right.offset
                }
            }
            .map { $0.element }

        let now: Date = self.now()
        let calendar: Calendar = .current
        var groups: [DayGroup] = []
        var currentDay: CatalogPersonalTimeline.Day?
        var currentItems: [FavoriteContentItem] = []
        for item: FavoriteContentItem in sorted {
            let day: CatalogPersonalTimeline.Day = CatalogPersonalTimeline.day(
                for: Self.sortDate(item),
                now: now,
                calendar: calendar
            )
            if day != currentDay {
                if let finishedDay: CatalogPersonalTimeline.Day = currentDay {
                    groups.append(DayGroup(day: finishedDay, items: currentItems))
                }
                currentDay = day
                currentItems = []
            }
            currentItems.append(item)
        }
        if let finishedDay: CatalogPersonalTimeline.Day = currentDay {
            groups.append(DayGroup(day: finishedDay, items: currentItems))
        }
        self.dayGroups = groups
    }

    static func catalogKind(of item: FavoriteContentItem) -> CatalogSourceKind {
        switch item.kind {
        case .videoNative, .videoWeb:
            return .video
        case .comic:
            return .comic
        case .book:
            return .book
        }
    }

    private static func matches(_ item: FavoriteContentItem, _ filter: KindFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .video:
            return Self.catalogKind(of: item) == .video
        case .comic:
            return Self.catalogKind(of: item) == .comic
        case .book:
            return Self.catalogKind(of: item) == .book
        }
    }

    private static func sortDate(_ item: FavoriteContentItem) -> Date? {
        return item.favoritedAt ?? item.updatedAt
    }

    // MARK: - 来源

    func source(for item: FavoriteContentItem) -> Source? {
        if let currentSource: Source = self.sources.first(where: { source in
            source.id == item.sourceID
        }) {
            return currentSource
        }

        return item.fallbackSource()
    }

    func sourceState(for item: FavoriteContentItem) -> SourceState {
        if let currentSource: Source = self.sources.first(where: { source in
            source.id == item.sourceID
        }) {
            return currentSource.accessState == .lockedBySlotLimit ? .paused : .available
        }
        return item.fallbackSource() == nil ? .unknown : .deleted
    }

    func sourceName(for item: FavoriteContentItem) -> String {
        return self.source(for: item)?.name
            ?? item.sourceSnapshot?.name
            ?? NSLocalizedString("favorites_unknown_source", comment: "")
    }

    /// 封面请求沿用来源规则里的图片请求配置（与库页同一份），按来源缓存，不在每次绘制时重新校验规则。
    func imageRequestConfig(for item: FavoriteContentItem) -> RequestConfig? {
        return self.imageRequestConfigs[item.sourceID]
    }

    // MARK: - 取消收藏与撤销

    /// 取消收藏不弹确认（2026-10-02 用户裁定），取消后底部给出可撤销提示。
    @MainActor
    func unfavorite(_ item: FavoriteContentItem) async {
        do {
            let snapshot: FavoritesPersistenceSnapshot = try await self.persistenceCoordinator.remove(item: item)
            self.apply(snapshot)
            self.changeRevision += 1
            self.showUndo(for: item)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// 撤销：按原收藏时间恢复，条目回到原来的日期分组。
    @MainActor
    func undoUnfavorite() async {
        guard let item: FavoriteContentItem = self.undoableItem else {
            return
        }
        self.dismissUndo()
        do {
            let snapshot: FavoritesPersistenceSnapshot = try await self.persistenceCoordinator.restore(item: item)
            self.apply(snapshot)
            self.changeRevision += 1
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func dismissUndo() {
        self.undoDismissTask?.cancel()
        self.undoDismissTask = nil
        self.undoableItem = nil
    }

    private func showUndo(for item: FavoriteContentItem) {
        self.undoDismissTask?.cancel()
        self.undoableItem = item
        self.undoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.undoDuration)
            guard Task.isCancelled == false,
                  let self = self,
                  self.undoableItem?.identity == item.identity else {
                return
            }
            self.undoableItem = nil
        }
    }

    // MARK: - 快照

    private func apply(_ snapshot: FavoritesPersistenceSnapshot) {
        self.sources = snapshot.sources
        self.favoriteItems = snapshot.items

        var configs: [String: RequestConfig] = [:]
        for item in snapshot.items where configs[item.sourceID] == nil {
            guard let source: Source = self.source(for: item),
                  let config: RequestConfig = self.resolveLibrarySourcePresentationUseCase.imageRequestConfig(
                    for: source,
                    listTab: nil
                  ) else {
                continue
            }
            configs[item.sourceID] = config
        }
        self.imageRequestConfigs = configs
    }
}
