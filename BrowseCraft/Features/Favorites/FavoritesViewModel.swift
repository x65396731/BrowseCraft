import Observation
@preconcurrency import BrowseCraftCore
import BrowseCraftDomain
import Foundation

// 中文注释：FavoritesViewModel 负责收藏页数据加载、类型筛选、按天分组、来源状态、取消收藏与选择模式下的批量取消
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
    /// 本页每改动一次收藏集合就加一；宿主据此让库页刷新封面上的爱心状态。
    private(set) var changeRevision: Int = 0
    /// 选择模式（设计文档 2.5）：勾选的条目只在当前筛选范围内。
    private(set) var isSelecting: Bool = false
    private(set) var selectedIdentities: Set<FavoriteItemIdentity> = []

    @ObservationIgnored private var imageRequestConfigs: [String: RequestConfig] = [:]

    private let persistenceCoordinator: FavoritesPersistenceCoordinator
    private let resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase
    private let now: () -> Date

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

    /// 埋点的内容类型：收藏条目分不出有声书，书一律报 book。
    static func analyticsKind(of item: FavoriteContentItem) -> AnalyticsContentKind {
        switch Self.catalogKind(of: item) {
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

    // MARK: - 取消收藏

    /// 单条取消收藏（左滑、长按）：不弹确认，也没有撤销（2026-10-17 用户裁定）。返回是否成功，页面据此上报埋点。
    @MainActor
    @discardableResult
    func unfavorite(_ item: FavoriteContentItem) async -> Bool {
        do {
            let snapshot: FavoritesPersistenceSnapshot = try await self.persistenceCoordinator.remove(item: item)
            self.apply(snapshot)
            self.changeRevision += 1
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - 选择与批量取消收藏（设计文档 2.5）

    /// 当前筛选下、按显示顺序排的条目；「全选」只作用于它们。
    var visibleItems: [FavoriteContentItem] {
        return self.dayGroups.flatMap(\.items)
    }

    var selectedCount: Int {
        return self.selectedIdentities.count
    }

    var isAllVisibleSelected: Bool {
        let visible: [FavoriteContentItem] = self.visibleItems
        return visible.isEmpty == false && visible.allSatisfy { self.selectedIdentities.contains($0.identity) }
    }

    func isSelected(_ item: FavoriteContentItem) -> Bool {
        return self.selectedIdentities.contains(item.identity)
    }

    /// 进入选择模式；从长按菜单「选择多项」进来时预先选中那一条。
    func beginSelection(preselecting item: FavoriteContentItem? = nil) {
        self.isSelecting = true
        self.selectedIdentities = item.map { [$0.identity] } ?? []
    }

    func endSelection() {
        self.isSelecting = false
        self.selectedIdentities = []
    }

    func toggleSelection(_ item: FavoriteContentItem) {
        if self.selectedIdentities.contains(item.identity) {
            self.selectedIdentities.remove(item.identity)
        } else {
            self.selectedIdentities.insert(item.identity)
        }
    }

    /// 「全选 / 全不选」：全部选中时清空，否则选中当前筛选下的全部条目。
    func toggleSelectAll() {
        if self.isAllVisibleSelected {
            self.selectedIdentities = []
        } else {
            self.selectedIdentities = Set(self.visibleItems.map(\.identity))
        }
    }

    /// 确认框里点了「取消收藏」：一次取消所选条目，然后退出选择模式。返回取消了几条（失败或没选为 0），页面据此上报埋点。
    @MainActor
    @discardableResult
    func unfavoriteSelected() async -> Int {
        let items: [FavoriteContentItem] = self.visibleItems.filter { self.selectedIdentities.contains($0.identity) }
        guard items.isEmpty == false else {
            return 0
        }
        do {
            let snapshot: FavoritesPersistenceSnapshot = try await self.persistenceCoordinator.remove(items: items)
            self.apply(snapshot)
            self.changeRevision += 1
            self.endSelection()
            return items.count
        } catch {
            self.errorMessage = error.localizedDescription
            await self.load()
            return 0
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

        // 中文注释：数据变了（同步、别处取消收藏）时，勾选只留还在当前筛选里的条目；收藏变空就退出选择模式。
        if self.isSelecting {
            if self.favoriteItems.isEmpty {
                self.endSelection()
            } else {
                self.selectedIdentities.formIntersection(self.visibleItems.map(\.identity))
            }
        }
    }
}
