import Foundation

/// AppContainer is not a screen.
///
/// It is the one place where we build concrete dependencies:
/// GRDB repositories, Alamofire HTTP client, SwiftSoup parser, and use cases.
final class AppContainer {
    private let database: AppDatabase
    private let sourceRepository: SourceRepository
    private let contentRepository: ContentRepository
    private let favoriteRepository: FavoriteRepository
    private let historyRepository: HistoryRepository
    private let httpClient: HTTPClient
    private let urlResolver: URLResolvingService
    private let ruleParser: RuleParsingService

    init() {
        do {
            let database: AppDatabase = try AppDatabase()
            let urlResolver: URLResolvingService = URLResolvingService()

            self.database = database
            self.sourceRepository = GRDBSourceRepository(database: database)
            self.contentRepository = GRDBContentRepository(database: database)
            self.favoriteRepository = GRDBFavoriteRepository(database: database)
            self.historyRepository = GRDBHistoryRepository(database: database)
            self.httpClient = AlamofireHTTPClient()
            self.urlResolver = urlResolver
            self.ruleParser = SwiftSoupRuleParser(urlResolver: urlResolver)
        } catch {
            // If the database cannot be opened at launch, the app cannot operate.
            // Later we can replace this with a user-facing recovery screen.
            fatalError("Failed to build AppContainer: \(error)")
        }
    }

    func makeSourcesViewModel() -> SourcesViewModel {
        let loadSourcesUseCase: LoadSourcesUseCase = LoadSourcesUseCase(
            sourceRepository: self.sourceRepository
        )
        let addSourceUseCase: AddSourceUseCase = AddSourceUseCase(
            sourceRepository: self.sourceRepository
        )
        let refreshSourceUseCase: RefreshSourceUseCase = RefreshSourceUseCase(
            httpClient: self.httpClient,
            ruleParser: self.ruleParser,
            urlResolver: self.urlResolver,
            contentRepository: self.contentRepository
        )

        return SourcesViewModel(
            loadSourcesUseCase: loadSourcesUseCase,
            addSourceUseCase: addSourceUseCase,
            refreshSourceUseCase: refreshSourceUseCase
        )
    }

    func makeLibraryViewModel() -> LibraryViewModel {
        let loadLibraryUseCase: LoadLibraryUseCase = LoadLibraryUseCase(
            contentRepository: self.contentRepository
        )
        let loadSourcesUseCase: LoadSourcesUseCase = LoadSourcesUseCase(
            sourceRepository: self.sourceRepository
        )
        let toggleFavoriteUseCase: ToggleFavoriteUseCase = ToggleFavoriteUseCase(
            favoriteRepository: self.favoriteRepository
        )
        let recordOpenItemUseCase: RecordOpenItemUseCase = RecordOpenItemUseCase(
            historyRepository: self.historyRepository
        )

        return LibraryViewModel(
            loadLibraryUseCase: loadLibraryUseCase,
            loadSourcesUseCase: loadSourcesUseCase,
            toggleFavoriteUseCase: toggleFavoriteUseCase,
            recordOpenItemUseCase: recordOpenItemUseCase
        )
    }

    func makeHistoryViewModel() -> HistoryViewModel {
        let loadHistoryUseCase: LoadHistoryUseCase = LoadHistoryUseCase(
            historyRepository: self.historyRepository,
            favoriteRepository: self.favoriteRepository
        )
        let loadLibraryUseCase: LoadLibraryUseCase = LoadLibraryUseCase(
            contentRepository: self.contentRepository
        )
        let loadSourcesUseCase: LoadSourcesUseCase = LoadSourcesUseCase(
            sourceRepository: self.sourceRepository
        )

        return HistoryViewModel(
            loadHistoryUseCase: loadHistoryUseCase,
            loadLibraryUseCase: loadLibraryUseCase,
            loadSourcesUseCase: loadSourcesUseCase
        )
    }
}

