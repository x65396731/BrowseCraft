import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：AddRSSSourceUseCaseTests 固定 P4.9.5 RSS Source 保存入口和公开 feed 边界。
struct AddRSSSourceUseCaseTests {
    @Test func savesRSSSourceConfigurationUsingFeedTitle() async throws {
        let repository: RSSInMemorySourceRepository = RSSInMemorySourceRepository()
        let useCase: AddRSSSourceUseCase = AddRSSSourceUseCase(
            sourceRepository: repository,
            feedLoader: AddRSSStubFeedLoader(
                feed: RSSFeed(title: "Solidot", items: [])
            ),
            now: { Date(timeIntervalSince1970: 1_000) },
            makeID: { "rss.solidot" }
        )

        let source: Source = try await useCase.execute(
            feedURLString: " https://www.solidot.org/index.rss "
        )

        #expect(source.id == "rss.solidot")
        #expect(source.name == "Solidot")
        #expect(source.baseURL == "https://www.solidot.org")
        #expect(source.type == .rss)
        #expect(source.enabled == true)
        #expect(source.createdAt == Date(timeIntervalSince1970: 1_000))
        #expect(repository.savedSources[source.id] == source)

        guard case .rss(let configuration) = source.configuration else {
            Issue.record("Expected rss configuration.")
            return
        }

        #expect(configuration.definition.feedURL.absoluteString == "https://www.solidot.org/index.rss")
        #expect(configuration.definition.requiresAccount == false)
        #expect(configuration.definition.refreshPolicy == .manual)
    }

    @Test func inputNameOverridesFeedTitleAndSourceRecordRoundTripsRSSConfiguration() async throws {
        let repository: RSSInMemorySourceRepository = RSSInMemorySourceRepository()
        let useCase: AddRSSSourceUseCase = AddRSSSourceUseCase(
            sourceRepository: repository,
            feedLoader: AddRSSStubFeedLoader(feed: RSSFeed(title: "Solidot", items: [])),
            now: { Date(timeIntervalSince1970: 2_000) },
            makeID: { "rss.custom" }
        )

        let source: Source = try await useCase.execute(
            feedURLString: "https://www.solidot.org/index.rss",
            name: "My Feed"
        )
        let record: SourceRecord = try SourceRecord(source: source)
        let decodedSource: Source = try record.domainModel()

        #expect(source.name == "My Feed")
        #expect(record.kind == "rss")
        #expect(record.configJSON.contains("https:\\/\\/www.solidot.org\\/index.rss"))
        #expect(decodedSource.configuration == source.configuration)
    }

    @Test func rejectsInvalidFeedURL() async throws {
        let useCase: AddRSSSourceUseCase = AddRSSSourceUseCase(
            sourceRepository: RSSInMemorySourceRepository(),
            feedLoader: AddRSSStubFeedLoader(feed: RSSFeed(title: nil, items: []))
        )

        await #expect(throws: AddRSSSourceError.invalidFeedURL) {
            _ = try await useCase.execute(feedURLString: "not a url")
        }
    }
}

private final class RSSInMemorySourceRepository: SourceRepository {
    var savedSources: [String: Source] = [:]

    func fetchSources() throws -> [Source] {
        return Array(self.savedSources.values)
    }

    func saveSource(_ source: Source) throws {
        self.savedSources[source.id] = source
    }

    func deleteSource(id: String) throws {
        self.savedSources.removeValue(forKey: id)
    }
}

private struct AddRSSStubFeedLoader: RSSFeedLoading {
    var feed: RSSFeed

    func load(feedURL: URL) async throws -> RSSFeed {
        return self.feed
    }
}
