import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：ComicRuleSourceReaderProtectedResourceTests 验证漫画 reader 能把 imageAPI 条目映射成受保护图片引用。
struct ComicRuleSourceReaderProtectedResourceTests {
    @Test func imageAPIProducesProtectedReaderPageResources() async throws {
        let pageContentLoader: RecordingReaderPageContentLoader = RecordingReaderPageContentLoader(
            responses: [
                "https://example.test/api/chapter/10/images": """
                {
                  "images": [
                    { "id": "img-1", "sort": 2 },
                    { "id": "img-0", "sort": 1 }
                  ]
                }
                """
            ]
        )
        let loader: ComicRuleSourceReaderLoader = ComicRuleSourceReaderLoader(
            pageContentLoader: pageContentLoader,
            comicRuleParser: SwiftSoupComicRuleSourceParser(urlResolver: URLResolvingService())
        )

        let chapter: ReaderChapter = try await loader.execute(
            source: Self.sourceWithProtectedImageAPI(),
            item: ContentItem(
                id: "comic-10",
                sourceId: "protected-reader-source",
                title: "Protected Reader",
                detailURL: "https://example.test/comic/10",
                coverURL: nil,
                type: .comic,
                latestText: nil
            ),
            chapterURLString: "https://example.test/chapter/10"
        )

        #expect(chapter.pageImageURLs == [
            "protected://reader-image?imageId=img-0&quality=high",
            "protected://reader-image?imageId=img-1&quality=high"
        ])
        #expect(chapter.pageResources.count == 2)

        guard case .protectedResource(let firstReference) = chapter.pageResources[0] else {
            Issue.record("Expected first page to be protectedResource")
            return
        }
        guard case .legacy(let legacyReference) = firstReference.execution else {
            Issue.record("Expected imageAPI without resourcePipeline to keep the legacy route")
            return
        }
        #expect(legacyReference.sourceID == "protected-reader-source")
        #expect(legacyReference.baseURL?.absoluteString == "https://example.test")
        #expect(legacyReference.parameters["imageId"] == "img-0")
        #expect(legacyReference.parameters["quality"] == "high")
        #expect(legacyReference.parameters["id"] == "img-0")
        #expect(legacyReference.rule.binaryRequest.url == "https://example.test/encrypt/{imageId}/{quality}")
    }

    @Test func galleryProtectedResourceProducesProtectedReaderPageResources() async throws {
        let pageContentLoader: RecordingReaderPageContentLoader = RecordingReaderPageContentLoader(
            responses: [
                "https://example.test/api/chapter/10/info": """
                {
                  "data": {
                    "chapter": {
                      "proportion": [
                        { "id": "img-2", "idx": 2 },
                        { "id": "img-1", "idx": 1 }
                      ]
                    }
                  }
                }
                """
            ]
        )
        let loader: ComicRuleSourceReaderLoader = ComicRuleSourceReaderLoader(
            pageContentLoader: pageContentLoader,
            comicRuleParser: SwiftSoupComicRuleSourceParser(urlResolver: URLResolvingService())
        )

        let chapter: ReaderChapter = try await loader.execute(
            source: Self.sourceWithGalleryProtectedResource(),
            item: ContentItem(
                id: "comic-10",
                sourceId: "protected-reader-source",
                title: "Protected Reader",
                detailURL: "https://example.test/comic/10",
                coverURL: nil,
                type: .comic,
                latestText: nil
            ),
            chapterURLString: "https://example.test/reader/10"
        )

        #expect(pageContentLoader.requestedURLs == ["https://example.test/api/chapter/10/info"])
        #expect(chapter.pageImageURLs == [
            "protected://reader-image?imageId=img-1&id=img-1&quality=2",
            "protected://reader-image?imageId=img-2&id=img-2&quality=2"
        ])

        guard case .some(.protectedResource(let firstReference)) = chapter.pageResources.first else {
            Issue.record("Expected gallery protectedResource to bridge into protected page resources")
            return
        }
        guard case .legacy(let legacyReference) = firstReference.execution else {
            Issue.record("Expected gallery protectedResource bridge to keep the legacy route")
            return
        }
        #expect(legacyReference.parameters["imageId"] == "img-1")
        #expect(legacyReference.parameters["id"] == "img-1")
        #expect(legacyReference.parameters["quality"] == "2")
        #expect(legacyReference.rule.binaryRequest.url == "https://example.test/encrypt/{id}/{quality}")
    }

    @Test func v2PipelineMapsItemRootAndContextWithoutDependingOnLegacyURL() async throws {
        let pageContentLoader: RecordingReaderPageContentLoader = RecordingReaderPageContentLoader(
            responses: [
                "https://example.test/api/chapter/10/images": """
                {
                  "meta": { "chapterKey": "root-10" },
                  "images": [
                    {
                      "id": "img-0",
                      "nested": { "rank": 3 },
                      "flags": [true, null]
                    }
                  ]
                }
                """
            ]
        )
        let loader: ComicRuleSourceReaderLoader = ComicRuleSourceReaderLoader(
            pageContentLoader: pageContentLoader,
            comicRuleParser: SwiftSoupComicRuleSourceParser(urlResolver: URLResolvingService())
        )

        let chapter: ReaderChapter = try await loader.execute(
            source: Self.sourceWithResourcePipeline(policy: .pipelineOnly),
            item: ContentItem(
                id: "comic-10",
                sourceId: "protected-reader-source",
                title: "Pipeline Reader",
                detailURL: "https://example.test/comic/10",
                coverURL: nil,
                type: .comic,
                latestText: nil
            ),
            chapterURLString: "https://example.test/chapter/10"
        )

        guard case .some(.protectedResource(let protectedReference)) = chapter.pageResources.first,
              case .pipeline(let pipelineReference) = protectedReference.execution else {
            Issue.record("Expected V2 imageAPI item to become a pipeline reference")
            return
        }

        #expect(pipelineReference.item["id"] == .string("img-0"))
        #expect(pipelineReference.item["nested"] == .object(["rank": .number(3)]))
        #expect(pipelineReference.item["flags"] == .array([.boolean(true), .null]))
        #expect(pipelineReference.root["meta"] == .object(["chapterKey": .string("root-10")]))
        #expect(pipelineReference.context["readerAccessToken"] == .string("context-secret"))
        #expect(pipelineReference.legacyFallback == nil)
        #expect(pipelineReference.displayURLString.hasPrefix("resource-pipeline://reader/"))
    }

    @Test func executionPolicyAloneControlsLegacyFallback() async throws {
        let legacyData: Data = Data("legacy-image".utf8)
        let legacyReference: LegacyProtectedReaderImageReference = LegacyProtectedReaderImageReference(
            displayURLString: "protected://reader-image?id=img-0",
            sourceID: "protected-reader-source",
            baseURL: URL(string: "https://example.test"),
            rule: Self.legacyProtectedResource(),
            parameters: ["id": "img-0"]
        )
        let loader: ReaderProtectedResourceLoader = ReaderProtectedResourceLoader(
            loadLegacy: { _ in
                ProtectedResourceOutput(data: legacyData, contentType: .image)
            },
            executePipeline: { _ in
                throw StubResourcePipelineError.failed
            }
        )
        let context: SourceRequestContext = SourceRequestContext(sourceID: "protected-reader-source")
        var pipelineReference: ResourcePipelineReaderImageReference = ResourcePipelineReaderImageReference(
            displayURLString: "resource-pipeline://reader/test/0",
            sourceID: "protected-reader-source",
            baseURL: URL(string: "https://example.test"),
            rule: Self.resourcePipeline(),
            item: ["id": .string("img-0")],
            root: [:],
            context: [:],
            legacyFallback: legacyReference
        )

        let fallbackData: Data = try await loader.load(
            ProtectedReaderImageReference(execution: .pipeline(pipelineReference)),
            context: context
        )
        #expect(fallbackData == legacyData)

        pipelineReference.legacyFallback = nil
        await #expect(throws: RuleExecutionError.self) {
            _ = try await loader.load(
                ProtectedReaderImageReference(execution: .pipeline(pipelineReference)),
                context: context
            )
        }
    }

    private static func sourceWithProtectedImageAPI() -> Source {
        let protectedResource: ProtectedResourceRule = ProtectedResourceRule(
            type: .encryptedBinary,
            keyRequest: ProtectedResourceRequestRule(url: "https://example.test/key/{imageId}"),
            keyPath: "data.key",
            binaryRequest: ProtectedResourceRequestRule(url: "https://example.test/encrypt/{imageId}/{quality}"),
            decrypt: ProtectedResourceDecryptRule(
                algorithm: .aes,
                mode: .cbc,
                padding: .pkcs7,
                key: ProtectedResourceValueRule(source: .keyResponse, encoding: .base64),
                iv: ProtectedResourceValueRule(source: .keyResponse, path: "data.iv", encoding: .base64),
                ciphertextEncoding: .raw
            ),
            output: ProtectedResourceOutputRule(contentType: .image)
        )
        let rule: SiteRule = SiteRule(
            version: 1,
            site: nil,
            urlPatterns: nil,
            pages: nil,
            ruleSets: nil,
            sharedRequest: nil,
            flags: nil,
            name: "Protected Reader Source",
            baseUrl: "https://example.test",
            list: ListRule(
                id: "updates",
                url: "https://example.test/updates",
                item: ".item",
                title: "a",
                link: "a@href",
                cover: nil,
                type: .comic,
                latestText: nil
            ),
            listTabs: nil,
            detail: DetailRule(
                id: "detail",
                chapterItem: ".chapter a",
                chapterTitle: "this",
                chapterLink: "this@href",
                treatDetailURLAsChapter: true
            ),
            gallery: GalleryRule(
                id: "reader",
                imageAPI: ReaderImageAPIRule(
                    url: "https://example.test/api/chapter/{detailSlug}/images",
                    itemPath: "images[]",
                    urlTemplate: "protected://reader-image?imageId={id}&quality=high",
                    orderPath: "sort",
                    sort: .ascending,
                    protectedResource: protectedResource
                ),
                imageItem: "img",
                imageUrl: "this@src"
            ),
            video: nil
        )

        return Source(
            id: "protected-reader-source",
            name: "Protected Reader Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func sourceWithGalleryProtectedResource() -> Source {
        let protectedResource: ProtectedResourceRule = ProtectedResourceRule(
            type: .encryptedBinary,
            keyRequest: ProtectedResourceRequestRule(url: "https://example.test/key/{id}"),
            keyPath: "data.key",
            binaryRequest: ProtectedResourceRequestRule(url: "https://example.test/encrypt/{id}/{quality}"),
            decrypt: ProtectedResourceDecryptRule(
                algorithm: .aes,
                mode: .cbc,
                padding: .pkcs7,
                key: ProtectedResourceValueRule(source: .keyResponse, encoding: .base64),
                iv: ProtectedResourceValueRule(source: .keyResponse, path: "data.iv", encoding: .base64),
                ciphertextEncoding: .raw
            ),
            output: ProtectedResourceOutputRule(contentType: .image)
        )
        let rule: SiteRule = SiteRule(
            version: 1,
            site: nil,
            urlPatterns: nil,
            pages: nil,
            ruleSets: nil,
            sharedRequest: nil,
            flags: nil,
            name: "Protected Reader Source",
            baseUrl: "https://example.test",
            list: ListRule(
                id: "updates",
                url: "https://example.test/updates",
                item: ".item",
                title: "a",
                link: "a@href",
                cover: nil,
                type: .comic,
                latestText: nil
            ),
            listTabs: nil,
            detail: DetailRule(
                id: "detail",
                chapterItem: ".chapter a",
                chapterTitle: "this",
                chapterLink: "this@href",
                treatDetailURLAsChapter: true
            ),
            gallery: GalleryRule(
                id: "reader",
                protectedResource: GalleryProtectedResourceRule(
                    type: "encryptedBinary",
                    itemSource: ReaderProtectedResourceItemSourceRule(
                        url: "https://example.test/api/chapter/{chapterId}/info",
                        method: .get,
                        headers: ["Accept": "application/json"],
                        itemPath: "data.chapter.proportion[]",
                        idPath: "id",
                        orderPath: "idx",
                        sort: .ascending
                    ),
                    nativeRule: protectedResource
                ),
                imageItem: "canvas",
                imageUrl: ""
            ),
            video: nil
        )

        return Source(
            id: "protected-reader-source",
            name: "Protected Reader Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func sourceWithResourcePipeline(
        policy: ReaderImageResourcePipelineExecutionPolicy
    ) -> Source {
        var source: Source = self.sourceWithProtectedImageAPI()
        var rule: SiteRule = source.rule
        let galleryRule: GalleryRule = GalleryRule(
            id: "pipeline-reader",
            imageAPI: ReaderImageAPIRule(
                url: "https://example.test/api/chapter/{detailSlug}/images",
                itemPath: "images[]",
                resourcePipeline: ReaderImageResourcePipelineRule(
                    executionPolicy: policy,
                    pipeline: self.resourcePipeline()
                ),
                protectedResource: policy == .pipelineWithLegacyFallback
                    ? self.legacyProtectedResource()
                    : nil
            ),
            imageItem: "img",
            imageUrl: "this@src"
        )
        rule.version = 2
        rule.context = [
            "readerAccessToken": SiteRuleContextValue(value: "context-secret")
        ]
        rule.pages = [
            PageRule(
                id: "reader-page",
                title: "Reader",
                type: .reader,
                ruleRefs: RuleRefs(gallery: "pipeline-reader")
            )
        ]
        rule.ruleSets = RuleSets(galleryRules: [galleryRule])
        source.rule = rule
        return source
    }

    private static func resourcePipeline() -> ResourcePipelineRule {
        return ResourcePipelineRule(
            bindings: [
                "imageID": ResourceBindingRule(source: .item, path: "id")
            ],
            steps: [
                ResourcePipelineStepRule(
                    id: "imageData",
                    operation: .request(
                        ResourceRequestOperationRule(
                            urlTemplate: "https://cdn.example.test/{binding.imageID}",
                            responseType: .data
                        )
                    )
                )
            ],
            output: ResourcePipelineOutputRule(
                value: ResourceValueReferenceRule(source: .step, name: "imageData"),
                contentType: .image
            )
        )
    }

    private static func legacyProtectedResource() -> ProtectedResourceRule {
        return ProtectedResourceRule(
            type: .encryptedBinary,
            binaryRequest: ProtectedResourceRequestRule(url: "https://example.test/legacy/{id}"),
            decrypt: ProtectedResourceDecryptRule(
                algorithm: .aes,
                mode: .cbc,
                padding: .pkcs7,
                key: ProtectedResourceValueRule(
                    source: .constant,
                    value: "12345678901234567890123456789012",
                    encoding: .utf8
                ),
                iv: ProtectedResourceValueRule(
                    source: .constant,
                    value: "abcdefghijklmnop",
                    encoding: .utf8
                ),
                ciphertextEncoding: .raw
            ),
            output: ProtectedResourceOutputRule(contentType: .image)
        )
    }

}

private enum StubResourcePipelineError: Error {
    case failed
}

private final class RecordingReaderPageContentLoader: PageContentLoader {
    private enum LoaderError: LocalizedError {
        case missingResponse(String)

        var errorDescription: String? {
            switch self {
            case .missingResponse(let url):
                return "Missing response for URL: \(url)"
            }
        }
    }

    private let responses: [String: String]
    private(set) var requestedURLs: [String] = []

    init(responses: [String: String]) {
        self.responses = responses
    }

    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        let urlString: String = url.absoluteString
        self.requestedURLs.append(urlString)

        guard let response: String = self.responses[urlString] else {
            throw LoaderError.missingResponse(urlString)
        }

        return response
    }
}
