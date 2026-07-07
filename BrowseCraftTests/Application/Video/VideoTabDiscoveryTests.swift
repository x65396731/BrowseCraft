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

    @Test func addVideoSourceUseCaseCanPersistDiscoveredGenericHTMLTabsWhenHTMLIsProvided() throws {
        let repository: VideoTabDiscoveryInMemorySourceRepository = VideoTabDiscoveryInMemorySourceRepository()
        let useCase: AddVideoSourceUseCase = AddVideoSourceUseCase(
            sourceRepository: repository,
            makeID: { "video.example" }
        )

        let result: AddVideoSourceResult = try useCase.execute(
            entryURLString: "https://video.example.test/",
            name: "Video Example",
            entryHTML: """
            <html>
              <body>
                <nav>
                  <a href="/">首页</a>
                  <a href="/new">新片</a>
                  <a href="/popular">热门</a>
                </nav>
                <div class="video-card thumb-block duration thumbnail">
                  <video><source src="https://media.example.test/sample.m3u8"></video>
                  <img data-src="/cover.jpg">
                  <a href="/watch/sample">Sample</a>
                </div>
              </body>
            </html>
            """
        )

        let source: Source
        if case .saved(let savedSource) = result {
            source = savedSource
        } else {
            Issue.record("Expected high-confidence video source import to save.")
            return
        }

        guard case .video(let configuration) = source.configuration else {
            Issue.record("Expected video source configuration.")
            return
        }

        #expect(configuration.definition.adapter == .genericHTML)
        #expect(configuration.listTabs.map(\.title) == ["首页", "新片", "热门"])
        #expect(repository.savedSources.map(\.id) == ["video.example"])
    }

    @Test func addVideoSourceUseCaseRequiresReviewWhenHTMLIsMissing() throws {
        let repository: VideoTabDiscoveryInMemorySourceRepository = VideoTabDiscoveryInMemorySourceRepository()
        let useCase: AddVideoSourceUseCase = AddVideoSourceUseCase(
            sourceRepository: repository,
            makeID: { "video.review" }
        )

        let result: AddVideoSourceResult = try useCase.execute(
            entryURLString: "https://video.example.test/",
            name: "Review Video"
        )

        if case .needsReview(let source, let warnings) = result {
            #expect(source.id == "video.review")
            #expect(warnings.isEmpty == false)
        } else {
            Issue.record("Expected video source without entry HTML to require review.")
        }

        #expect(repository.savedSources.isEmpty)
    }

    @Test func addVideoSourceUseCaseCanSaveReviewedVideoSource() throws {
        let repository: VideoTabDiscoveryInMemorySourceRepository = VideoTabDiscoveryInMemorySourceRepository()
        let useCase: AddVideoSourceUseCase = AddVideoSourceUseCase(
            sourceRepository: repository,
            makeID: { "video.review" }
        )

        let result: AddVideoSourceResult = try useCase.execute(
            entryURLString: "https://video.example.test/",
            name: "Review Video"
        )

        guard case .needsReview(let source, _) = result else {
            Issue.record("Expected video source without entry HTML to require review.")
            return
        }

        let savedSource: Source = try useCase.saveReviewedSource(source)

        #expect(savedSource.id == "video.review")
        #expect(repository.savedSources.map(\.id) == ["video.review"])
    }

    @Test func addVideoSourceUseCaseDoesNotSaveUnavailableVideoSource() throws {
        let repository: VideoTabDiscoveryInMemorySourceRepository = VideoTabDiscoveryInMemorySourceRepository()
        let useCase: AddVideoSourceUseCase = AddVideoSourceUseCase(
            sourceRepository: repository,
            makeID: { "video.unavailable" }
        )

        let result: AddVideoSourceResult = try useCase.execute(
            entryURLString: "https://article.example.test/",
            name: "Not Video",
            entryHTML: """
            <html>
              <body>
                <h1>About this site</h1>
                <p>Company profile and contact information.</p>
              </body>
            </html>
            """
        )

        #expect(result == .unavailable(.noVideoSignals))
        #expect(repository.savedSources.isEmpty)
    }

    @Test func addVideoSourceUseCaseDoesNotSavePluginRequiredVideoSource() throws {
        let repository: VideoTabDiscoveryInMemorySourceRepository = VideoTabDiscoveryInMemorySourceRepository()
        let useCase: AddVideoSourceUseCase = AddVideoSourceUseCase(
            sourceRepository: repository,
            makeID: { "video.plugin" }
        )

        let result: AddVideoSourceResult = try useCase.execute(
            entryURLString: "https://video.example.test/",
            name: "Plugin Video",
            entryHTML: """
            <html>
              <body>
                <script>var media = CryptoJS.AES.decrypt(payload, key)</script>
              </body>
            </html>
            """
        )

        #expect(result == .pluginRequired(.encryptedPlayback))
        #expect(repository.savedSources.isEmpty)
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

private final class VideoTabDiscoveryInMemorySourceRepository: SourceRepository {
    var savedSources: [Source] = []

    func fetchSources() throws -> [Source] {
        return self.savedSources
    }

    func saveSource(_ source: Source) throws {
        self.savedSources.append(source)
    }

    func deleteSource(id: String) throws {
        self.savedSources.removeAll { source in
            source.id == id
        }
    }
}
