import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：嵌套规则模型测试，覆盖标签、评论和视频等详情页子结构。
struct NestedRuleModelTests {
    @Test func detailRuleDecodesSemanticTagAndCommentRules() throws {
        let json: String = """
        {
          "tagRule": {
            "item": {
              "selector": ".tags a",
              "function": "raw"
            },
            "name": {
              "selector": "this",
              "function": "text"
            },
            "url": {
              "selector": "this",
              "function": "url"
            }
          },
          "commentRule": {
            "item": {
              "selector": ".comment",
              "function": "raw"
            },
            "avatar": {
              "selector": "img.avatar",
              "function": "attr",
              "param": "src"
            },
            "username": {
              "selector": ".user",
              "function": "text"
            },
            "datetime": {
              "selector": "time",
              "function": "attr",
              "param": "datetime"
            },
            "content": {
              "selector": ".content",
              "function": "text"
            }
          }
        }
        """

        let detailRule: DetailRule = try JSONDecoder().decode(
            DetailRule.self,
            from: Data(json.utf8)
        )

        // 中文注释：tagRule 使用语义化标签规则，避免把标签名、链接和展示文本都塞进通用 text/title。
        #expect(detailRule.tagRule?.item.selector == ".tags a")
        #expect(detailRule.tagRule?.name?.selector == "this")
        #expect(detailRule.tagRule?.url?.function == .url)
        // 中文注释：commentRule 需要明确头像、用户名、时间和正文，不再只靠 title/text 猜语义。
        #expect(detailRule.commentRule?.item.selector == ".comment")
        #expect(detailRule.commentRule?.avatar?.selector == "img.avatar")
        #expect(detailRule.commentRule?.username?.selector == ".user")
        #expect(detailRule.commentRule?.datetime?.param == "datetime")
        #expect(detailRule.commentRule?.content?.selector == ".content")
    }

    @Test func detailRuleDecodesStructuredVideoRule() throws {
        let json: String = """
        {
          "videoRule": {
            "item": {
              "selector": "video, .video",
              "function": "raw"
            },
            "url": {
              "selector": "source",
              "function": "attr",
              "param": "src"
            },
            "thumbnail": {
              "selector": "video",
              "function": "attr",
              "param": "poster"
            },
            "link": {
              "selector": "a.video-link",
              "function": "url"
            },
            "title": {
              "selector": ".video-title",
              "function": "text"
            }
          }
        }
        """

        let detailRule: DetailRule = try JSONDecoder().decode(
            DetailRule.self,
            from: Data(json.utf8)
        )

        // 中文注释：VideoRule 使用和 PictureRule 接近的 item/url/thumbnail/link 结构，方便统一媒体处理。
        #expect(detailRule.videoRule?.item?.selector == "video, .video")
        #expect(detailRule.videoRule?.url?.selector == "source")
        #expect(detailRule.videoRule?.url?.param == "src")
        #expect(detailRule.videoRule?.thumbnail?.param == "poster")
        #expect(detailRule.videoRule?.link?.selector == "a.video-link")
        #expect(detailRule.videoRule?.title?.selector == ".video-title")
    }

    @Test func legacyVideoURLShapeStillDecodes() throws {
        let json: String = """
        {
          "videoUrl": "https://media.example/video.mp4"
        }
        """

        let videoRule: VideoRule = try JSONDecoder().decode(
            VideoRule.self,
            from: Data(json.utf8)
        )

        // 中文注释：顶层旧版 video.videoUrl 仍要能 decode，避免结构化 VideoRule 破坏既有规则。
        #expect(videoRule.videoUrl == "https://media.example/video.mp4")
        #expect(videoRule.item == nil)
        #expect(videoRule.url == nil)
    }
}
