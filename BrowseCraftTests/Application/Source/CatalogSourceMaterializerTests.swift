import Foundation
import Testing
import BrowseCraftCore
import BrowseCraftRulesKit
@testable import BrowseCraft

struct CatalogSourceMaterializerTests {
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
