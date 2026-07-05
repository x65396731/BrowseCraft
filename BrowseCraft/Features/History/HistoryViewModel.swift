import Combine
import Foundation

// 中文注释：HistoryViewModel.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：HistoryViewModel 是 final class，负责本模块中的对应职责。
final class HistoryViewModel: ObservableObject {
    @Published private(set) var readingHistoryEntries: [ReadingHistoryEntry] = []
    @Published var errorMessage: String?

    private let loadReadingHistoryEntriesUseCase: LoadReadingHistoryEntriesUseCase
    private let userID: String

    init(
        loadReadingHistoryEntriesUseCase: LoadReadingHistoryEntriesUseCase,
        userID: String = AppUser.localDefaultID
    ) {
        self.loadReadingHistoryEntriesUseCase = loadReadingHistoryEntriesUseCase
        self.userID = userID
    }

    @MainActor
    /// 中文注释：load 方法封装当前类型的一段业务或界面行为。
    func load() {
        do {
            self.readingHistoryEntries = try self.loadReadingHistoryEntriesUseCase.execute(userID: self.userID)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
