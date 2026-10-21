import BrowseCraftDomain

struct HistoryFeatureFactory {
    private let database: AppDatabase
    private let activeAppUser: any ActiveAppUserProviding
    private let sourceRepository: SourceRepository
    private let videoPlayerViewModelFactory: @MainActor (VideoWatchHistory, Source) -> VideoPlayerViewModel

    init(
        database: AppDatabase,
        activeAppUser: any ActiveAppUserProviding,
        sourceRepository: SourceRepository,
        videoPlayerViewModelFactory: @escaping @MainActor (VideoWatchHistory, Source) -> VideoPlayerViewModel
    ) {
        self.database = database
        self.activeAppUser = activeAppUser
        self.sourceRepository = sourceRepository
        self.videoPlayerViewModelFactory = videoPlayerViewModelFactory
    }

    @MainActor
    func makeViewModel() -> HistoryViewModel {
        let comicRepository: ComicChapterHistoryRepository = GRDBComicChapterHistoryRepository(
            database: self.database
        )
        let videoRepository: VideoWatchHistoryRepository = GRDBVideoWatchHistoryRepository(
            database: self.database
        )
        let bookRepository: BookReadingHistoryRepository = GRDBBookReadingHistoryRepository(
            database: self.database
        )
        let temporaryRepository: TemporaryResourceHistoryRepository = GRDBTemporaryResourceHistoryRepository(
            database: self.database
        )

        let persistenceCoordinator: HistoryPersistenceCoordinator = HistoryPersistenceCoordinator(
            loadReadingHistoryEntriesUseCase: LoadReadingHistoryEntriesUseCase(
                comicRepository: comicRepository,
                videoRepository: videoRepository,
                bookRepository: bookRepository,
                temporaryRepository: temporaryRepository
            ),
            deleteReadingHistoryEntryUseCase: DeleteReadingHistoryEntryUseCase(
                comicRepository: comicRepository,
                videoRepository: videoRepository,
                bookRepository: bookRepository,
                temporaryRepository: temporaryRepository
            ),
            reconcileSourceSlotAssignmentsUseCase:
                ReconcileSourceSlotAssignmentsUseCase(
                sourceRepository: self.sourceRepository
                )
        )

        return HistoryViewModel(
            persistenceCoordinator: persistenceCoordinator,
            activeAppUser: self.activeAppUser,
            videoPlayerViewModelFactory: self.videoPlayerViewModelFactory
        )
    }
}
