import Foundation
import Testing
import BrowseCraftCore
import BrowseCraftAPIKit
@testable import BrowseCraft

struct CatalogSourceMaterializerTests {
    @Test func materializesComicRuleWithEmptyChapterAPIRequestBody() throws {
        let materializer: CatalogSourceMaterializer = CatalogSourceMaterializer()
        let catalogSource: BrowseCraftCatalogSource = BrowseCraftCatalogSource(
            id: "komiic",
            name: "Komiic",
            baseURL: "https://komiic.com",
            kind: .comic,
            ruleJSON: """
            {
              "version": 1,
              "name": "Komiic",
              "baseUrl": "https://komiic.com",
              "list": {
                "id": "latest",
                "url": "https://komiic.com/latest",
                "item": "a[href*='/comic/']",
                "title": "this",
                "link": "this@href",
                "cover": "img@src",
                "type": "comic"
              },
              "detail": {
                "id": "detail",
                "title": "h1",
                "cover": "img@src",
                "chapterContainer": "body",
                "chapterItem": "a[href*='/chapter/']",
                "chapterTitle": "this",
                "chapterLink": "this@href",
                "chapterAPI": {
                  "url": "https://komiic.com/api/query",
                  "request": {
                    "method": "POST",
                    "body": {}
                  },
                  "itemPath": "data.chapters[]",
                  "titlePath": "title",
                  "urlPath": "url",
                  "preferAPI": true
                }
              },
              "gallery": {
                "id": "reader",
                "imageItem": "img",
                "imageUrl": "this@src"
              }
            }
            """
        )

        let source: Source = try materializer.source(
            from: catalogSource,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        guard case .comic(let configuration) = source.configuration else {
            Issue.record("Expected catalog source to materialize as a comic source.")
            return
        }

        #expect(configuration.rule.name == "Komiic")
    }

    @Test func materializesAndPersistsVideoV2AsRuleDrivenConfiguration() throws {
        let materializer: CatalogSourceMaterializer = CatalogSourceMaterializer()
        let catalogSource: BrowseCraftCatalogSource = BrowseCraftCatalogSource(
            id: "catalog.video.v2",
            name: "Video V2",
            baseURL: "https://video.example.invalid/",
            kind: .video,
            ruleJSON: """
            {
              "version": 2,
              "name": "Video V2",
              "baseUrl": "https://video.example.invalid/",
              "site": {
                "name": "Video V2",
                "domain": "video.example.invalid",
                "baseURL": "https://video.example.invalid/"
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
        )

        let source: Source = try materializer.source(
            from: catalogSource,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        guard case .video(let configuration) = source.configuration else {
            Issue.record("Expected Video V2 catalog source to use rule-driven persistence.")
            return
        }

        #expect(configuration.rule.version == 2)
        #expect(configuration.rule.pages.map(\.id) == ["latest"])

        let encodedConfiguration: Data = try JSONEncoder().encode(source.configuration)
        let persistedJSON: [String: Any] = try #require(
            JSONSerialization.jsonObject(with: encodedConfiguration) as? [String: Any]
        )
        let persistedValue: [String: Any] = try #require(persistedJSON["video"] as? [String: Any])
        #expect(persistedValue["strategy"] as? String == "ruleDriven")
        #expect(persistedValue["rule"] != nil)
        #expect(persistedValue["definition"] == nil)

        let decodedConfiguration: SourceConfiguration = try JSONDecoder().decode(
            SourceConfiguration.self,
            from: encodedConfiguration
        )
        #expect(decodedConfiguration == source.configuration)
    }

    @Test func rejectsVideoV1CatalogRule() throws {
        let catalogSource: BrowseCraftCatalogSource = BrowseCraftCatalogSource(
            id: "catalog.video.v1",
            name: "Video V1",
            baseURL: "https://video.example.invalid/",
            kind: .video,
            ruleJSON: """
            {
              "adapter": "genericHTML",
              "entryURL": "https://video.example.invalid/videos/"
            }
            """
        )

        #expect(throws: CatalogSourceImportError.self) {
            _ = try CatalogSourceMaterializer().source(
                from: catalogSource,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 20)
            )
        }
    }
}
