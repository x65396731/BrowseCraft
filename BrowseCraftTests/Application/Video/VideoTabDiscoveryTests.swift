import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：P5.1.8 固定视频 tab discovery 合同：tab 来自页面结构，不来自硬编码分类数量。
struct VideoTabDiscoveryTests {
    @Test func macCMSDiscoveryUsesOnlyDiscoveredCategoryLinks() throws {
        let entryURL: URL = try #require(URL(string: "https://video.example.test/"))
        let definition: VideoSourceDefinition = Self.videoDefinition(
            adapter: .macCMS,
            entryURL: entryURL
        )
        let discoverer: MacCMSVideoTabDiscoverer = MacCMSVideoTabDiscoverer()

        let tabs: [VideoSourceListTab] = try discoverer.discoverTabs(
            html: """
            <html>
              <body>
                <nav>
                  <a href="/">首页</a>
                  <a href="/vodtype/1.html">电影</a>
                  <a href="/vodtype/9.html">短剧</a>
                  <a href="/about.html">关于</a>
                </nav>
              </body>
            </html>
            """,
            definition: definition,
            pageURL: entryURL
        )

        #expect(tabs.map(\.title) == ["首页", "电影", "短剧"])
        #expect(tabs.count == 3)
        #expect(tabs.allSatisfy { tab in
            tab.id.hasPrefix("video.")
        })
    }

    @Test func genericHTMLDiscoveryFindsSameSiteNavigationTabs() throws {
        let entryURL: URL = try #require(URL(string: "https://video.example.test/"))
        let definition: VideoSourceDefinition = Self.videoDefinition(
            adapter: .genericHTML,
            entryURL: entryURL
        )
        let discoverer: GenericHTMLVideoTabDiscoverer = GenericHTMLVideoTabDiscoverer()

        let tabs: [VideoSourceListTab] = try discoverer.discoverTabs(
            html: """
            <html>
              <body>
                <header>
                  <a href="/">首页</a>
                  <a href="/new">新片</a>
                  <a href="/popular">热门</a>
                  <a href="/login">登录</a>
                  <a href="https://ads.example.test/click">广告</a>
                </header>
                <section class="video-list">
                  <article class="video-card">
                    <a href="/watch/sample"><img data-src="/cover.jpg" alt="Sample"></a>
                  </article>
                </section>
              </body>
            </html>
            """,
            definition: definition,
            pageURL: entryURL
        )

        #expect(tabs.map(\.title) == ["首页", "新片", "热门"])
        #expect(tabs.count == 3)
        #expect(tabs.dropFirst().allSatisfy { tab in
            tab.url.hasPrefix("https://video.example.test/")
        })
    }

    @Test func genericHTMLDiscoveryFallsBackToHomeWhenNoTabSignalsExist() throws {
        let entryURL: URL = try #require(URL(string: "https://video.example.test/"))
        let definition: VideoSourceDefinition = Self.videoDefinition(
            adapter: .genericHTML,
            entryURL: entryURL
        )
        let discoverer: GenericHTMLVideoTabDiscoverer = GenericHTMLVideoTabDiscoverer()

        let tabs: [VideoSourceListTab] = try discoverer.discoverTabs(
            html: """
            <html>
              <body>
                <main>
                  <article><a href="/watch/sample">Sample</a></article>
                </main>
              </body>
            </html>
            """,
            definition: definition,
            pageURL: entryURL
        )

        #expect(tabs.map(\.id) == ["video.home"])
        #expect(tabs.map(\.title) == ["首页"])
    }

    private static func videoDefinition(
        adapter: VideoAdapter,
        entryURL: URL
    ) -> VideoSourceDefinition {
        return VideoSourceDefinition(
            adapter: adapter,
            entryURL: entryURL,
            seedURL: nil,
            entryKind: .home,
            routePatterns: adapter == .macCMS ? .macCMS : nil,
            playbackPolicy: .playPageFirst,
            requiresAccount: false,
            seedVodID: nil,
            seedSourceIndex: nil,
            seedEpisodeIndex: nil,
            seedDetailURL: nil,
            seedPlayURL: nil
        )
    }
}
