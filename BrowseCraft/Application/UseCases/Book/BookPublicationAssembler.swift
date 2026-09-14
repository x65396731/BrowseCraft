import BrowseCraftCore
import BrowseCraftDomain
import Foundation

// 中文注释：BookPublicationAssembler 把 Runtime 的详情输出装成 BookPublicationManifest：
// 章节即音频（BC-BOOK-051）的作品装成有声出版物；其余章节装成正文出版物，href 按顺序编号。

/// 中文注释：站点书展示标题——列表条目标题与详情规则标题**一个包含另一个时取较短的**，否则用详情标题。
/// 两边各有一种站点把书名包在多余文字里：biquhua 列表带分类前缀「[玄幻]普罗之主」、详情是「普罗之主」；
/// sfacg 详情规则只能取目录页 `<title>`「大傩目录列表 - 小说频道 - SF轻小说」、列表是「大傩」（目录页上没有书名元素）。
/// loyalbooks 两边相同。只看两串的包含关系，不认站点、不认后缀词表（2026-09-15 用户裁决）。
enum SiteBookTitle {
    static func preferred(itemTitle: String, detailTitle: String?) -> String {
        let item: String = itemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail: String = (detailTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return item
        }
        if item.isEmpty {
            return detail
        }
        if detail.contains(item) {
            return item
        }
        if item.contains(detail) {
            return detail
        }
        return detail
    }
}

struct BookPublicationAssembler: Sendable {
    func assemble(source: Source, detailURL: URL, detail: SourceDetailOutput) -> BookPublicationManifest {
        let audioExtensions: Set<String> = ["mp3", "m4a", "m4b", "mp4", "aac", "m3u8"]
        let items: [BookPublicationItem] = detail.chapters.enumerated().map { index, chapter in
            let isAudio: Bool = audioExtensions.contains(chapter.url.pathExtension.lowercased())
            return BookPublicationItem(
                href: isAudio ? chapter.url.absoluteString : String(format: "chapters/%04d.xhtml", index + 1),
                title: chapter.title,
                chapterURL: chapter.url,
                kind: isAudio ? .audio(mediaType: Self.audioMediaType(for: chapter.url), durationSeconds: nil) : .text
            )
        }
        return BookPublicationManifest(
            identifier: "\(source.id)::\(detailURL.absoluteString)",
            title: detail.metadata?.title ?? source.name,
            author: detail.metadata?.author,
            language: detail.metadata?.language.flatMap { $0.isEmpty ? nil : $0 },
            coverURL: detail.metadata?.coverURL,
            items: items
        )
    }

    private static func audioMediaType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "mp3": return BookMediaFormat.mp3.rwpmMediaType
        case "m4a", "m4b", "mp4": return BookMediaFormat.m4a.rwpmMediaType
        case "aac": return BookMediaFormat.aac.rwpmMediaType
        case "m3u8": return BookMediaFormat.hls.rwpmMediaType
        default: return nil
        }
    }
}

/// 中文注释：正文段落 → XHTML（BC-BOOK-012：`readingOrder[].type = text/html`）；只做转义与包装，不注入样式以外的任何脚本。
struct BookXHTMLRenderer: Sendable {
    func render(title: String?, paragraphs: [String], language: String?) -> String {
        let lang: String = Self.escaped(language ?? "")
        let langAttribute: String = lang.isEmpty ? "" : " xml:lang=\"\(lang)\" lang=\"\(lang)\""
        var body: String = ""
        if let title: String = title, title.isEmpty == false {
            body += "<h1>\(Self.escaped(title))</h1>\n"
        }
        for paragraph: String in paragraphs where paragraph.isEmpty == false {
            body += "<p>\(Self.escaped(paragraph))</p>\n"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"\(langAttribute)>
        <head><meta charset="UTF-8"/><title>\(Self.escaped(title ?? ""))</title></head>
        <body>
        \(body)</body>
        </html>
        """
    }

    private static func escaped(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
