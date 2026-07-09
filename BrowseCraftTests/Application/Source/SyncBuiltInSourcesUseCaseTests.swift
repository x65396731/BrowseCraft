import Foundation
import Testing
import BrowseCraftCore
import BrowseCraftRulesKit
@testable import BrowseCraft

struct SyncBuiltInSourcesUseCaseTests {
    @Test func syncUpdatesExistingCatalogVideoSourceWithoutAddingMissingSources() throws {
        let repository: SyncInMemorySourceRepository = SyncInMemorySourceRepository()
        let oldSource: Source = Source(
            id: "catalog.video.arte",
            name: "Old ARTE",
            baseURL: "https://www.arte.tv/",
            type: .html,
            configuration: .video(
                VideoSourceConfiguration(
                    definition: VideoSourceDefinition(
                        adapter: .genericHTML,
                        entryURL: try #require(URL(string: "https://www.arte.tv/en/videos/")),
                        seedURL: nil,
                        entryKind: .list,
                        routePatterns: nil,
                        playbackPolicy: .playPageFirst,
                        sharedRequest: RequestConfig(needsWebView: true),
                        requiresAccount: false,
                        seedVodID: nil,
                        seedSourceIndex: nil,
                        seedEpisodeIndex: nil,
                        seedDetailURL: nil,
                        seedPlayURL: nil
                    ),
                    listTabs: [
                        VideoSourceListTab(
                            id: "video.arte.videos",
                            title: "Videos",
                            url: "https://www.arte.tv/en/videos/"
                        )
                    ]
                )
            ),
            enabled: false,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try repository.saveSource(oldSource)

        try SyncBuiltInSourcesUseCase(
            sourceRepository: repository,
            catalogSources: [
                Self.arteCatalogSource()
            ],
            now: {
                return Date(timeIntervalSince1970: 30)
            }
        ).execute()

        let sources: [Source] = try repository.fetchSources()
        let updatedSource: Source = try #require(sources.first)
        guard case .video(let configuration) = updatedSource.configuration else {
            Issue.record("Expected upgraded ARTE source to stay a video source.")
            return
        }

        #expect(sources.count == 1)
        #expect(updatedSource.name == "ARTE Videos")
        #expect(updatedSource.enabled == false)
        #expect(updatedSource.createdAt == Date(timeIntervalSince1970: 10))
        #expect(updatedSource.updatedAt == Date(timeIntervalSince1970: 30))
        #expect(configuration.listTabs.map(\.id) == ["video.arte.videos"])
        #expect(
            configuration.definition.sharedRequest?.imageRequest?.headers?["Accept"] ==
                "image/jpeg,image/png,image/*;q=0.8,*/*;q=0.5"
        )
    }

    private static func arteCatalogSource() -> BrowseCraftCatalogSource {
        return BrowseCraftCatalogSource(
            id: "catalog.video.arte",
            name: "ARTE Videos",
            baseURL: "https://www.arte.tv/",
            kind: .video,
            ruleJSON: """
            {
              "adapter": "genericHTML",
              "entryURL": "https://www.arte.tv/en/videos/",
              "entryKind": "list",
              "playbackPolicy": "playPageFirst",
              "sharedRequest": {
                "needsWebView": true,
                "autoScroll": true,
                "imageRequest": {
                  "headers": {
                    "Accept": "image/jpeg,image/png,image/*;q=0.8,*/*;q=0.5"
                  }
                }
              },
              "requiresAccount": false,
              "listTabs": [
                {
                  "id": "video.arte.videos",
                  "title": "Videos",
                  "url": "https://www.arte.tv/en/videos/"
                }
              ]
            }
            """
        )
    }
}

private final class SyncInMemorySourceRepository: SourceRepository {
    private var sources: [Source] = []

    func fetchSources() throws -> [Source] {
        return self.sources
    }

    func saveSource(_ source: Source) throws {
        if let index: Array<Source>.Index = self.sources.firstIndex(where: { existingSource in
            return existingSource.id == source.id
        }) {
            self.sources[index] = source
            return
        }

        self.sources.append(source)
    }

    func deleteSource(id: String) throws {
        self.sources.removeAll { source in
            return source.id == id
        }
    }
}
