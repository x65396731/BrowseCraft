import Foundation
import Testing
import BrowseCraftRulesKit
@testable import BrowseCraft

struct LoadCatalogSourcesUseCaseTests {
    @Test func loadCatalogSourcesUsesPluralPortalCoreEndpoint() async throws {
        let loader: RecordingCatalogPageDataLoader = RecordingCatalogPageDataLoader(
            data: Data(Self.portalCoreCatalogResponse.utf8)
        )
        let useCase: LoadCatalogSourcesUseCase = LoadCatalogSourcesUseCase(
            pageDataLoader: loader,
            requestHeaders: {
                return [
                    "userId": "local.default",
                    "osInfo": "iOS 17.0",
                    "deviceInfo": "iPhone15,3",
                    "aplVersion": "1.0(1)",
                    "X-Request-Id": "request-1"
                ]
            }
        )

        _ = try await useCase.execute()

        #expect(loader.requests.map(\.url.absoluteString) == ["https://anyportal.online/catalog/sources"])
        #expect(loader.requests.first?.request?.headers?["Accept"] == "application/json")
        #expect(loader.requests.first?.request?.headers?["userId"] == "local.default")
        #expect(loader.requests.first?.request?.headers?["osInfo"] == "iOS 17.0")
        #expect(loader.requests.first?.request?.headers?["deviceInfo"] == "iPhone15,3")
        #expect(loader.requests.first?.request?.headers?["aplVersion"] == "1.0(1)")
        #expect(loader.requests.first?.request?.headers?["X-Request-Id"] == "request-1")
    }

    @Test func loadCatalogSourcesDecodesPortalCoreObjectRuleJSON() async throws {
        let loader: RecordingCatalogPageDataLoader = RecordingCatalogPageDataLoader(
            data: Data(Self.portalCoreCatalogResponse.utf8)
        )
        let useCase: LoadCatalogSourcesUseCase = LoadCatalogSourcesUseCase(pageDataLoader: loader)

        let sources = try await useCase.execute()
        let source = try #require(sources.first)
        let ruleData: Data = Data(source.ruleJSON.utf8)
        let rule = try #require(JSONSerialization.jsonObject(with: ruleData) as? [String: Any])

        #expect(sources.count == 1)
        #expect(source.id == "catalog.video.sample")
        #expect(source.baseURL == "https://example.invalid")
        #expect(source.kind == .video)
        #expect(rule["adapter"] as? String == "genericHTML")
        #expect(rule["entryURL"] as? String == "https://example.invalid/videos/")
    }

    private static let portalCoreCatalogResponse: String = """
    [
      {
        "id": "catalog.video.sample",
        "name": "Sample Video",
        "baseURL": "https://example.invalid",
        "kind": "video",
        "ruleJSON": {
          "adapter": "genericHTML",
          "entryURL": "https://example.invalid/videos/",
          "entryKind": "list",
          "routePattern": null,
          "playbackPolicy": "playPageFirst",
          "sharedRequest": null,
          "listRequest": null,
          "detailRequest": null,
          "playRequest": null,
          "requiresAccount": false,
          "listTabs": []
        },
        "payload": {
          "id": "catalog.video.sample",
          "name": "Sample Video",
          "baseURL": "https://example.invalid",
          "kind": "video",
          "ruleJSON": {
            "adapter": "genericHTML",
            "entryURL": "https://example.invalid/videos/",
            "entryKind": "list",
            "routePattern": null,
            "playbackPolicy": "playPageFirst",
            "sharedRequest": null,
            "listRequest": null,
            "detailRequest": null,
            "playRequest": null,
            "requiresAccount": false,
            "listTabs": []
          }
        },
        "createdAt": "2026-07-09T00:00:00+00:00",
        "updatedAt": "2026-07-09T00:00:00+00:00"
      }
    ]
    """
}

private final class RecordingCatalogPageDataLoader: PageDataLoader {
    struct RecordedRequest: Equatable {
        var url: URL
        var request: RequestConfig?
    }

    private let data: Data
    private(set) var requests: [RecordedRequest] = []

    init(data: Data) {
        self.data = data
    }

    func getData(from url: URL, request: RequestConfig?) async throws -> Data {
        self.requests.append(
            RecordedRequest(
                url: url,
                request: request
            )
        )
        return self.data
    }
}
