import Foundation

// 中文注释：BookFeatureFactory 装配本地书书架与阅读器：Readium 适配器、文件存储、三个 GRDB 仓储。
// 本地书不是 Source，不经 SourceRuntimeComposition。

struct BookFeatureFactory {
    private let database: AppDatabase
    private let activeAppUser: any ActiveAppUserProviding
    private let fileStore: any BookFileStoring
    private let inspector: any BookFileInspecting
    private let opener: any BookPublicationOpening

    init(database: AppDatabase, activeAppUser: any ActiveAppUserProviding) {
        self.database = database
        self.activeAppUser = activeAppUser
        // 中文注释：Application Support 拿不到时退回临时目录，只影响本地书，不影响其它功能。
        self.fileStore = (try? FileSystemBookFileStore.makeDefault())
            ?? FileSystemBookFileStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("Books", isDirectory: true))
        self.inspector = ReadiumBookFileInspector()
        self.opener = ReadiumBookPublicationOpener()
    }

    @MainActor
    func makeShelfViewModel() -> BookShelfViewModel {
        let books: GRDBLocalBookRepository = GRDBLocalBookRepository(database: self.database)
        let progress: GRDBBookReadingProgressRepository = GRDBBookReadingProgressRepository(database: self.database)
        return BookShelfViewModel(
            listUseCase: ListLocalBooksUseCase(repository: books, progressRepository: progress),
            importUseCase: ImportLocalBookUseCase(
                inspector: self.inspector,
                fileStore: self.fileStore,
                opener: self.opener,
                repository: books
            ),
            deleteUseCase: DeleteLocalBookUseCase(repository: books, fileStore: self.fileStore),
            fileStore: self.fileStore,
            activeAppUser: self.activeAppUser
        )
    }

    @MainActor
    func makeReaderViewModel(book: LocalBook) -> BookReaderViewModel {
        let books: GRDBLocalBookRepository = GRDBLocalBookRepository(database: self.database)
        let progress: GRDBBookReadingProgressRepository = GRDBBookReadingProgressRepository(database: self.database)
        let bookmarks: GRDBBookBookmarkRepository = GRDBBookBookmarkRepository(database: self.database)
        return BookReaderViewModel(
            book: book,
            userID: self.activeAppUser.currentUserID.uuidString,
            openUseCase: OpenLocalBookUseCase(
                repository: books,
                progressRepository: progress,
                fileStore: self.fileStore,
                opener: self.opener
            ),
            saveProgressUseCase: SaveBookReadingProgressUseCase(progressRepository: progress),
            addBookmarkUseCase: AddBookBookmarkUseCase(repository: bookmarks),
            listBookmarksUseCase: ListBookBookmarksUseCase(repository: bookmarks),
            removeBookmarkUseCase: RemoveBookBookmarkUseCase(repository: bookmarks)
        )
    }
}
