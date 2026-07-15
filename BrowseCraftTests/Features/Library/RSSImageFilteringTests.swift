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

    @Test func parserLimitsBBCLearningEnglishArticleBeforeArchiveList() throws {
        let html: String = """
        <html><body>
          <noscript><p><img src="https://a1.api.bbc.co.uk/hit.xiti?col=1" height="1" width="1"></p></noscript>
          <div id="bbcle-content" class="content-no-sidebar b-g-p">
            <div role="article">
              <div class="widget-container widget-container-left">
                <div class="widget widget-heading"><h3>媒体英语</h3></div>
                <div class="widget widget-audio widget-audio-standard">
                  <img src="https://ichef.bbc.co.uk/images/ic/640x360/p0nwg25x.jpg">
                </div>
                <div class="widget widget-richtext 6">
                  <div class="text">
                    <p class="BBCText">正文第一段</p>
                    <p class="BBCText">正文第二段</p>
                  </div>
                </div>
                <div class="widget widget-list widget-list-automatic">
                  <ul>
                    <li class="item"><img src="https://ichef.bbci.co.uk/images/ic/256xn/archive-one.jpg"></li>
                    <li class="item"><img src="https://ichef.bbci.co.uk/images/ic/256xn/archive-two.jpg"></li>
                  </ul>
                </div>
              </div>
            </div>
          </div>
        </body></html>
        """

        let blocks: [RSSContentPayload.Block] = RSSDetailHTMLParser.detailContentBlocks(
            in: html,
            pageURL: try #require(URL(string: "https://www.bbc.co.uk/learningenglish/chinese/features/media-english/ep-260713"))
        )
        let texts: [String] = blocks.compactMap(\.text)
        let imageURLs: [String] = blocks.compactMap(\.imageURL)

        #expect(texts.contains("正文第一段"))
        #expect(texts.contains("正文第二段"))
        #expect(imageURLs == ["https://ichef.bbc.co.uk/images/ic/640x360/p0nwg25x.jpg"])
    }

    @Test func viewModelRejectsBBCTrackingImages() {
        #expect(
            RSSContentDetailViewModel.rssImageRejectionReason(
                "https://a1.api.bbc.co.uk/hit.xiti?col=1"
            ) == "tracking-pixel"
        )
        #expect(
            RSSContentDetailViewModel.rssImageRejectionReason(
                "https://sb.scorecardresearch.com/b?c2=19999701"
            ) == "tracking-pixel"
        )
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
