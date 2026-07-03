import Foundation
import Nuke
import Testing
@testable import BrowseCraft

// 中文注释：图片请求工厂测试，确认规则中的 imageHeaders/imageRequest.headers 能进入 Nuke URLRequest。
struct ImageRequestFactoryTests {
    @Test func imageRequestHeadersOverrideDefaultAndCurrentReferer() throws {
        let requestConfig: RequestConfig = RequestConfig(
            scope: .image,
            mergePolicy: .mergeHeaders,
            method: nil,
            headers: nil,
            body: nil,
            cookiePolicy: nil,
            cookiePriority: nil,
            cookieScope: nil,
            charset: nil,
            needsWebView: nil,
            autoScroll: nil,
            imageHeaders: [
                "Accept": "image/webp",
                "X-Image-Header": "site"
            ],
            imageRequest: ImageRequestConfig(
                headers: [
                    "Referer": "https://rule.example/reader",
                    "X-Image-Header": "rule"
                ],
                cookiePolicy: nil,
                cookiePriority: nil,
                cookieScope: nil,
                mergePolicy: .mergeHeaders
            )
        )

        let imageRequest = try #require(
            ImageRequestFactory.makeRequest(
                urlString: "https://image.example/page.jpg",
                refererURLString: "https://current.example/chapter",
                requestConfig: requestConfig
            )
        )

        // 中文注释：Nuke 的 urlRequest 为可选值，先确认工厂确实生成 URLRequest，再验证 header 合并优先级。
        let urlRequest = try #require(imageRequest.urlRequest)

        // 中文注释：imageRequest.headers 最具体，应覆盖 imageHeaders 和当前章节 URL 传入的 Referer。
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "image/webp")
        #expect(urlRequest.value(forHTTPHeaderField: "X-Image-Header") == "rule")
        #expect(urlRequest.value(forHTTPHeaderField: "Referer") == "https://rule.example/reader")
    }

    @Test func currentRefererIsUsedWhenRuleDoesNotProvideReferer() throws {
        let requestConfig: RequestConfig = RequestConfig(
            scope: .image,
            mergePolicy: .mergeHeaders,
            method: nil,
            headers: nil,
            body: nil,
            cookiePolicy: nil,
            cookiePriority: nil,
            cookieScope: nil,
            charset: nil,
            needsWebView: nil,
            autoScroll: nil,
            imageHeaders: [
                "X-Image-Header": "site"
            ],
            imageRequest: nil
        )

        let imageRequest = try #require(
            ImageRequestFactory.makeRequest(
                urlString: "https://image.example/page.jpg",
                refererURLString: "https://current.example/chapter",
                requestConfig: requestConfig
            )
        )

        // 中文注释：Nuke 的 urlRequest 为可选值，先确认工厂输出可被图片加载器消费的请求。
        let urlRequest = try #require(imageRequest.urlRequest)

        // 中文注释：规则没有指定 Referer 时继续使用当前页面 URL，保持旧版阅读页图片加载行为。
        #expect(urlRequest.value(forHTTPHeaderField: "Referer") == "https://current.example/chapter")
        #expect(urlRequest.value(forHTTPHeaderField: "X-Image-Header") == "site")
    }

    @Test func imageRequestAppliesImageCookiePolicy() throws {
        let requestConfig: RequestConfig = RequestConfig(
            scope: .image,
            mergePolicy: .mergeHeaders,
            method: nil,
            headers: nil,
            body: nil,
            cookiePolicy: CookiePolicy.none,
            cookiePriority: CookiePriority.none,
            cookieScope: nil,
            charset: nil,
            needsWebView: nil,
            autoScroll: nil,
            imageHeaders: nil,
            imageRequest: ImageRequestConfig(
                headers: [
                    "Cookie": "image_session=rule"
                ],
                cookiePolicy: .custom,
                cookiePriority: .image,
                cookieScope: .image,
                mergePolicy: .mergeHeaders
            )
        )

        let imageRequest = try #require(
            ImageRequestFactory.makeRequest(
                urlString: "https://image.example/page.jpg",
                refererURLString: "https://current.example/chapter",
                requestConfig: requestConfig
            )
        )
        let urlRequest = try #require(imageRequest.urlRequest)

        // 中文注释：图片请求应优先使用 imageRequest 的 Cookie 策略，而不是页面 request 的 none 策略。
        #expect(urlRequest.value(forHTTPHeaderField: "Cookie") == "image_session=rule")
    }
}
