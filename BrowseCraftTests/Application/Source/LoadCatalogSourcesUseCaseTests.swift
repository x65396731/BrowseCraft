import Foundation
import Testing
import CryptoKit
import BrowseCraftDomain
@testable import BrowseCraft
import BrowseCraftCore

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
        #expect(loader.requests.first?.request?.headers?["Cache-Control"] == "no-cache")
        #expect(loader.requests.first?.cachePolicy == .reloadIgnoringLocalCacheData)
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
        #expect(rule["version"] as? Int == 2)
        #expect(rule["baseUrl"] as? String == "https://example.invalid")
        #expect(rule["adapter"] == nil)
    }

    @Test func loadCatalogSourcesDecryptsEncryptedPortalCoreRule() async throws {
        let encryptedResponse: String = try Self.encryptedPortalCoreCatalogResponse()
        let loader: RecordingCatalogPageDataLoader = RecordingCatalogPageDataLoader(
            data: Data(encryptedResponse.utf8)
        )
        let keyProvider: CatalogRuleDecryptionKeyProvider = CatalogRuleDecryptionKeyProvider(
            keysByID: [
                "test-v1": SymmetricKey(data: try #require(Data(base64Encoded: Self.testKeyBase64)))
            ]
        )
        let useCase: LoadCatalogSourcesUseCase = LoadCatalogSourcesUseCase(
            pageDataLoader: loader,
            catalogRuleDecryptor: CatalogRuleDecryptor(keyProvider: keyProvider)
        )

        let sources: [CatalogSource] = try await useCase.execute()
        let source: CatalogSource = try #require(sources.first)
        let ruleData: Data = Data(source.ruleJSON.utf8)
        let rule: [String: Any] = try #require(JSONSerialization.jsonObject(with: ruleData) as? [String: Any])

        #expect(sources.count == 1)
        #expect(source.id == "catalog.video.encrypted")
        #expect(source.baseURL == "https://encrypted.example.invalid")
        #expect(source.kind == .video)
        #expect(rule["version"] as? Int == 2)
        #expect(rule["baseUrl"] as? String == "https://encrypted.example.invalid")
        #expect(rule["adapter"] == nil)
    }

    private static let sampleVideoV2RuleJSON: String = """
    {
      "version": 2,
      "name": "Sample Video V2",
      "baseUrl": "https://example.invalid",
      "site": {
        "name": "Sample Video V2",
        "domain": "example.invalid",
        "baseURL": "https://example.invalid"
      },
      "pages": [
        {
          "id": "latest",
          "title": "Latest",
          "type": "list",
          "url": "/videos/",
          "ruleRefs": {
            "list": "video-list"
          }
        }
      ],
      "ruleSets": {
        "listRules": [
          {
            "id": "video-list",
            "item": {
              "selector": ".video-card",
              "selectorKind": "css",
              "function": "raw"
            },
            "fields": {
              "title": {
                "selectorKind": "current",
                "function": "text"
              },
              "detailURL": {
                "selector": "a[href]",
                "selectorKind": "css",
                "function": "url",
                "param": "href"
              }
            }
          }
        ]
      }
    }
    """

    private static let encryptedVideoV2RuleJSON: String = """
    {
      "version": 2,
      "name": "Encrypted Video V2",
      "baseUrl": "https://encrypted.example.invalid",
      "site": {
        "name": "Encrypted Video V2",
        "domain": "encrypted.example.invalid",
        "baseURL": "https://encrypted.example.invalid"
      },
      "pages": [
        {
          "id": "latest",
          "title": "Latest",
          "type": "list",
          "url": "/videos/",
          "ruleRefs": {
            "list": "video-list"
          }
        }
      ],
      "ruleSets": {
        "listRules": [
          {
            "id": "video-list",
            "item": {
              "selector": ".video-card",
              "selectorKind": "css",
              "function": "raw"
            },
            "fields": {
              "title": {
                "selectorKind": "current",
                "function": "text"
              },
              "detailURL": {
                "selector": "a[href]",
                "selectorKind": "css",
                "function": "url",
                "param": "href"
              }
            }
          }
        ]
      }
    }
    """

    private static let portalCoreCatalogResponse: String = """
    [
      {
        "id": "catalog.video.sample",
        "name": "Sample Video",
        "baseURL": "https://example.invalid",
        "kind": "video",
        "ruleJSON": \(Self.sampleVideoV2RuleJSON),
        "payload": {
          "id": "catalog.video.sample",
          "name": "Sample Video",
          "baseURL": "https://example.invalid",
          "kind": "video",
          "ruleJSON": \(Self.sampleVideoV2RuleJSON)
        },
        "createdAt": "2026-07-09T00:00:00+00:00",
        "updatedAt": "2026-07-09T00:00:00+00:00"
      }
    ]
    """

    private static let testKeyBase64: String = "yAxcpfRu0nn6mEGZ395F29s8F9edPExEc2z1jCdSy18="

    private static func encryptedPortalCoreCatalogResponse() throws -> String {
        let sourcePayload: String = """
        {
          "id": "catalog.video.encrypted",
          "name": "Encrypted Video",
          "baseURL": "https://encrypted.example.invalid",
          "kind": "video",
          "ruleJSON": \(Self.encryptedVideoV2RuleJSON)
        }
        """
        let keyData: Data = try #require(Data(base64Encoded: Self.testKeyBase64))
        let key: SymmetricKey = SymmetricKey(data: keyData)
        let nonceData: Data = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
        let sealedBox: AES.GCM.SealedBox = try AES.GCM.seal(
            Data(sourcePayload.utf8),
            using: key,
            nonce: try AES.GCM.Nonce(data: nonceData)
        )
        var ciphertextAndTag: Data = sealedBox.ciphertext
        ciphertextAndTag.append(sealedBox.tag)

        return """
        [
          {
            "id": "catalog.video.encrypted",
            "name": "Encrypted Video",
            "baseURL": "https://encrypted.example.invalid",
            "kind": "video",
            "encryptedRule": {
              "version": 1,
              "keyId": "test-v1",
              "nonce": "\(nonceData.base64EncodedString())",
              "ciphertext": "\(ciphertextAndTag.base64EncodedString())"
            },
            "createdAt": "2026-07-09T00:00:00+00:00",
            "updatedAt": "2026-07-09T00:00:00+00:00"
          }
        ]
        """
    }
}

private final class RecordingCatalogPageDataLoader: PageDataLoader, @unchecked Sendable {
    struct RecordedRequest: Equatable {
        var url: URL
        var request: RequestConfig?
        var cachePolicy: URLRequest.CachePolicy
    }

    private let data: Data
    private(set) var requests: [RecordedRequest] = []

    init(data: Data) {
        self.data = data
    }

    func loadData(_ request: PageLoadRequest) async throws -> PageDataResponse {
        self.requests.append(
            RecordedRequest(
                url: request.url,
                request: request.requestConfig,
                cachePolicy: request.cachePolicy
            )
        )
        return PageDataResponse(data: self.data, finalURL: request.url)
    }
}
