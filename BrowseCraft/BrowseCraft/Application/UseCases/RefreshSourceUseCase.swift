import Foundation

/// Fetches a source list page, parses it, saves the normalized items, and returns them.
///
/// This is the core MVP pipeline:
///
/// Source + Rule -> Fetch -> Parse -> Normalize -> Store -> Display
struct RefreshSourceUseCase {
    private let httpClient: HTTPClient
    private let ruleParser: RuleParsingService
    private let urlResolver: URLResolvingService
    private let contentRepository: ContentRepository

    init(
        httpClient: HTTPClient,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService,
        contentRepository: ContentRepository
    ) {
        self.httpClient = httpClient
        self.ruleParser = ruleParser
        self.urlResolver = urlResolver
        self.contentRepository = contentRepository
    }

    func execute(source: Source, page: Int = 1) async throws -> [ContentItem] {
        let url: URL = try self.urlResolver.listURL(for: source, page: page)
        let html: String = try await self.httpClient.getString(from: url)
        let items: [ContentItem] = try self.ruleParser.parseList(html: html, source: source)

        try self.contentRepository.saveItems(items)
        return items
    }
}

