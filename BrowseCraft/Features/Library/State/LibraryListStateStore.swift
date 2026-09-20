import BrowseCraftCore
import BrowseCraftDomain
import Foundation

struct LibraryListStateKey: Hashable, CustomStringConvertible {
    let sourceID: String
    let pageID: String?
    let tabID: String?
    let sectionID: String?
    let sectionRole: String?
    let listRuleID: String?

    var description: String {
        return [
            self.sourceID,
            self.pageID ?? "nil",
            self.tabID ?? "nil",
            self.sectionID ?? "nil",
            self.sectionRole ?? "nil",
            self.listRuleID ?? "nil"
        ].joined(separator: "::")
    }
}

enum LibraryListPageOutcome: String {
    case loaded
    case empty
    case duplicateOnly
}

struct LibraryListPageState {
    let pageNumber: Int
    /// 中文注释：items 保留源站当前页的原始映射结果，便于识别重复页和诊断规则分页。
    let items: [ContentItem]
    /// 中文注释：visibleItems 只保存当前页相对前序页面真正新增的内容。
    let visibleItems: [ContentItem]
    let duplicateCount: Int
    let nextPage: Int?
    let outcome: LibraryListPageOutcome
}

struct LibraryListCacheEntry {
    let sourceID: String
    let context: ListContext?
    private(set) var pageOrder: [Int]
    private(set) var pages: [Int: LibraryListPageState]

    var items: [ContentItem] {
        return self.pageOrder
            .compactMap { self.pages[$0] }
            .flatMap(\.visibleItems)
    }

    var currentPage: Int {
        return self.pageOrder.reversed().first { pageNumber in
            return self.pages[pageNumber]?.visibleItems.isEmpty == false
        } ?? self.pageOrder.first ?? 1
    }

    var nextPage: Int? {
        guard let lastPageNumber: Int = self.pageOrder.last,
              let lastPageState: LibraryListPageState = self.pages[lastPageNumber] else {
            return nil
        }
        return lastPageState.nextPage
    }

    var snapshotPages: [SourceLibraryPageSnapshot] {
        return self.pageOrder.compactMap { pageNumber in
            guard let page: LibraryListPageState = self.pages[pageNumber] else {
                return nil
            }
            return SourceLibraryPageSnapshot(
                pageNumber: page.pageNumber,
                items: page.items,
                nextPage: page.nextPage
            )
        }
    }

    init(
        sourceID: String,
        context: ListContext?,
        pages: [SourceLibraryPageSnapshot]
    ) {
        self.sourceID = sourceID
        self.context = context
        self.pageOrder = []
        self.pages = [:]
        for page in pages.sorted(by: { lhs, rhs in
            return lhs.pageNumber < rhs.pageNumber
        }) {
            self.storePage(
                pageNumber: page.pageNumber,
                items: page.items,
                nextPage: page.nextPage
            )
        }
    }

    mutating func storePage(
        pageNumber: Int,
        items: [ContentItem],
        nextPage: Int?
    ) {
        let existingItemIDs: Set<String> = Set(
            self.pageOrder
                .filter { $0 != pageNumber }
                .compactMap { self.pages[$0] }
                .flatMap(\.visibleItems)
                .map(\.id)
        )
        var seenItemIDs: Set<String> = existingItemIDs
        let visibleItems: [ContentItem] = items.filter { item in
            return seenItemIDs.insert(item.id).inserted
        }
        let outcome: LibraryListPageOutcome
        if items.isEmpty {
            outcome = .empty
        } else if visibleItems.isEmpty {
            outcome = .duplicateOnly
        } else {
            outcome = .loaded
        }

        if self.pages[pageNumber] == nil {
            self.pageOrder.append(pageNumber)
            self.pageOrder.sort()
        }
        self.pages[pageNumber] = LibraryListPageState(
            pageNumber: pageNumber,
            items: items,
            visibleItems: visibleItems,
            duplicateCount: items.count - visibleItems.count,
            // 中文注释：非空响应若没有任何新 ID，说明分页已循环回历史数据，必须终止自动翻页。
            nextPage: outcome == .duplicateOnly ? nil : nextPage,
            outcome: outcome
        )
    }
}

struct LibraryListStateStore {
    private var confirmedEmptyTabKeys: Set<String> = []
    private var errorMessages: [LibraryListStateKey: String] = [:]
    private var cache: [LibraryListStateKey: LibraryListCacheEntry] = [:]
    /// 中文注释：每个 tab 各自的「上次真取到数据的时刻」。缓存本来就按 tab 分开存，
    /// 缺的只是新鲜度——没有它就没法回答「切回这个 tab 要不要重取」，
    /// 于是切 tab 只能无条件刷一次，缓存命中了也白命中（2026-09-20 真机日志）。
    private var refreshedAt: [LibraryListStateKey: Date] = [:]

    /// 一个 tab 的数据最多沿用多久；超过就在切回来时重取一次。
    ///
    /// 中文注释：取 5 分钟——来回切 tab 不再重新加载，离开久了回来仍然能看到新内容。
    /// 下拉刷新与「刷新」动作不看它，任何时候都强制重取。
    static let cacheFreshnessSeconds: TimeInterval = 300

