import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：请求配置模型测试，覆盖请求层级、合并策略、Cookie 优先级和图片请求配置。
struct RequestConfigModelTests {
    @Test func requestPriorityAndImageRequestShapeDecode() throws {
        let json: String = """
        {
          "scope": "rule",
          "mergePolicy": "mergeHeadersAndCookies",
          "method": "GET",
          "headers": {
            "User-Agent": "BrowseCraftTest",
            "Referer": "https://example.test/"
          },
          "cookiePolicy": "browserThenCustom",
          "cookiePriority": "custom",
          "cookieScope": "rule",
          "charset": "utf8",
          "needsWebView": true,
          "autoScroll": true,
          "imageHeaders": {
            "Accept": "image/avif,image/webp,image/*"
          },
          "imageRequest": {
            "mergePolicy": "mergeHeaders",
            "headers": {
              "Referer": "https://image.example/"
            },
            "cookiePolicy": "browser",
            "cookiePriority": "image",
            "cookieScope": "image"
          }
        }
        """

        let request: RequestConfig = try JSONDecoder().decode(
            RequestConfig.self,
            from: Data(json.utf8)
        )

        // 中文注释：请求配置需要显式记录来源层级，后续执行器才能按 Rule > Page > Site 解释覆盖关系。
        #expect(request.scope == .rule)
        #expect(request.mergePolicy == .mergeHeadersAndCookies)
        #expect(request.method == .get)
        #expect(request.headers?["Referer"] == "https://example.test/")
        // 中文注释：cookiePolicy 负责是否使用 Cookie，cookiePriority 负责多来源 Cookie 冲突时谁优先。
        #expect(request.cookiePolicy == .browserThenCustom)
        #expect(request.cookiePriority == .custom)
        #expect(request.cookieScope == .rule)
        #expect(request.charset == .utf8)
        #expect(request.needsWebView == true)
        #expect(request.autoScroll == true)
        // 中文注释：imageHeaders 保持旧的轻量写法，imageRequest 允许图片请求独立声明 referer/cookie 合并策略。
        #expect(request.imageHeaders?["Accept"] == "image/avif,image/webp,image/*")
        #expect(request.imageRequest?.mergePolicy == .mergeHeaders)
        #expect(request.imageRequest?.headers?["Referer"] == "https://image.example/")
        #expect(request.imageRequest?.cookiePolicy == .browser)
        #expect(request.imageRequest?.cookiePriority == .image)
        #expect(request.imageRequest?.cookieScope == .image)
    }

    @Test func legacyRequestConfigShapeDecodesWithoutPriorityFields() throws {
        let json: String = """
        {
          "method": "POST",
          "headers": {
            "Content-Type": "application/x-www-form-urlencoded"
          },
          "body": {
            "contentType": "application/x-www-form-urlencoded",
            "value": "q=keyword"
          },
          "cookiePolicy": "custom",
          "charset": "auto",
          "imageHeaders": {
            "Referer": "https://example.test/"
          }
        }
        """

        let request: RequestConfig = try JSONDecoder().decode(
            RequestConfig.self,
            from: Data(json.utf8)
        )

        // 中文注释：旧 RequestConfig 不包含 scope/merge/cookiePriority 字段时，必须继续正常 decode。
        #expect(request.scope == nil)
        #expect(request.mergePolicy == nil)
        #expect(request.cookiePriority == nil)
        #expect(request.cookieScope == nil)
        #expect(request.imageRequest == nil)
        // 中文注释：旧请求字段和 imageHeaders 仍然保持原有语义。
        #expect(request.method == .post)
        #expect(request.headers?["Content-Type"] == "application/x-www-form-urlencoded")
        #expect(request.body?.value == "q=keyword")
        #expect(request.cookiePolicy == .custom)
        #expect(request.charset == .auto)
        #expect(request.imageHeaders?["Referer"] == "https://example.test/")
    }
}
