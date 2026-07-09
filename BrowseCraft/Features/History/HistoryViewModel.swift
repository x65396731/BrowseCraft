import Combine
import Foundation

// 中文注释：HistoryViewModel.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：HistoryViewModel 是 final class，负责本模块中的对应职责。
final class HistoryViewModel: ObservableObject {
    @Published private(set) var readingHistoryEntries: [ReadingHistoryEntry] = []
    @Published private(set) var sources: [Source] = []
    @Published var videoPlaybackRoute: VideoPlaybackRoute?
    @Published var errorMessage: String?

    private let loadReadingHistoryEntriesUseCase: LoadReadingHistoryEntriesUseCase
    private let deleteReadingHistoryEntryUseCase: DeleteReadingHistoryEntryUseCase
    private let loadSourcesUseCase: LoadSourcesUseCase
    private let userID: String
    private let videoPlayerViewModelFactory: @MainActor (VideoWatchHistory, Source) -> VideoPlayerViewModel

    init(
        loadReadingHistoryEntriesUseCase: LoadReadingHistoryEntriesUseCase,
        deleteReadingHistoryEntryUseCase: DeleteReadingHistoryEntryUseCase,
        loadSourcesUseCase: LoadSourcesUseCase,
        userID: String = AppUser.localDefaultID,
        videoPlayerViewModelFactory: @escaping @MainActor (VideoWatchHistory, Source) -> VideoPlayerViewModel
    ) {
        self.loadReadingHistoryEntriesUseCase = loadReadingHistoryEntriesUseCase
        self.deleteReadingHistoryEntryUseCase = deleteReadingHistoryEntryUseCase
        self.loadSourcesUseCase = loadSourcesUseCase
        self.userID = userID
        self.videoPlayerViewModelFactory = videoPlayerViewModelFactory
    }

    @MainActor
    /// 中文注释：load 方法封装当前类型的一段业务或界面行为。
    func load() {
        do {
            self.sources = try self.loadSourcesUseCase.execute()
            self.readingHistoryEntries = self.deduplicatedVideoEntries(
                try self.loadReadingHistoryEntriesUseCase.execute(userID: self.userID)
            )
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func source(for sourceID: String) -> Source? {
        return self.sources.first { source in
            return source.id == sourceID
        }
    }

    @MainActor
    func openVideoHistory(_ history: VideoWatchHistory) {
        guard let source: Source = self.source(for: history.sourceID) else {
            self.errorMessage = "Missing video source."
            return
        }

        let viewModel: VideoPlayerViewModel = self.videoPlayerViewModelFactory(history, source)
        self.videoPlaybackRoute = VideoPlaybackRoute(
            id: history.id,
            viewModel: viewModel
        )
    }

    @MainActor
    func deleteHistoryEntries(at offsets: IndexSet) {
        let entriesToDelete: [ReadingHistoryEntry] = offsets.compactMap { index in
            guard self.readingHistoryEntries.indices.contains(index) else {
                return nil
            }

            return self.readingHistoryEntries[index]
        }

        do {
            for entry: ReadingHistoryEntry in entriesToDelete {
                try self.deleteReadingHistoryEntryUseCase.execute(entry)
            }
            for index: Int in offsets.sorted(by: >) where self.readingHistoryEntries.indices.contains(index) {
                self.readingHistoryEntries.remove(at: index)
            }
        } catch {
            self.errorMessage = error.localizedDescription
            self.load()
        }
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
}
