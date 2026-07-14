import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：RSS 图片过滤测试，保护正文图片、二维码与装饰图片之间的边界。
@MainActor
struct RSSImageFilteringTests {
    @Test func parserRejectsReactionImagesAndKeepsQRCodeAndArticleImages() throws {
        let html: String = """
        <html><body>
          <article>
            <p>正文</p>
            <div class="qrcode-box">
              <img src="https://example.test/qrcode.png">
            </div>
            <div class="align align--middle reaction-item-button">
              <img src="/static/img/upvote.png">
            </div>
            <img src="https://cdn.example.test/article.jpg">
          </article>
        </body></html>
        """

        let blocks: [RSSContentPayload.Block] = RSSDetailHTMLParser.detailContentBlocks(
            in: html,
            pageURL: try #require(URL(string: "https://example.test/article"))
        )
        let imageURLs: [String] = blocks.compactMap(\.imageURL)

        #expect(imageURLs.contains("https://example.test/qrcode.png"))
        #expect(imageURLs.contains("https://cdn.example.test/article.jpg"))
        #expect(imageURLs.contains("https://example.test/static/img/upvote.png") == false)
    }

    @Test func viewModelRejectsDirectoryImageURLWithoutQuery() {
        #expect(
            RSSContentDetailViewModel.rssImageRejectionReason(
                "https://www.dongwm.com/static/upload/"
            ) == "directory-url"
        )
    }

    @Test func viewModelKeepsExtensionlessCDNImageAndDynamicDirectoryEndpoint() {
        #expect(
            RSSContentDetailViewModel.rssImageRejectionReason(
                "https://cdn.example.test/image/asset-123"
            ) == nil
        )
        #expect(
            RSSContentDetailViewModel.rssImageRejectionReason(
                "https://cdn.example.test/image/?id=asset-123"
            ) == nil
        )
    }

    @Test func viewModelKeepsRegularImageURL() {
        #expect(
            RSSContentDetailViewModel.rssImageRejectionReason(
                "https://cdn.example.test/article.webp"
            ) == nil
        )
    }

    @Test func detailViewDoesNotExposeOriginalWebViewForHTTPURL() throws {
        let httpURL: URL = try #require(URL(string: "http://politics.people.com.cn/n1/2025/0605/c1001-40494900.html"))
        let httpsURL: URL = try #require(URL(string: "https://politics.people.com.cn/n1/2025/0605/c1001-40494900.html"))

        #expect(RSSContentDetailView.supportsOriginalWebViewURL(httpURL) == false)
        #expect(RSSContentDetailView.supportsOriginalWebViewURL(httpsURL) == true)
    }
}
