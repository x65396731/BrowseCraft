import Foundation
import Testing
import BrowseCraftCore
import BrowseCraftRulesKit
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

    @Test func materializesVideoSourceWithObjectRoutePattern() throws {
        let materializer: CatalogSourceMaterializer = CatalogSourceMaterializer()
        let catalogSource: BrowseCraftCatalogSource = BrowseCraftCatalogSource(
            id: "catalog.video.object-route",
            name: "Object Route",
            baseURL: "https://example.invalid",
            kind: .video,
            ruleJSON: """
            {
              "adapter": "genericHTML",
              "entryURL": "https://example.invalid/videos/",
              "entryKind": "list",
              "routePattern": {
                "detail": "/voddetail/{id}.html",
                "play": "/vodplay/{id}-{source}-{episode}.html"
              },
              "playbackPolicy": "playPageFirst",
              "requiresAccount": false,
              "listTabs": []
            }
            """
        )

        let source: Source = try materializer.source(
            from: catalogSource,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        guard case .video(.legacyPreset(let configuration)) = source.configuration else {
            Issue.record("Expected catalog source to materialize as a video source.")
            return
        }

        #expect(configuration.definition.adapter == .macCMS)
        #expect(configuration.definition.routePatterns == .macCMS)
    }

    @Test func materializesGenericHTMLVfedRuleAsMacCMSRoutePattern() throws {
        let materializer: CatalogSourceMaterializer = CatalogSourceMaterializer()
        let catalogSource: BrowseCraftCatalogSource = BrowseCraftCatalogSource(
            id: "catalog.video.vfed",
            name: "Vfed Rule",
            baseURL: "https://video.example.invalid",
            kind: .video,
            ruleJSON: """
            {
              "adapter": "genericHTML",
              "entryURL": "https://video.example.invalid/",
              "entryKind": "home",
              "playbackPolicy": "playPageFirst",
              "requiresAccount": false,
              "listTabs": [
                {
                  "id": "movie",
                  "title": "Movie",
                  "url": "https://video.example.invalid/vodtype/1/",
                  "itemSelector": ".fed-list-item",
                  "titleSelector": ".fed-list-title",
                  "linkSelector": "a[href*='/voddetail/']@href",
                  "coverSelector": ".fed-list-pics@data-original",
                  "latestTextSelector": ".fed-list-remarks"
                }
              ]
            }
            """
        )

        let source: Source = try materializer.source(
            from: catalogSource,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        guard case .video(.legacyPreset(let configuration)) = source.configuration else {
            Issue.record("Expected catalog source to materialize as a video source.")
            return
        }

        #expect(configuration.definition.adapter == .macCMS)
        #expect(configuration.definition.routePatterns == .macCMS)
    }

    @Test func materializesGenericHTMLMacCMSCategoryTabsAsMacCMSRoutePattern() throws {
        let materializer: CatalogSourceMaterializer = CatalogSourceMaterializer()
        let catalogSource: BrowseCraftCatalogSource = BrowseCraftCatalogSource(
            id: "catalog.video.category-routes",
            name: "Category Routes",
            baseURL: "https://video.example.invalid",
            kind: .video,
            ruleJSON: """
            {
              "adapter": "genericHTML",
              "entryURL": "https://video.example.invalid/",
              "entryKind": "home",
              "playbackPolicy": "playPageFirst",
              "requiresAccount": false,
              "listTabs": [
                {
                  "id": "movie",
                  "title": "Movie",
                  "url": "https://video.example.invalid/vodtype/1/"
                },
                {
                  "id": "series",
                  "title": "Series",
                  "url": "https://video.example.invalid/vodtype/2/"
                }
              ]
            }
            """
        )

        let source: Source = try materializer.source(
            from: catalogSource,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        guard case .video(.legacyPreset(let configuration)) = source.configuration else {
            Issue.record("Expected catalog source to materialize as a video source.")
            return
        }

        #expect(configuration.definition.adapter == .macCMS)
        #expect(configuration.definition.routePatterns == .macCMS)
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

        guard case .video(.ruleDriven(let configuration)) = source.configuration else {
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

    @Test func decodesPersistedVideoConfigurationWithoutStrategyAsLegacyPreset() throws {
        let legacyDefinition: VideoSourceDefinition = VideoSourceDefinition(
            adapter: .genericHTML,
            entryURL: try #require(URL(string: "https://video.example.invalid/videos/")),
            seedURL: nil,
            entryKind: .list,
            routePatterns: nil,
            playbackPolicy: .playPageFirst,
            requiresAccount: false,
            seedVodID: nil,
            seedSourceIndex: nil,
            seedEpisodeIndex: nil,
            seedDetailURL: nil,
            seedPlayURL: nil
        )
        let definitionData: Data = try JSONEncoder().encode(legacyDefinition)
        let definitionJSON: [String: Any] = try #require(
            JSONSerialization.jsonObject(with: definitionData) as? [String: Any]
        )
        let persistedData: Data = try JSONSerialization.data(
            withJSONObject: [
                "video": [
                    "definition": definitionJSON,
                    "listTabs": []
                ]
            ],
            options: [.sortedKeys]
        )

        let configuration: SourceConfiguration = try JSONDecoder().decode(
            SourceConfiguration.self,
            from: persistedData
        )

        guard case .video(.legacyPreset(let legacyConfiguration)) = configuration else {
            Issue.record("Expected persisted V1 video data without strategy to decode as legacyPreset.")
            return
        }
        #expect(legacyConfiguration.definition == legacyDefinition)
        #expect(legacyConfiguration.listTabs.isEmpty)
    }
}
