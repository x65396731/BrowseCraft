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
    /// 中文注释：播放页型有声章节（fwq 设计稿第 46 节 A1）：href 是章节播放页，真正的音频地址要等播放时取页解析
    /// （`SiteBookPageAudioResolver`）；章节地址本身是音频文件时为 false。
    var audioResolvedFromPage: Bool = false
}

struct BookPublicationManifest: Hashable, Sendable {
    let identifier: String
    let title: String
    let author: String?
    let language: String?
    let coverURL: URL?
    let items: [BookPublicationItem]
    /// 中文注释：简介——Runtime 的 `metadata.description`，详情页有才出（`docs/design/Book-Detail-Page-Redesign-Design.md` 第五节）。
    var description: String? = nil

    var isAudiobook: Bool {
        return self.items.contains { if case .audio = $0.kind { return true } else { return false } }
    }

    /// 中文注释：音频章节全是 HLS（规则 `media.format = hls`，或章节地址扩展名 m3u8）——播放走 App 自己的 HLS 内核，
    /// 不走 Readium（fwq 设计稿第 83 节）。读取规则的格式是整条规则一个值，按整本判。
    var isHLSAudiobook: Bool {
        var audioMediaTypes: [String?] = []
        for item: BookPublicationItem in self.items {
            if case .audio(let mediaType, _) = item.kind {
                audioMediaTypes.append(mediaType)
            }
        }
        return audioMediaTypes.isEmpty == false
            && audioMediaTypes.allSatisfy { $0 == BookMediaFormat.hls.rwpmMediaType }
    }

    /// 中文注释：播放走 App 自己的内核（`SiteHLSAudioPlayer`）：音频全是 HLS，或有播放页型章节（`audioResolvedFromPage`）。
    /// 后者的真实音频地址要播放时取页才知道，Readium 却在建出版物时就把格式写死在链接上（`PublicationMediaLoader`
    /// 以链接媒体类型填 `contentType`），只能用规则的 `media.format`；规则按样本写死、全站格式不一时解析失败
    ///（2026-10-24 hentaiasmr 中文区外站 mp3 被标成 m4a，AVFoundation -11829）。链接不带格式也不行：播放器不发请求。
    /// App 内核播放时才解析、用真实 https 地址建播放项，格式由系统按真实地址判断，规则的 `media.format` 不起作用。
    var usesAppAudioEngine: Bool {
        return self.isHLSAudiobook || self.items.contains { $0.audioResolvedFromPage }
    }
}

/// 中文注释：按需取一章内容的端口；Runtime 的 `loadBookContent` 在用例里被包成这个闭包。
typealias BookChapterContentProvider = @Sendable (URL) async throws -> SourceBookChapterContent

/// 中文注释：Runtime 报的内容与 manifest 期望的形态不一致（如正文章节却回来音频）。
enum BookPublicationContentError: Error, Equatable, Sendable {
    case unexpectedContent(chapterURL: URL)
}
