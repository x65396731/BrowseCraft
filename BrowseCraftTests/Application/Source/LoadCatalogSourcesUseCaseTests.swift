import BrowseCraftCore
import BrowseCraftDomain
import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：App 取公共目录的用例：请求显式带本版本认得的 kinds；解码时未知 kind 逐条跳过、book 照常进入。

struct LoadCatalogSourcesUseCaseTests {
    @Test func defaultURLDeclaresEveryKnownKind() {
        #expect(LoadCatalogSourcesUseCase.defaultCatalogAPIURL?.absoluteString == "https://anyportal.online/catalog/sources?kinds=comic,video,book")
    }

    @Test func unknownKindIsSkippedAndBookDecodes() async throws {
        let loader: RecordingCatalogDataLoader = RecordingCatalogDataLoader(
            payload: """
            [
              {"id": "c1", "name": "Comic", "baseURL": "https://c/", "kind": "comic", "ruleJSON": {"version": 2, "name": "C"}},
              {"id": "b1", "name": "Book", "baseURL": "https://b/", "kind": "book", "ruleJSON": {"version": 2, "name": "B"}},
              {"id": "x1", "name": "Future", "baseURL": "https://x/", "kind": "hologram", "ruleJSON": {"version": 9}}
            ]
            """
        )
        let useCase: LoadCatalogSourcesUseCase = LoadCatalogSourcesUseCase(pageDataLoader: loader)

        let sources: [CatalogSource] = try await useCase.execute()

        #expect(sources.map(\.id) == ["c1", "b1"])
        #expect(sources.map(\.kind) == [.comic, .book])
        #expect(loader.requestedURL?.query == "kinds=comic,video,book")
    }
}

private final class RecordingCatalogDataLoader: PageDataLoader, @unchecked Sendable {
    private let payload: String
    private(set) var requestedURL: URL?

    init(payload: String) {
        self.payload = payload
    }

    func loadData(_ request: PageLoadRequest) async throws -> PageDataResponse {
        self.requestedURL = request.url
        return PageDataResponse(data: Data(self.payload.utf8), finalURL: request.url)
    }
}
