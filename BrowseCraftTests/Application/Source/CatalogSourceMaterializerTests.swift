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

        guard case .video(let configuration) = source.configuration else {
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

        guard case .video(let configuration) = source.configuration else {
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

        guard case .video(let configuration) = source.configuration else {
            Issue.record("Expected catalog source to materialize as a video source.")
            return
        }

        #expect(configuration.definition.adapter == .macCMS)
        #expect(configuration.definition.routePatterns == .macCMS)
    }
}
