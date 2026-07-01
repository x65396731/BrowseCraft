import Foundation

/// Records that the user opened an item.
///
/// This gives us a small first version of reading history before the full comic
/// reader exists.
struct RecordOpenItemUseCase {
    private let historyRepository: HistoryRepository

    init(historyRepository: HistoryRepository) {
        self.historyRepository = historyRepository
    }

    func execute(itemId: String) throws {
        let history: ReadingHistory = ReadingHistory(
            itemId: itemId,
            chapterId: nil,
            pageIndex: 0,
            updatedAt: Date()
        )

        try self.historyRepository.saveReadingHistory(history)
    }
}

