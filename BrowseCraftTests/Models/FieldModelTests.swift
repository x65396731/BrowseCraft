import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：字段模型测试，覆盖列表、详情、章节字段的扩展解码能力。
struct FieldModelTests {
    @Test func listFieldsDecodeDisplayAndMediaMetadata() throws {
        let json: String = """
        {
          "title": {
            "selector": ".title",
            "function": "text"
          },
          "cover": {
            "selector": "img.cover",
            "function": "attr",
            "param": "src"
          },
          "largeImage": {
            "selector": "img.large",
            "function": "attr",
            "param": "data-src"
          },
          "video": {
            "selector": "video source",
            "function": "attr",
            "param": "src"
          },
          "detailURL": {
            "selector": "a.title",
            "function": "url"
          },
          "uploader": {
            "selector": ".uploader",
            "function": "text"
          },
          "datetime": {
            "selector": "time",
            "function": "attr",
            "param": "datetime"
          }
        }
        """

        let fields: ListFields = try JSONDecoder().decode(
            ListFields.self,
            from: Data(json.utf8)
        )

        // 中文注释：列表卡片需要同时支持缩略图、大图和视频入口，覆盖复杂站点的列表字段。
        #expect(fields.title.selector == ".title")
        #expect(fields.cover?.selector == "img.cover")
        #expect(fields.largeImage?.selector == "img.large")
        #expect(fields.video?.selector == "video source")
        #expect(fields.detailURL.selector == "a.title")
        // 中文注释：uploader/datetime 与 author/publishedAt 并存，避免把上传者和作者、原发布时间混成一个字段。
        #expect(fields.uploader?.selector == ".uploader")
        #expect(fields.datetime?.selector == "time")
        #expect(fields.datetime?.param == "datetime")
    }

    @Test func detailFieldsDecodeSecondLevelPageMetadata() throws {
        let json: String = """
        {
          "title": {
            "selector": "h1",
            "function": "text"
          },
          "totalImages": {
            "selector": ".page-count",
            "function": "text",
            "regex": "(\\\\d+)"
          },
          "photoAlbumLink": {
            "selector": "a.album",
            "function": "url"
          },
          "secondLevelPageURL": {
            "selector": "a.reader",
            "function": "url"
          }
        }
        """

        let fields: DetailFields = try JSONDecoder().decode(
            DetailFields.self,
            from: Data(json.utf8)
        )

        // 中文注释：详情页需要能记录总页数，供后续分页阅读器或进度展示使用。
        #expect(fields.title?.selector == "h1")
        #expect(fields.totalImages?.selector == ".page-count")
        #expect(fields.totalImages?.regex == "(\\d+)")
        // 中文注释：photoAlbumLink 保留 Yealico 命名，secondLevelPageURL 提供非相册站点的通用表达。
        #expect(fields.photoAlbumLink?.selector == "a.album")
        #expect(fields.secondLevelPageURL?.selector == "a.reader")
    }

    @Test func chapterRuleDecodesChapterURLPlaceholderAlias() throws {
        let json: String = """
        {
          "item": {
            "selector": "a.chapter",
            "function": "raw"
          },
          "idCode": {
            "selector": "a.chapter",
            "function": "attr",
            "param": "data-id"
          },
          "cidCode": {
            "selector": "a.chapter",
            "function": "attr",
            "param": "data-cid"
          },
          "title": {
            "selector": "a.chapter",
            "function": "text"
          },
          "url": {
            "selector": "a.chapter",
            "function": "url"
          }
        }
        """

        let chapterRule: ChapterRule = try JSONDecoder().decode(
            ChapterRule.self,
            from: Data(json.utf8)
        )

        // 中文注释：idCode 保持作品/条目稳定标识语义，cidCode 明确服务于章节 URL 占位符 {cidCode:}。
        #expect(chapterRule.idCode?.param == "data-id")
        #expect(chapterRule.cidCode?.param == "data-cid")
        #expect(chapterRule.title.selector == "a.chapter")
        #expect(chapterRule.url.function == .url)
    }
}
