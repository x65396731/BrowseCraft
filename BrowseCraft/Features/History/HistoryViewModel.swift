import Combine
import Foundation

// 中文注释：HistoryViewModel.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：HistoryViewModel 是 final class，负责本模块中的对应职责。
final class HistoryViewModel: ObservableObject {
    @Published private(set) var readingHistoryEntries: [ReadingHistoryEntry] = []
    @Published private(set) var sources: [Source] = []
    @Published var errorMessage: String?

    private let loadReadingHistoryEntriesUseCase: LoadReadingHistoryEntriesUseCase
    private let loadSourcesUseCase: LoadSourcesUseCase
    private let userID: String

    init(
        loadReadingHistoryEntriesUseCase: LoadReadingHistoryEntriesUseCase,
        loadSourcesUseCase: LoadSourcesUseCase,
        userID: String = AppUser.localDefaultID
    ) {
        self.loadReadingHistoryEntriesUseCase = loadReadingHistoryEntriesUseCase
        self.loadSourcesUseCase = loadSourcesUseCase
        self.userID = userID
    }

    @MainActor
    /// 中文注释：load 方法封装当前类型的一段业务或界面行为。
    func load() {
        do {
            self.sources = try self.loadSourcesUseCase.execute()
            self.readingHistoryEntries = try self.loadReadingHistoryEntriesUseCase.execute(userID: self.userID)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func source(for sourceID: String) -> Source? {
        return self.sources.first { source in
            return source.id == sourceID
        }
    }
}
