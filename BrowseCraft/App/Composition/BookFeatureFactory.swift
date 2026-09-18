import BrowseCraftDomain
import BrowseCraftRuntime
import Foundation

// 中文注释：BookFeatureFactory 装配读书 kind 的页面：本地书（书架、阅读器）与站点书（详情、阅读器）。
// 两者共用阅读器、进度与书签；站点书的作品标识由 sourceID + 作品地址派生（SiteBookIdentity）。

struct BookFeatureFactory {
    private let database: AppDatabase
    private let activeAppUser: any ActiveAppUserProviding
    private let runtimeResolver: any SourceRuntimeResolving
    private let fileStore: any BookFileStoring
    private let inspector: any BookFileInspecting
    private let opener: any BookPublicationOpening
    /// 中文注释：站点书出版物缓存——详情页与阅读器共用，开书不再把作品页 + 目录页各取两遍（2026-09-15 真机日志）。
    private let publicationCache: BookPublicationCache = BookPublicationCache()

    init(database: AppDatabase, activeAppUser: any ActiveAppUserProviding, runtimeResolver: any SourceRuntimeResolving) {
        self.database = database
        self.activeAppUser = activeAppUser
        self.runtimeResolver = runtimeResolver
        // 中文注释：Application Support 拿不到时退回临时目录，只影响本地书，不影响其它功能。
        self.fileStore = (try? FileSystemBookFileStore.makeDefault())
            ?? FileSystemBookFileStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("Books", isDirectory: true))
        self.inspector = ReadiumBookFileInspector()
        self.opener = ReadiumBookPublicationOpener()
    }

    private var userID: String {
        return self.activeAppUser.currentUserID.uuidString
    }

    @MainActor
    func makeShelfViewModel() -> BookShelfViewModel {
        let books: GRDBLocalBookRepository = GRDBLocalBookRepository(database: self.database)
        let progress: GRDBBookReadingProgressRepository = GRDBBookReadingProgressRepository(database: self.database)
        let bookmarks: GRDBBookBookmarkRepository = GRDBBookBookmarkRepository(database: self.database)
        return BookShelfViewModel(
            listUseCase: ListLocalBooksUseCase(repository: books, progressRepository: progress),
            importUseCase: ImportLocalBookUseCase(
                inspector: self.inspector,
                fileStore: self.fileStore,
                opener: self.opener,
                repository: books
            ),
            deleteUseCase: DeleteLocalBookUseCase(
                repository: books,
                progressRepository: progress,
                bookmarkRepository: bookmarks,
                fileStore: self.fileStore
            ),
            fileStore: self.fileStore,
            activeAppUser: self.activeAppUser
        )
    }

    @MainActor
    func makeReaderViewModel(book: LocalBook) -> BookReaderViewModel {
        return self.makeReaderViewModel(subject: .local(book))
    }

    @MainActor
    func makeSiteDetailViewModel(item: ContentItem, source: Source) -> BookSiteDetailViewModel {
        return BookSiteDetailViewModel(
            item: item,
            source: source,
            loadPublicationUseCase: LoadBookPublicationUseCase(runtimeResolver: self.runtimeResolver, cache: self.publicationCache),
            loadProgressUseCase: LoadBookReadingProgressUseCase(progressRepository: GRDBBookReadingProgressRepository(database: self.database)),
            userID: self.userID
        )
    }

    @MainActor
    func makeSiteReaderViewModel(selection: SiteBookChapterSelection) -> BookReaderViewModel {
        return self.makeReaderViewModel(subject: .site(selection))
    }

    @MainActor
    private func makeReaderViewModel(subject: BookReaderSubject) -> BookReaderViewModel {
        let books: GRDBLocalBookRepository = GRDBLocalBookRepository(database: self.database)
        let progress: GRDBBookReadingProgressRepository = GRDBBookReadingProgressRepository(database: self.database)
        let bookmarks: GRDBBookBookmarkRepository = GRDBBookBookmarkRepository(database: self.database)
        return BookReaderViewModel(
            subject: subject,
            userID: self.userID,
            openLocalUseCase: OpenLocalBookUseCase(
                repository: books,
                progressRepository: progress,
                fileStore: self.fileStore,
                opener: self.opener
            ),
            loadSitePublicationUseCase: LoadBookPublicationUseCase(runtimeResolver: self.runtimeResolver, cache: self.publicationCache),
            sitePublicationBuilder: ReadiumSitePublicationBuilderAdapter(),
            loadProgressUseCase: LoadBookReadingProgressUseCase(progressRepository: progress),
            saveProgressUseCase: SaveBookReadingProgressUseCase(progressRepository: progress),
            addBookmarkUseCase: AddBookBookmarkUseCase(repository: bookmarks),
            listBookmarksUseCase: ListBookBookmarksUseCase(repository: bookmarks),
            removeBookmarkUseCase: RemoveBookBookmarkUseCase(repository: bookmarks),
            saveHistoryUseCase: SaveBookReadingHistoryUseCase(repository: GRDBBookReadingHistoryRepository(database: self.database))
        )
    }
}
