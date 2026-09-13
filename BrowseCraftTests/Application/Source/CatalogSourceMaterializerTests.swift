import Foundation
import Testing
import BrowseCraftCore
import BrowseCraftDomain
@testable import BrowseCraft

struct CatalogSourceMaterializerTests {
    @Test func migratesComicV1CatalogRuleBeforePersistence() throws {
        let materializer: CatalogSourceMaterializer = CatalogSourceMaterializer()
        let catalogSource: CatalogSource = CatalogSource(
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

        let source = try materializer.source(
            from: catalogSource,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        #expect(source.rule.version == 2)
        #expect(source.rule.flags?.contains(.migratedV1Compatibility) == true)
        #expect(ComicSiteRuleV2Validator().validate(rule: source.rule).resolvedRule != nil)
    }

    @Test func materializesAndPersistsVideoV2AsRuleDrivenConfiguration() throws {
        let materializer: CatalogSourceMaterializer = CatalogSourceMaterializer()
        let catalogSource: CatalogSource = CatalogSource(
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
        let catalogSource: CatalogSource = CatalogSource(
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

// 中文注释：book catalog（规则仓库真跑产物）物化成 `.book` 配置；非法 ruleJSON 按 BookSiteRuleValidator 的问题清单报错。
struct BookCatalogSourceMaterializerTests {
    @Test func materializesRealBookCatalogIntoBookConfiguration() throws {
        let materializer: CatalogSourceMaterializer = CatalogSourceMaterializer()
        let catalogSource: CatalogSource = try Self.catalogSource(fixture: "biquhua-catalog")

        let source: Source = try materializer.source(from: catalogSource, createdAt: Date(), updatedAt: Date())

        #expect(source.id == "biquhua-com--top-all-0-1-html")
        #expect(source.type == .html)
        #expect(source.configuration.kind == .book)
        guard case .book(let configuration) = source.configuration else {
            Issue.record("expected .book configuration")
            return
        }
        #expect(configuration.schemaVersion == 2)
        #expect(configuration.rule.name == "笔趣阁")
        #expect(configuration.rule.ruleSets.readerRules.first?.variant == .textDOM)
        #expect(configuration.isEditable == false)
    }

    @Test func audiobookCatalogMaterializesToo() throws {
        let source: Source = try CatalogSourceMaterializer().source(
            from: try Self.catalogSource(fixture: "loyalbooks-catalog"),
            createdAt: Date(),
            updatedAt: Date()
        )
        guard case .book(let configuration) = source.configuration else {
            Issue.record("expected .book configuration")
            return
        }
        #expect(configuration.rule.ruleSets.readerRules.first?.variant == .audioMedia)
        #expect(configuration.rule.ruleSets.listRules.first?.pagination?.urlTemplate?.contains("{page}") == true)
    }

    @Test func invalidBookRuleJSONIsRejectedWithValidatorPaths() throws {
        let catalogSource: CatalogSource = CatalogSource(
            id: "bad-book",
            name: "Bad",
            baseURL: "https://bad.invalid/",
            kind: .book,
            ruleJSON: "{\"version\": 2, \"name\": \"Bad\", \"baseUrl\": \"https://bad.invalid/\", \"pages\": [], \"ruleSets\": {\"listRules\": [], \"detailRules\": [], \"readerRules\": []}}"
        )
        #expect(throws: CatalogSourceImportError.self) {
            _ = try CatalogSourceMaterializer().source(from: catalogSource, createdAt: Date(), updatedAt: Date())
        }
        do {
            _ = try CatalogSourceMaterializer().source(from: catalogSource, createdAt: Date(), updatedAt: Date())
        } catch let error as CatalogSourceImportError {
            guard case .invalidRuleJSON(_, _, let kind, let reason) = error else {
                Issue.record("expected invalidRuleJSON, got \(error)")
                return
            }
            #expect(kind == "book")
            #expect(reason.contains("$.ruleSets.listRules"))
            #expect(reason.contains("$.pages"))
        }
    }

    private static func catalogSource(fixture: String) throws -> CatalogSource {
        let url: URL = try #require(Bundle(for: BookCatalogFixtureMarker.self).url(forResource: fixture, withExtension: "json"))
        let catalog: [String: Any] = try #require(JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let ruleJSON: Data = try JSONSerialization.data(withJSONObject: try #require(catalog["ruleJSON"]))
        return CatalogSource(
            id: try #require(catalog["id"] as? String),
            name: try #require(catalog["name"] as? String),
            baseURL: try #require(catalog["baseURL"] as? String),
            kind: .book,
            ruleJSON: String(decoding: ruleJSON, as: UTF8.self)
        )
    }
}

private final class BookCatalogFixtureMarker {}
