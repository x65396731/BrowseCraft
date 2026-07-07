import Foundation
import BrowseCraftCore

// 中文注释：AddRSSSourceUseCase 负责把公开 RSS feed 保存为 rss-backed Source，不处理账号或凭据。
struct AddRSSSourceResult {
    let source: Source
    let listOutput: SourceListOutput
}

struct AddRSSSourceUseCase {
    private let sourceRepository: SourceRepository
    private let feedLoader: any RSSFeedLoading
    private let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase
    private let validateSourceListLoadUseCase: ValidateSourceListLoadUseCase
    private let now: () -> Date
    private let makeID: () -> String

    init(
        sourceRepository: SourceRepository,
        feedLoader: any RSSFeedLoading,
        refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase,
        validateSourceListLoadUseCase: ValidateSourceListLoadUseCase = ValidateSourceListLoadUseCase(),
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.sourceRepository = sourceRepository
        self.feedLoader = feedLoader
        self.refreshSourceRuntimeUseCase = refreshSourceRuntimeUseCase
        self.validateSourceListLoadUseCase = validateSourceListLoadUseCase
        self.now = now
        self.makeID = makeID
    }

    func execute(feedURLString: String, name: String? = nil) async throws -> AddRSSSourceResult {
        let feedURL: URL = try self.feedURL(from: feedURLString)
        let feed: RSSFeed = try await self.feedLoader.load(feedURL: feedURL)
        let timestamp: Date = self.now()
        let source: Source = Source(
            id: self.makeID(),
            name: self.sourceName(inputName: name, feed: feed, feedURL: feedURL),
            baseURL: self.baseURLString(from: feedURL),
            type: .rss,
            configuration: .rss(
                RSSSourceConfiguration(
                    definition: RSSSourceDefinition(
                        feedURL: feedURL,
                        requiresAccount: false,
                        refreshPolicy: .manual
                    )
                )
            ),
            enabled: true,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let listOutput: SourceListOutput = try await self.refreshSourceRuntimeUseCase.execute(
            source: source,
            listContext: nil
        )
        try self.validateSourceListLoadUseCase.execute(listOutput)
        try self.sourceRepository.saveSource(source)
        return AddRSSSourceResult(source: source, listOutput: listOutput)
    }

    private func feedURL(from string: String) throws -> URL {
        let trimmed: String = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url: URL = URL(string: trimmed),
              let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            throw AddRSSSourceError.invalidFeedURL
        }

        return url
    }

    private func sourceName(inputName: String?, feed: RSSFeed, feedURL: URL) -> String {
        if let inputName: String = inputName?.trimmedNonEmpty {
            return inputName
        }

        if let feedTitle: String = feed.title?.trimmedNonEmpty {
            return feedTitle
        }

        return feedURL.host ?? "RSS Feed"
    }

    private func baseURLString(from feedURL: URL) -> String {
        var components: URLComponents = URLComponents()
        components.scheme = feedURL.scheme
        components.host = feedURL.host
        components.port = feedURL.port
        return components.url?.absoluteString ?? feedURL.absoluteString
    }
}

enum AddRSSSourceError: Error, Equatable {
    case invalidFeedURL
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
