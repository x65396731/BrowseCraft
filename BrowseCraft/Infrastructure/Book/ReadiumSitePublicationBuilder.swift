import BrowseCraftCore
import Foundation
import ReadiumShared

// 中文注释：ReadiumSitePublicationBuilder 把 BookPublicationManifest 建成 Readium `Publication`：
// 正文章节是容器内的 XHTML 资源（按需取正文、装 XHTML），音频章节是远程 href。阅读器与书签复用本地书那一套。

struct ReadiumSitePublicationBuilder: Sendable {
    private let renderer: BookXHTMLRenderer

    init(renderer: BookXHTMLRenderer = BookXHTMLRenderer()) {
        self.renderer = renderer
    }

    func build(manifest: BookPublicationManifest, contentProvider: @escaping BookChapterContentProvider) -> Publication {
        let readingOrder: [Link] = manifest.items.map { item in
            switch item.kind {
            case .text:
                return Link(href: item.href, mediaType: .xhtml, title: item.title)
            case .audio(let mediaType, let duration):
                return Link(href: item.href, mediaType: mediaType.flatMap { MediaType($0) }, title: item.title, duration: duration)
            }
        }
        let metadata: Metadata = Metadata(
            identifier: manifest.identifier,
            conformsTo: manifest.isAudiobook ? [.audiobook] : [],
            title: manifest.title,
            languages: manifest.language.map { [$0] } ?? [],
            authors: manifest.author.map { [Contributor(name: $0)] } ?? []
        )
        let siteContainer: SiteBookChapterContainer = SiteBookChapterContainer(
            manifest: manifest,
            renderer: self.renderer,
            contentProvider: contentProvider
        )
        // 中文注释：AudioNavigator 的媒体加载器只播 `publication.get(link)` 给得出资源的 href；远程 mp3 由 Readium 自带的
        // HTTPContainer 按 Range 取（HTTPResource 的构造器不对外），正文容器与它组合，正文章节仍走前者。
        let audioEntries: Set<AnyURL> = Set(manifest.items.compactMap { item in
            guard case .audio = item.kind else {
                return nil
            }
            return AnyURL(string: item.href)
        })
        let container: Container = audioEntries.isEmpty
            ? siteContainer
            : CompositeContainer(siteContainer, HTTPContainer(client: siteContainer.audioHTTPClient.client, entries: audioEntries))
        return Publication(
            manifest: Manifest(metadata: metadata, readingOrder: readingOrder, tableOfContents: readingOrder),
            container: container
        )
    }
}

/// 中文注释：只承载正文章节的容器；每个 href 对应一个按需取内容的 `DataResource`（首次读取后 Readium 自己缓存）。
final class SiteBookChapterContainer: Container, @unchecked Sendable {
    let sourceURL: AbsoluteURL? = nil
    private(set) var entries: Set<AnyURL> = []
    private let itemsByHref: [String: BookPublicationItem]
    private let language: String?
    private let renderer: BookXHTMLRenderer
    private let contentProvider: BookChapterContentProvider
    /// 中文注释：音频请求客户端（含 http → https 升级代理）；DefaultHTTPClient 对代理是弱引用，由本容器持有。
    let audioHTTPClient: SiteBookAudioHTTPClient = SiteBookAudioHTTPClient()

    init(manifest: BookPublicationManifest, renderer: BookXHTMLRenderer, contentProvider: @escaping BookChapterContentProvider) {
        var byHref: [String: BookPublicationItem] = [:]
        var entries: Set<AnyURL> = []
        for item: BookPublicationItem in manifest.items {
            guard case .text = item.kind else {
                continue
            }
            byHref[item.href] = item
            if let url: AnyURL = AnyURL(string: item.href) {
                entries.insert(url)
            }
        }
        self.itemsByHref = byHref
        self.entries = entries
        self.language = manifest.language
        self.renderer = renderer
        self.contentProvider = contentProvider
    }

    subscript(url: any URLConvertible) -> Resource? {
        let key: String = Self.normalizedHref(url.anyURL.string)
        guard let item: BookPublicationItem = self.itemsByHref[key] else {
            return nil
        }
        let provider: BookChapterContentProvider = self.contentProvider
        let renderer: BookXHTMLRenderer = self.renderer
        let language: String? = self.language
        return DataResource { () async -> ReadResult<Data> in
            do {
                switch try await provider(item.chapterURL) {
                case .text(let title, let paragraphs):
                    return .success(Data(renderer.render(title: title ?? item.title, paragraphs: paragraphs, language: language).utf8))
                case .audio:
                    return .failure(.decoding(BookPublicationContentError.unexpectedContent(chapterURL: item.chapterURL)))
                }
            } catch {
                return .failure(.access(.other(error)))
            }
        }
    }

    func close() async {}

    private static func normalizedHref(_ href: String) -> String {
        var value: String = href
        if value.hasPrefix("/") {
            value.removeFirst()
        }
        return value
    }
}
