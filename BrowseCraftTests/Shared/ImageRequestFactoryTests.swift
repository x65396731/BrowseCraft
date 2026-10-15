import Foundation
import Nuke
import Testing
@testable import BrowseCraft
import BrowseCraftCore

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

    @Test func itemThumbnailCacheKeyIgnoresRefererButKeepsContentHeaders() throws {
        let url: URL = try #require(URL(string: "https://image.example/item.jpg?size=small"))
        var firstRequest: URLRequest = URLRequest(url: url)
        firstRequest.setValue("https://site.example/detail-a", forHTTPHeaderField: "Referer")
        firstRequest.setValue("image/webp", forHTTPHeaderField: "Accept")

        var secondRequest: URLRequest = URLRequest(url: url)
        secondRequest.setValue("https://site.example/detail-b", forHTTPHeaderField: "Referer")
        secondRequest.setValue("image/webp", forHTTPHeaderField: "Accept")

        var cookieRequest: URLRequest = URLRequest(url: url)
        cookieRequest.setValue("https://site.example/detail-a", forHTTPHeaderField: "Referer")
        cookieRequest.setValue("image/webp", forHTTPHeaderField: "Accept")
        cookieRequest.setValue("session=abc", forHTTPHeaderField: "Cookie")

        #expect(
            ItemThumbnailImageCachePlugin.cacheKey(url: url, request: firstRequest)
                == ItemThumbnailImageCachePlugin.cacheKey(url: url, request: secondRequest)
        )
        #expect(
            ItemThumbnailImageCachePlugin.cacheKey(url: url, request: firstRequest)
                != ItemThumbnailImageCachePlugin.cacheKey(url: url, request: cookieRequest)
        )
    }

    /// 中文注释：Cookie 只按名字进键——会话值轮换不能让该站的缩略图缓存整体失效（2026-10-10 复审 B-1）。
    @Test func itemThumbnailCacheKeyIgnoresCookieValuesButKeepsCookieNames() throws {
        let url: URL = try #require(URL(string: "https://image.example/item.jpg"))
        var firstRequest: URLRequest = URLRequest(url: url)
        firstRequest.setValue("session=abc; theme=dark", forHTTPHeaderField: "Cookie")
        var rotatedRequest: URLRequest = URLRequest(url: url)
        rotatedRequest.setValue("theme=light; session=xyz", forHTTPHeaderField: "Cookie")
        var differentNamesRequest: URLRequest = URLRequest(url: url)
        differentNamesRequest.setValue("session=abc", forHTTPHeaderField: "Cookie")

        #expect(
            ItemThumbnailImageCachePlugin.cacheKey(url: url, request: firstRequest)
                == ItemThumbnailImageCachePlugin.cacheKey(url: url, request: rotatedRequest)
        )
        #expect(
            ItemThumbnailImageCachePlugin.cacheKey(url: url, request: firstRequest)
                != ItemThumbnailImageCachePlugin.cacheKey(url: url, request: differentNamesRequest)
        )
    }

    /// 中文注释：`BCA-RUNTIME-011`——默认按浏览器带当前页面 Referer（bhtv001 ← xz.kanrenao.cn 不带即 404），地址升成 https。
    @Test func insecureImageKeepsPageRefererByDefault() throws {
        let imageRequest = try #require(
            ImageRequestFactory.makeRequest(
                urlString: "http://oss.example/comic/page/1.jpg",
                refererURLString: "https://current.example/chapter"
            )
        )
        let urlRequest = try #require(imageRequest.urlRequest)

        #expect(urlRequest.url?.absoluteString == "https://oss.example/comic/page/1.jpg")
        #expect(urlRequest.value(forHTTPHeaderField: "Referer") == "https://current.example/chapter")
    }

    /// 中文注释：失败后的重试不带当前页面 Referer（umh5 ← oss.mkzcdn.com 带即 403）。
    @Test func omitPageRefererDropsCurrentPageReferer() throws {
        let imageRequest = try #require(
            ImageRequestFactory.makeRequest(
                urlString: "http://oss.example/comic/page/1.jpg",
                refererURLString: "https://current.example/chapter",
                omitPageReferer: true
            )
        )
        let urlRequest = try #require(imageRequest.urlRequest)

        #expect(urlRequest.value(forHTTPHeaderField: "Referer") == nil)
    }

    /// 中文注释：规则显式给的 Referer 不受重试开关影响。
    @Test func omitPageRefererKeepsRuleReferer() throws {
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
            imageHeaders: ["Referer": "https://rule.example/reader"],
            imageRequest: nil
        )
        let imageRequest = try #require(
            ImageRequestFactory.makeRequest(
                urlString: "http://oss.example/comic/page/1.jpg",
                refererURLString: "https://current.example/chapter",
                requestConfig: requestConfig,
                omitPageReferer: true
            )
        )
        let urlRequest = try #require(imageRequest.urlRequest)

        #expect(urlRequest.value(forHTTPHeaderField: "Referer") == "https://rule.example/reader")
    }

    /// 中文注释：每个候选地址先带 Referer、再不带；没有当前页面时只留一次。
    @Test func remoteImageAttemptsTryPageRefererFirst() {
        let attempts: [RemoteImageAttempt] = RemoteImageAttempt.attempts(
            for: ["https://a.example/1.jpg", "https://b.example/2.jpg"],
            refererURLString: "https://site.example/detail"
        )
        #expect(attempts == [
            RemoteImageAttempt(urlString: "https://a.example/1.jpg", omitPageReferer: false),
            RemoteImageAttempt(urlString: "https://a.example/1.jpg", omitPageReferer: true),
            RemoteImageAttempt(urlString: "https://b.example/2.jpg", omitPageReferer: false),
            RemoteImageAttempt(urlString: "https://b.example/2.jpg", omitPageReferer: true)
        ])
        #expect(
            RemoteImageAttempt.attempts(for: ["https://a.example/1.jpg"], refererURLString: nil)
                == [RemoteImageAttempt(urlString: "https://a.example/1.jpg", omitPageReferer: false)]
        )
    }

    /// 中文注释：缩略图键区分「带不带 Referer」，不带 Referer 的重试不会被 Nuke 合并进带 Referer 的任务。
    @Test func itemThumbnailCacheKeySeparatesRefererPresence() throws {
        let url: URL = try #require(URL(string: "https://image.example/item.jpg"))
        var withReferer: URLRequest = URLRequest(url: url)
        withReferer.setValue("https://site.example/detail-a", forHTTPHeaderField: "Referer")
        let withoutReferer: URLRequest = URLRequest(url: url)

        #expect(
            ItemThumbnailImageCachePlugin.cacheKey(url: url, request: withReferer)
                != ItemThumbnailImageCachePlugin.cacheKey(url: url, request: withoutReferer)
        )
    }
}
