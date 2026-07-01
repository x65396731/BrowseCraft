import Foundation

/// Domain-facing storage API for reading history.
protocol HistoryRepository {
    func fetchReadingHistory() throws -> [ReadingHistory]
    func saveReadingHistory(_ history: ReadingHistory) throws
}

