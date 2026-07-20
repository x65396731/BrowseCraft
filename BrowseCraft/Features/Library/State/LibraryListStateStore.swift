import BrowseCraftCore
import Foundation

struct LibraryListCacheEntry {
    let sourceID: String
    let context: ListContext?
    let items: [ContentItem]
}

struct LibraryListStateStore {
    private var confirmedEmptyTabKeys: Set<String> = []
    private var errorMessages: [String: String] = [:]
    private var cache: [String: LibraryListCacheEntry] = [:]

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

    func stateKey(sourceID: String, context: ListContext?) -> String {
        return [
            sourceID,
            context?.pageId ?? "nil",
            context?.tabId ?? "nil",
            context?.sectionId ?? "nil",
            context?.listRuleId ?? "nil"
        ].joined(separator: "::")
    }

    func errorMessage(sourceID: String, context: ListContext?) -> String? {
        return self.errorMessages[self.stateKey(sourceID: sourceID, context: context)]
    }

    mutating func setErrorMessage(
        _ message: String?,
        sourceID: String,
        context: ListContext?
    ) {
        let key: String = self.stateKey(sourceID: sourceID, context: context)
        if let message: String {
            self.errorMessages[key] = message
        } else {
            self.errorMessages.removeValue(forKey: key)
        }
    }

    func cachedEntry(sourceID: String, context: ListContext?) -> LibraryListCacheEntry? {
        return self.cache[self.stateKey(sourceID: sourceID, context: context)]
    }

    mutating func cacheItems(
        source: Source,
        items: [ContentItem],
        context: ListContext?
    ) {
        self.cache[self.stateKey(sourceID: source.id, context: context)] = LibraryListCacheEntry(
            sourceID: source.id,
            context: context,
            items: items
        )
    }

    private func tabKey(sourceID: String, tabID: String) -> String {
        return "\(sourceID)::\(tabID)"
    }
}
