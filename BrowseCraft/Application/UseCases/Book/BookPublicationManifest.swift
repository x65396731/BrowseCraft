import BrowseCraftCore
import Foundation

// 中文注释：BookPublicationManifest 是站点书装成 Readium 出版物前的纯值中间层（BC-BOOK-012 的对应表）：
// metadata 来自 detail，readingOrder 来自章节，每一项的内容由 provider 按需取（正文装成 XHTML，音频是远程地址）。
// Application 不依赖 Readium；Infrastructure 的 ReadiumSitePublicationBuilder 把它建成 `Publication`。

struct BookPublicationItem: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// 中文注释：正文章节，资源由 provider 取回并装成 XHTML；href 是出版物内的相对路径。
        case text
        /// 中文注释：音频章节，href 是远程地址；Readium 直接播放。
        case audio(mediaType: String?, durationSeconds: Double?)
    }

    let href: String
    let title: String
    /// 中文注释：站点上的章节地址；正文章节取内容时用它，音频章节它就是 href。
    let chapterURL: URL
    let kind: Kind
}

struct BookPublicationManifest: Hashable, Sendable {
    let identifier: String
    let title: String
    let author: String?
    let language: String?
    let coverURL: URL?
    let items: [BookPublicationItem]

    var isAudiobook: Bool {
        return self.items.contains { if case .audio = $0.kind { return true } else { return false } }
    }
}

/// 中文注释：按需取一章内容的端口；Runtime 的 `loadBookContent` 在用例里被包成这个闭包。
typealias BookChapterContentProvider = @Sendable (URL) async throws -> SourceBookChapterContent

/// 中文注释：Runtime 报的内容与 manifest 期望的形态不一致（如正文章节却回来音频）。
enum BookPublicationContentError: Error, Equatable, Sendable {
    case unexpectedContent(chapterURL: URL)
}
