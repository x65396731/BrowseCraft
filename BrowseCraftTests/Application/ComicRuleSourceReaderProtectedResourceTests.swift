import Foundation
import Testing
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
            "protected://reader-image?imageId=img-0&quality=2",
            "protected://reader-image?imageId=img-1&quality=2"
        ])
        #expect(chapter.pageResources.count == 2)

        guard case .protectedResource(let firstReference) = chapter.pageResources[0] else {
            Issue.record("Expected first page to be protectedResource")
            return
        }
        #expect(firstReference.sourceID == "protected-reader-source")
        #expect(firstReference.baseURL?.absoluteString == "https://example.test")
        #expect(firstReference.parameters["imageId"] == "img-0")
        #expect(firstReference.parameters["quality"] == "high")
        #expect(firstReference.parameters["id"] == "img-0")
        #expect(firstReference.rule.binaryRequest.url == "https://example.test/encrypt/{imageId}/{quality}")
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
        #expect(firstReference.parameters["imageId"] == "img-1")
        #expect(firstReference.parameters["id"] == "img-1")
        #expect(firstReference.parameters["quality"] == "2")
        #expect(firstReference.rule.binaryRequest.url == "https://example.test/encrypt/{id}/{quality}")
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
