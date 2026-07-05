import Foundation

// 中文注释：Source/Favorite/History 暂时使用会话内存实现；列表内容通过 SourceSelectionStore 快照传递。
final class InMemorySourceRepository: SourceRepository {
    private var sourcesByID: [String: Source] = [:]
    private var sourceIDs: [String] = []

    func fetchSources() throws -> [Source] {
        return self.sourceIDs.compactMap { id in
            return self.sourcesByID[id]
        }
    }

    func saveSource(_ source: Source) throws {
        if self.sourcesByID[source.id] == nil {
            self.sourceIDs.append(source.id)
        }

        self.sourcesByID[source.id] = source
    }

    func deleteSource(id: String) throws {
        self.sourcesByID[id] = nil
        self.sourceIDs.removeAll { existingID in
            return existingID == id
        }
    }
}

final class InMemoryFavoriteRepository: FavoriteRepository {
    private var favoriteItemIDs: Set<String> = []

    func fetchFavoriteItemIDs() throws -> Set<String> {
        return self.favoriteItemIDs
    }

    func setFavorite(itemId: String, isFavorite: Bool) throws {
        if isFavorite {
            self.favoriteItemIDs.insert(itemId)
        } else {
            self.favoriteItemIDs.remove(itemId)
        }
    }
}

final class InMemoryHistoryRepository: HistoryRepository {
    private var historiesByItemID: [String: ReadingHistory] = [:]

    func fetchReadingHistory() throws -> [ReadingHistory] {
        return self.historiesByItemID.values.sorted { lhs, rhs in
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    func saveReadingHistory(_ history: ReadingHistory) throws {
        self.historiesByItemID[history.itemId] = history
    }
}
