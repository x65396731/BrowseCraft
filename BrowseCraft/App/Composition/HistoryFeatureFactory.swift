struct HistoryFeatureFactory {
    private let database: AppDatabase
    private let sourceRepository: SourceRepository
    private let videoPlayerViewModelFactory: @MainActor (VideoWatchHistory, Source) -> VideoPlayerViewModel

    init(
        database: AppDatabase,
        sourceRepository: SourceRepository,
        videoPlayerViewModelFactory: @escaping @MainActor (VideoWatchHistory, Source) -> VideoPlayerViewModel
    ) {
        self.database = database
        self.sourceRepository = sourceRepository
        self.videoPlayerViewModelFactory = videoPlayerViewModelFactory
    }

    func makeViewModel() -> HistoryViewModel {
        let rssRepository: RSSReadingHistoryRepository = GRDBRSSReadingHistoryRepository(
            database: self.database
        )
        let comicRepository: ComicChapterHistoryRepository = GRDBComicChapterHistoryRepository(
            database: self.database
        )
        let videoRepository: VideoWatchHistoryRepository = GRDBVideoWatchHistoryRepository(
            database: self.database
        )
        let temporaryRepository: TemporaryResourceHistoryRepository = GRDBTemporaryResourceHistoryRepository(
            database: self.database
        )

        return HistoryViewModel(
            loadReadingHistoryEntriesUseCase: LoadReadingHistoryEntriesUseCase(
                rssRepository: rssRepository,
                comicRepository: comicRepository,
                videoRepository: videoRepository,
                temporaryRepository: temporaryRepository
            ),
            deleteReadingHistoryEntryUseCase: DeleteReadingHistoryEntryUseCase(
                rssRepository: rssRepository,
                comicRepository: comicRepository,
                videoRepository: videoRepository,
                temporaryRepository: temporaryRepository
            ),
            loadSourcesUseCase: LoadSourcesUseCase(
                sourceRepository: self.sourceRepository
            ),
            videoPlayerViewModelFactory: self.videoPlayerViewModelFactory
        )
    }
}