    func visibleTabs(_ tabs: [ListTabRule], source: Source?) -> [ListTabRule] {
        guard source?.configuration.kind == .video,
              let sourceID: String = source?.id else {
            return tabs
        }

        let visibleTabs: [ListTabRule] = tabs.filter { tab in
            return self.confirmedEmptyTabKeys.contains(
                self.tabKey(sourceID: sourceID, tabID: tab.id)
            ) == false
        }
        return visibleTabs.isEmpty ? tabs : visibleTabs
    }

    mutating func updateConfirmedEmptyTab(
        sourceID: String,
        tabID: String?,
        itemCount: Int
    ) -> Bool {
        guard let tabID: String else {
            return false
        }

        let key: String = self.tabKey(sourceID: sourceID, tabID: tabID)
        let wasHidden: Bool = self.confirmedEmptyTabKeys.contains(key)
        if itemCount == 0 {
            self.confirmedEmptyTabKeys.insert(key)
        } else {
            self.confirmedEmptyTabKeys.remove(key)
        }
        return wasHidden != self.confirmedEmptyTabKeys.contains(key)
    }

    func stateKey(sourceID: String, context: ListContext?) -> LibraryListStateKey {
        return LibraryListStateKey(
            sourceID: sourceID,
            pageID: context?.pageId,
            tabID: context?.tabId,
            sectionID: context?.sectionId,
            sectionRole: context?.sectionRole?.rawValue,
            listRuleID: context?.listRuleId
        )
    }

    func errorMessage(sourceID: String, context: ListContext?) -> String? {
        return self.errorMessages[self.stateKey(sourceID: sourceID, context: context)]
    }

    mutating func setErrorMessage(
        _ message: String?,
        sourceID: String,
        context: ListContext?
    ) {
        let key: LibraryListStateKey = self.stateKey(sourceID: sourceID, context: context)
        if let message: String {
            self.errorMessages[key] = message
        } else {
            self.errorMessages.removeValue(forKey: key)
        }
    }

    func cachedEntry(sourceID: String, context: ListContext?) -> LibraryListCacheEntry? {
        return self.cache[self.stateKey(sourceID: sourceID, context: context)]
    }

    /// 这个 tab 的缓存还新鲜吗——新鲜就不必在切过去时重取。
    ///
    /// 中文注释：没有取数记录时一律返回 false（宁可多取一次，也不给用户看一份来路不明的旧数据）。
    func isCacheFresh(sourceID: String, context: ListContext?, now: Date) -> Bool {
        let key: LibraryListStateKey = self.stateKey(sourceID: sourceID, context: context)
        guard self.cache[key] != nil,
              let refreshedAt: Date = self.refreshedAt[key] else {
            return false
        }
        return now.timeIntervalSince(refreshedAt) < Self.cacheFreshnessSeconds
    }

    /// 记下这个 tab 刚取到数据的时刻。只有**真从站点取回**才调用，读缓存不算。
    mutating func markRefreshed(sourceID: String, context: ListContext?, at: Date) {
        self.refreshedAt[self.stateKey(sourceID: sourceID, context: context)] = at
    }

    @discardableResult
    mutating func replaceWithFirstPage(
        source: Source,
        items: [ContentItem],
        nextPage: Int?,
        context: ListContext?
    ) -> LibraryListCacheEntry {
        let entry: LibraryListCacheEntry = LibraryListCacheEntry(
            sourceID: source.id,
            context: context,
            pages: [
                SourceLibraryPageSnapshot(
                    pageNumber: 1,
                    items: items,
                    nextPage: nextPage
                )
            ]
        )
        self.cache[self.stateKey(sourceID: source.id, context: context)] = entry
        return entry
    }

    @discardableResult
    mutating func storePage(
        source: Source,
        pageNumber: Int,
        items: [ContentItem],
        nextPage: Int?,
        context: ListContext?
    ) -> LibraryListCacheEntry {
        let key: LibraryListStateKey = self.stateKey(sourceID: source.id, context: context)
        var entry: LibraryListCacheEntry = self.cache[key] ?? LibraryListCacheEntry(
            sourceID: source.id,
            context: context,
            pages: []
        )
        entry.storePage(
            pageNumber: pageNumber,
            items: items,
            nextPage: nextPage
        )
        self.cache[key] = entry
        return entry
    }

    @discardableResult
    mutating func cacheSnapshot(
        source: Source,
        pages: [SourceLibraryPageSnapshot],
        context: ListContext?
    ) -> LibraryListCacheEntry {
        let entry: LibraryListCacheEntry = LibraryListCacheEntry(
            sourceID: source.id,
            context: context,
            pages: pages
        )
        self.cache[self.stateKey(sourceID: source.id, context: context)] = entry
        return entry
    }

    private func tabKey(sourceID: String, tabID: String) -> String {
        return "\(sourceID)::\(tabID)"
    }
}
