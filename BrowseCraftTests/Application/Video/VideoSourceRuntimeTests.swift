import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

struct VideoSourceRuntimeTests {
    @Test func swiftSoupVideoRuleParserExecutesStructuredExtractRules() throws {
        let parser: CoreVideoRuleSourceParser = CoreVideoRuleSourceParser()
        let rule: VideoListRule = Self.listRule()
        let html: String = """
        <html>
          <body>
            <main class="ready">
              <a class="video-card" href="/watch/one" data-id="one">
                <span class="title">First Video</span>
                <img data-src="/covers/one.jpg">
                <span class="latest">Episode 1</span>
              </a>
              <a class="video-card" href="https://video.example.invalid/watch/two" data-id="two">
                <span class="title">Second Video</span>
                <img src="https://cdn.example.invalid/two.jpg">
              </a>
            </main>
          </body>
        </html>
        """

        let result: VideoRuleParsedList = try parser.parseList(
            html: html,
            pageURL: try #require(URL(string: "https://video.example.invalid/videos/")),
            rule: rule
        )

        #expect(result.candidateCount == 2)
        #expect(result.droppedCount == 0)
        #expect(result.items.map(\.idCode) == ["one", "two"])
        #expect(result.items.map(\.title) == ["First Video", "Second Video"])
        #expect(result.items.map(\.detailURL.absoluteString) == [
            "https://video.example.invalid/watch/one",
            "https://video.example.invalid/watch/two"
        ])
        #expect(result.items.map { item in item.coverURL?.absoluteString } == [
            "https://video.example.invalid/covers/one.jpg",
            "https://cdn.example.invalid/two.jpg"
        ])
        #expect(result.items.map(\.latestText) == ["Episode 1", nil])
    }

    @Test func swiftSoupVideoRuleParserMapsDetailMetadata() throws {
        let parser: CoreVideoRuleSourceParser = CoreVideoRuleSourceParser()
        let html: String = """
        <main class="detail-ready" data-id="movie-7">
          <h1>Movie Seven</h1>
          <img class="poster" src="/covers/movie-7.jpg">
          <p class="summary">A structured detail description.</p>
          <span class="director">Director Seven</span>
        </main>
        """
        let rule = VideoDetailRule(
            id: "video-detail",
            fields: VideoDetailFields(
                idCode: ExtractRule(
                    selector: ".detail-ready",
                    selectorKind: .css,
                    function: .attr,
                    param: "data-id"
                ),
                title: ExtractRule(selector: "h1", selectorKind: .css, function: .text),
                cover: ExtractRule(
                    selector: ".poster",
                    selectorKind: .css,
                    function: .url,
                    param: "src"
                ),
                description: ExtractRule(
                    selector: ".summary",
                    selectorKind: .css,
                    function: .text
                ),
                metadata: [
                    VideoDetailMetadataFieldRule(
                        id: "director",
                        label: "Director",
                        value: ExtractRule(
                            selector: ".director",
                            selectorKind: .css,
                            function: .text
                        )
                    )
                ]
            ),
            ready: ExtractRule(selector: ".detail-ready", selectorKind: .css, function: .raw)
        )

        let result: VideoRuleParsedDetail = try parser.parseDetail(
            html: html,
            pageURL: try #require(URL(string: "https://video.example.invalid/detail/movie-7")),
            rule: rule
        )

        #expect(result.readyMatched)
        #expect(result.metadata.idCode == "movie-7")
        #expect(result.metadata.title == "Movie Seven")
        #expect(result.metadata.coverURL?.absoluteString == "https://video.example.invalid/covers/movie-7.jpg")
        #expect(result.metadata.description == "A structured detail description.")
        #expect(result.metadata.attributes == [
            VideoRuleParsedDetailAttribute(id: "director", label: "Director", value: "Director Seven")
        ])
    }

    @Test func swiftSoupVideoRuleParserPreservesDetailReadyEmptyState() throws {
        let parser: CoreVideoRuleSourceParser = CoreVideoRuleSourceParser()
        let rule = VideoDetailRule(
            id: "video-detail",
            fields: VideoDetailFields(
                title: ExtractRule(selector: "h1", selectorKind: .css, function: .text)
            ),
            ready: ExtractRule(selector: ".detail-ready", selectorKind: .css, function: .raw)
        )

        let result: VideoRuleParsedDetail = try parser.parseDetail(
            html: "<main><h1>Shell title</h1></main>",
            pageURL: try #require(URL(string: "https://video.example.invalid/detail/shell")),
            rule: rule
        )

        #expect(result.readyMatched == false)
        #expect(result.metadata.title == nil)
        #expect(result.metadata.attributes.isEmpty)
    }

    @Test func swiftSoupVideoRuleParserMapsAndSortsFlatEpisodes() throws {
        let parser: CoreVideoRuleSourceParser = CoreVideoRuleSourceParser()
        let html: String = """
        <main class="episode-ready">
          <a class="episode" href="/play/2" data-id="ep-2" data-order="2" data-paid="yes">
            <span class="title">Episode 2</span>
          </a>
          <a class="episode" href="/play/1" data-id="ep-1" data-order="1" data-restricted="blocked">
            <span class="title">Episode 1</span>
          </a>
          <a class="episode" href="/play/bonus" data-id="bonus">
            <span class="title">Bonus</span>
          </a>
          <a class="episode" href="/play/1#duplicate" data-id="duplicate" data-order="3">
            <span class="title">Duplicate</span>
          </a>
        </main>
        """
        let currentAttribute: (String) -> ExtractRule = { attribute in
            return ExtractRule(selectorKind: .current, function: .attr, param: attribute)
        }
        let rule = VideoEpisodeRule(
            id: "video-episodes",
            item: ExtractRule(selector: ".episode", selectorKind: .css, function: .raw),
            fields: VideoEpisodeFields(
                idCode: currentAttribute("data-id"),
                title: ExtractRule(selector: ".title", selectorKind: .css, function: .text),
                playURL: ExtractRule(selectorKind: .current, function: .url, param: "href"),
                order: currentAttribute("data-order"),
                restriction: VideoDOMScalarMatchRule(
                    value: currentAttribute("data-restricted"),
                    matchingValues: ["blocked"]
                ),
                paid: VideoDOMScalarMatchRule(
                    value: currentAttribute("data-paid"),
                    matchingValues: ["yes"]
                )
            ),
            ready: ExtractRule(selector: ".episode-ready", selectorKind: .css, function: .raw),
            sort: .ascending
        )

        let result: VideoRuleParsedEpisodes = try parser.parseEpisodes(
            html: html,
            pageURL: try #require(URL(string: "https://video.example.invalid/detail/movie-7")),
            rule: rule
        )

        #expect(result.readyMatched)
        #expect(result.groups.count == 1)
        #expect(result.candidateCount == 4)
        #expect(result.droppedCount == 1)
        #expect(result.episodes.map(\.title) == ["Episode 1", "Episode 2", "Bonus"])
        #expect(result.episodes.map(\.order) == [1, 2, nil])
        #expect(result.episodes.map(\.isRestricted) == [true, nil, nil])
        #expect(result.episodes.map(\.isPaid) == [nil, true, nil])
    }

    @Test func swiftSoupVideoRuleParserScopesEpisodesWithinRouteGroups() throws {
        let parser: CoreVideoRuleSourceParser = CoreVideoRuleSourceParser()
        let html: String = """
        <section class="route" data-route="route-a">
          <h2>Route A</h2>
          <a class="episode" href="/route-a/episode-1">Episode 1</a>
        </section>
        <section class="route" data-route="route-b">
          <h2>Route B</h2>
          <a class="episode" href="/route-b/episode-1">Episode 1</a>
        </section>
        """
        let rule = VideoEpisodeRule(
            id: "grouped-episodes",
            group: VideoEpisodeGroupDOMRule(
                item: ExtractRule(selector: ".route", selectorKind: .css, function: .raw),
                idCode: ExtractRule(selectorKind: .current, function: .attr, param: "data-route"),
                title: ExtractRule(selector: "h2", selectorKind: .css, function: .text)
            ),
            item: ExtractRule(selector: ".episode", selectorKind: .css, function: .raw),
            fields: VideoEpisodeFields(
                title: ExtractRule(selectorKind: .current, function: .text),
                playURL: ExtractRule(selectorKind: .current, function: .url, param: "href")
            )
        )

        let result: VideoRuleParsedEpisodes = try parser.parseEpisodes(
            html: html,
            pageURL: try #require(URL(string: "https://video.example.invalid/detail/movie-7")),
            rule: rule
        )

        #expect(result.groups.map(\.idCode) == ["route-a", "route-b"])
        #expect(result.groups.map(\.title) == ["Route A", "Route B"])
        #expect(result.groups.map { $0.episodes.first?.playURL.absoluteString } == [
            "https://video.example.invalid/route-a/episode-1",
            "https://video.example.invalid/route-b/episode-1"
        ])
    }

    @Test func videoRuleListLoaderUsesResolvedPageAndRuleRequest() async throws {
        let pageLoader: RecordingVideoRulePageContentLoader = RecordingVideoRulePageContentLoader(
            html: "<html><body><article>Rendered list</article></body></html>"
        )
        let parser: RecordingVideoRuleParser = RecordingVideoRuleParser(
            result: VideoRuleParsedList(
                items: [
                    VideoRuleParsedListItem(
                        idCode: "movie-1",
                        title: "Movie One",
                        detailURL: try #require(URL(string: "https://video.example.invalid/watch/movie-1")),
                        coverURL: nil,
                        latestText: "New"
                    )
                ],
                candidateCount: 1,
                droppedCount: 0
            )
        )
        let source: Source = Self.source(rule: Self.siteRule())
        let resolvedRule: ResolvedVideoSiteRule = try ResolvedVideoSiteRule(
            validating: try #require(source.videoConfiguration?.rule)
        )
        let runtime: VideoSourceRuntime = VideoSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoSourceListLoader(
                pageContentLoader: pageLoader,
                parser: parser
            )
        )

        let output: SourceListOutput = try await runtime.loadList(
            SourceListInput(
                page: 1,
                urlOverride: nil,
                context: Self.context(sourceID: source.id, pageID: "latest", ruleID: "video-list")
            )
        )

        #expect(pageLoader.lastURL?.absoluteString == "https://video.example.invalid/videos/")
        #expect(pageLoader.lastRequest?.headers?["X-Site"] == "site")
        #expect(pageLoader.lastRequest?.headers?["X-Page"] == "page")
        #expect(pageLoader.lastRequest?.headers?["X-Rule"] == "rule")
        #expect(pageLoader.lastRequest?.needsWebView == false)
        #expect(parser.lastPageURL == pageLoader.lastURL)
        #expect(parser.lastRule?.id == "video-list")
        #expect(output.items.map(\.title) == ["Movie One"])
        #expect(output.items.first?.id == "catalog.video.v2.video.v2.movie-1")
        #expect(output.items.first?.idCode == "movie-1")
        #expect(output.pagination == nil)
        #expect(output.diagnostics.extractionLogs.first?.candidateCount == 1)
    }

    @Test func videoRuleListAPILoaderMapsSortsAndResolvesRelativeOutputURLs() async throws {
        let pageLoader = RecordingVideoRulePageContentLoader(
            html: """
            {"data":{"items":[
              {"id":"movie-2","slug":"movie-2","title":"Movie Two","cover":"../covers/two.jpg","order":2},
              {"id":"movie-1","slug":"movie-1","title":"Movie One","cover":"../covers/one.jpg","order":1}
            ]}}
            """
        )
        let parser = RecordingVideoRuleParser(result: try Self.parsedListResult())
        let rule: VideoSiteRule = Self.apiListSiteRule(strategy: .apiOnly)
        let source: Source = Self.source(rule: rule)
        let runtime = VideoSourceRuntime(
            source: source,
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            listLoader: VideoSourceListLoader(pageContentLoader: pageLoader, parser: parser)
        )

        let output: SourceListOutput = try await runtime.loadList(
            SourceListInput(
                page: 1,
                urlOverride: nil,
                context: Self.context(sourceID: source.id, pageID: "latest", ruleID: "video-list")
            )
        )

        #expect(pageLoader.urls.map(\.absoluteString) == ["https://video.example.invalid/api/list"])
        #expect(pageLoader.lastRequest?.headers?["X-List-API"] == "api")
        #expect(output.items.map(\.idCode) == ["movie-1", "movie-2"])
        #expect(output.items.map(\.title) == ["Movie One", "Movie Two"])
        #expect(output.items.map { $0.detailURL?.absoluteString } == [
            "https://video.example.invalid/detail/movie-1",
            "https://video.example.invalid/detail/movie-2"
        ])
        #expect(output.items.map { $0.coverURL?.absoluteString } == [
            "https://video.example.invalid/covers/one.jpg",
            "https://video.example.invalid/covers/two.jpg"
        ])
        #expect(parser.lastRule == nil)
    }

    @Test func videoRuleListAPIFallsBackToDOMOnlyForExplicitEmptyArray() async throws {
        let pageLoader = RecordingVideoRulePageContentLoader(html: "{\"data\":{\"items\":[]}}")
        let parser = RecordingVideoRuleParser(
            result: try Self.parsedListResult(idCode: "dom-fallback")
        )
        let rule: VideoSiteRule = Self.apiListSiteRule(strategy: .apiThenDOM)
        let source: Source = Self.source(rule: rule)
        let runtime = VideoSourceRuntime(
            source: source,
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            listLoader: VideoSourceListLoader(pageContentLoader: pageLoader, parser: parser)
        )

        let output: SourceListOutput = try await runtime.loadList(
            SourceListInput(
                page: 1,
                urlOverride: nil,
                context: Self.context(sourceID: source.id, pageID: "latest", ruleID: "video-list")
            )
        )

        #expect(pageLoader.urls.map(\.absoluteString) == [
            "https://video.example.invalid/api/list",
            "https://video.example.invalid/videos/"
        ])
        #expect(parser.lastRule?.id == "video-list")
        #expect(output.items.first?.idCode == "dom-fallback")
        #expect(output.diagnostics.issues.contains { $0.id == "video.v2.listFallbackUsed" })
    }

    @Test func videoRuleListAPIMissingPathDoesNotFallBackToDOM() async throws {
        let pageLoader = RecordingVideoRulePageContentLoader(html: "{\"data\":{}}")
        let parser = RecordingVideoRuleParser(result: try Self.parsedListResult())
        let rule: VideoSiteRule = Self.apiListSiteRule(strategy: .apiThenDOM)
        let source: Source = Self.source(rule: rule)
        let runtime = VideoSourceRuntime(
            source: source,
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            listLoader: VideoSourceListLoader(pageContentLoader: pageLoader, parser: parser)
        )

        do {
            _ = try await runtime.loadList(
                SourceListInput(
                    page: 1,
                    urlOverride: nil,
                    context: Self.context(sourceID: source.id, pageID: "latest", ruleID: "video-list")
                )
            )
            Issue.record("Expected response-contract failure for a missing API itemPath.")
        } catch let error as RuleExecutionError {
            guard case .responseContract(_, _, let reason) = error else {
                Issue.record("Unexpected rule error: \(error.localizedDescription)")
                return
            }
            #expect(reason.contains("resolved as missing"))
        }
        #expect(pageLoader.urls.count == 1)
        #expect(parser.lastRule == nil)
    }

    @Test func videoRuleListAPIBusinessFailureDoesNotFallBackToDOM() async throws {
        let pageLoader = RecordingVideoRulePageContentLoader(
            html: "{\"code\":403,\"message\":\"account required\",\"data\":{\"items\":[]}}"
        )
        let parser = RecordingVideoRuleParser(result: try Self.parsedListResult())
        let rule: VideoSiteRule = Self.apiListSiteRule(
            strategy: .apiThenDOM,
            responsePolicy: APIResponsePolicy(
                mode: .envelope,
                businessStatusPath: "code",
                successValues: [.number(0)],
                messagePaths: ["message"]
            )
        )
        let source: Source = Self.source(rule: rule)
        let runtime = VideoSourceRuntime(
            source: source,
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            listLoader: VideoSourceListLoader(pageContentLoader: pageLoader, parser: parser)
        )

        do {
            _ = try await runtime.loadList(
                SourceListInput(
                    page: 1,
                    urlOverride: nil,
                    context: Self.context(sourceID: source.id, pageID: "latest", ruleID: "video-list")
                )
            )
            Issue.record("Expected source API business failure.")
        } catch let error as RuleExecutionError {
            guard case .sourceAPI(_, _, let reason) = error else {
                Issue.record("Unexpected rule error: \(error.localizedDescription)")
                return
            }
            #expect(reason.contains("account required"))
        }
        #expect(pageLoader.urls.count == 1)
        #expect(parser.lastRule == nil)
    }

    @Test func videoRuleListLoaderAppliesRuntimeOverrideAfterCompleteRuleInheritance() async throws {
        let pageLoader: RecordingVideoRulePageContentLoader = RecordingVideoRulePageContentLoader(
            html: "<html><body><article>Runtime override</article></body></html>"
        )
        let parser: RecordingVideoRuleParser = RecordingVideoRuleParser(
            result: try Self.parsedListResult()
        )
        let source: Source = Self.source(rule: Self.requestInheritanceSiteRule())
        let resolvedRule: ResolvedVideoSiteRule = try ResolvedVideoSiteRule(
            validating: try #require(source.videoConfiguration?.rule)
        )
        let runtime: VideoSourceRuntime = VideoSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoSourceListLoader(
                pageContentLoader: pageLoader,
                parser: parser
            )
        )
        let runtimeURL: URL = try #require(
            URL(string: "https://runtime.example.invalid/overridden-list")
        )
        let requestOverride: SourceRequestOverride = SourceRequestOverride(
            url: runtimeURL,
            headers: [
                "x-rule": "runtime",
                "X-Runtime": "runtime"
            ],
            method: "GET",
            body: "runtime-body",
            charset: "utf8",
            requiresWebView: true,
            autoScroll: true,
            cookiePolicy: .readWrite
        )

        _ = try await runtime.loadList(
            SourceListInput(
                page: 1,
                urlOverride: nil,
                context: Self.context(
                    sourceID: source.id,
                    pageID: "latest",
                    ruleID: "video-list",
                    requestOverride: requestOverride
                )
            )
        )

        let request: RequestConfig = try #require(pageLoader.lastRequest)
        #expect(pageLoader.lastURL == runtimeURL)
        #expect(request.scope == .rule)
        #expect(request.mergePolicy == .mergeHeadersAndCookies)
        #expect(request.method == .get)
        #expect(request.headers?["X-Site"] == "site")
        #expect(request.headers?["X-Shared-Case"] == nil)
        #expect(request.headers?["x-shared-case"] == "page")
        #expect(request.headers?["X-Page"] == "page")
        #expect(request.headers?["X-Rule"] == nil)
        #expect(request.headers?["x-rule"] == "runtime")
        #expect(request.headers?["X-Runtime"] == "runtime")
        #expect(request.body?.value == "runtime-body")
        #expect(request.body?.contentType == nil)
        #expect(request.cookiePolicy == .browser)
        #expect(request.cookiePriority == .request)
        #expect(request.cookieScope == .rule)
        #expect(request.charset == .utf8)
        #expect(request.needsWebView == true)
        #expect(request.autoScroll == true)
        #expect(request.imageHeaders?["Referer"] == nil)
        #expect(request.imageHeaders?["referer"] == "page-image")
        #expect(request.imageHeaders?["X-Image-Site"] == "site-image")
        #expect(request.imageHeaders?["X-Image-Page"] == "page-image")
        #expect(request.imageHeaders?["X-Image-Rule"] == "rule-image")
        #expect(request.imageRequest?.headers?["Referer"] == nil)
        #expect(request.imageRequest?.headers?["referer"] == "page-nested")
        #expect(request.imageRequest?.headers?["X-Nested-Site"] == "site-nested")
        #expect(request.imageRequest?.headers?["X-Nested-Page"] == "page-nested")
        #expect(request.imageRequest?.headers?["X-Nested-Rule"] == "rule-nested")
        #expect(request.imageRequest?.cookiePolicy == .browser)
        #expect(request.imageRequest?.cookiePriority == .image)
        #expect(request.imageRequest?.cookieScope == .image)
    }

    @Test func videoRuleListLoaderUsesExplicitInputURLBeforeContextURL() async throws {
        let pageLoader: RecordingVideoRulePageContentLoader = RecordingVideoRulePageContentLoader(
            html: "<html><body><article>Explicit URL</article></body></html>"
        )
        let parser: RecordingVideoRuleParser = RecordingVideoRuleParser(
            result: try Self.parsedListResult()
        )
        let source: Source = Self.source(rule: Self.siteRule())
        let resolvedRule: ResolvedVideoSiteRule = try ResolvedVideoSiteRule(
            validating: try #require(source.videoConfiguration?.rule)
        )
        let runtime: VideoSourceRuntime = VideoSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoSourceListLoader(
                pageContentLoader: pageLoader,
                parser: parser
            )
        )
        let inputURL: URL = try #require(URL(string: "https://input.example.invalid/list"))
        let contextURL: URL = try #require(URL(string: "https://context.example.invalid/list"))

        _ = try await runtime.loadList(
            SourceListInput(
                page: 1,
                urlOverride: inputURL,
                context: Self.context(
                    sourceID: source.id,
                    pageID: "latest",
                    ruleID: "video-list",
                    requestOverride: SourceRequestOverride(
                        url: contextURL,
                        headers: [:]
                    )
                )
            )
        )

        #expect(pageLoader.lastURL == inputURL)
        #expect(pageLoader.lastRequest?.headers?["X-Site"] == "site")
        #expect(pageLoader.lastRequest?.headers?["X-Page"] == "page")
        #expect(pageLoader.lastRequest?.headers?["X-Rule"] == "rule")
    }

    @Test func videoRulePaginationReplacesRequestedPageAndReturnsNextState() async throws {
        let pageLoader: RecordingVideoRulePageContentLoader = RecordingVideoRulePageContentLoader(
            html: "<html><body><article>Page 2</article></body></html>"
        )
        let parser: RecordingVideoRuleParser = RecordingVideoRuleParser(
            result: try Self.parsedListResult(idCode: "page-2")
        )
        let source: Source = Self.source(rule: Self.paginatedSiteRule())
        let resolvedRule: ResolvedVideoSiteRule = try ResolvedVideoSiteRule(
            validating: try #require(source.videoConfiguration?.rule)
        )
        let runtime: VideoSourceRuntime = VideoSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoSourceListLoader(
                pageContentLoader: pageLoader,
                parser: parser
            )
        )

        let output: SourceListOutput = try await runtime.loadList(
            SourceListInput(
                page: 2,
                urlOverride: nil,
                context: Self.context(sourceID: source.id, pageID: "latest", ruleID: "video-list")
            )
        )

        #expect(pageLoader.lastURL?.absoluteString == "https://video.example.invalid/videos/page/2/")
        #expect(output.pagination?.nextPage == 3)
        #expect(output.pagination?.nextPageURL?.absoluteString == "https://video.example.invalid/videos/page/3/")
        #expect(runtime.capabilities.supportsPagination)
        #expect(runtime.capabilities.limitation(for: .pagination) == nil)
    }

    @Test func videoRulePaginationStopsAtMaxPages() async throws {
        let pageLoader: RecordingVideoRulePageContentLoader = RecordingVideoRulePageContentLoader(
            html: "<html><body><article>Last page</article></body></html>"
        )
        let parser: RecordingVideoRuleParser = RecordingVideoRuleParser(
            result: try Self.parsedListResult(idCode: "last-page")
        )
        let source: Source = Self.source(rule: Self.paginatedSiteRule(maxPages: 4))
        let resolvedRule: ResolvedVideoSiteRule = try ResolvedVideoSiteRule(
            validating: try #require(source.videoConfiguration?.rule)
        )
        let runtime: VideoSourceRuntime = VideoSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoSourceListLoader(
                pageContentLoader: pageLoader,
                parser: parser
            )
        )

        let output: SourceListOutput = try await runtime.loadList(
            SourceListInput(
                page: 4,
                urlOverride: nil,
                context: Self.context(sourceID: source.id, pageID: "latest", ruleID: "video-list")
            )
        )

        #expect(pageLoader.lastURL?.absoluteString == "https://video.example.invalid/videos/page/4/")
        #expect(output.pagination == nil)
    }

    @Test func videoRulePaginationTreatsLaterEmptyPageAsTerminalWhenDeclared() async throws {
        let pageLoader: RecordingVideoRulePageContentLoader = RecordingVideoRulePageContentLoader(
            html: "<html><body><main class=\"empty\"></main></body></html>"
        )
        let parser: RecordingVideoRuleParser = RecordingVideoRuleParser(
            result: VideoRuleParsedList(items: [], candidateCount: 0, droppedCount: 0)
        )
        let source: Source = Self.source(rule: Self.paginatedSiteRule(stopWhenEmpty: true))
        let resolvedRule: ResolvedVideoSiteRule = try ResolvedVideoSiteRule(
            validating: try #require(source.videoConfiguration?.rule)
        )
        let runtime: VideoSourceRuntime = VideoSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoSourceListLoader(
                pageContentLoader: pageLoader,
                parser: parser
            )
        )

        let output: SourceListOutput = try await runtime.loadList(
            SourceListInput(
                page: 2,
                urlOverride: nil,
                context: Self.context(sourceID: source.id, pageID: "latest", ruleID: "video-list")
            )
        )

        #expect(output.items.isEmpty)
        #expect(output.pagination == nil)
        #expect(output.diagnostics.status == .succeeded)
        #expect(output.diagnostics.issues.contains { issue in
            return issue.id == "video.v2.paginationEnded" && issue.severity == .info
        })
    }

    @Test func videoRulePaginationContinuesPastLaterEmptyPageWhenDeclared() async throws {
        let pageLoader: RecordingVideoRulePageContentLoader = RecordingVideoRulePageContentLoader(
            html: "<html><body><main class=\"empty\"></main></body></html>"
        )
        let parser: RecordingVideoRuleParser = RecordingVideoRuleParser(
            result: VideoRuleParsedList(items: [], candidateCount: 0, droppedCount: 0)
        )
        let source: Source = Self.source(rule: Self.paginatedSiteRule(stopWhenEmpty: false))
        let resolvedRule: ResolvedVideoSiteRule = try ResolvedVideoSiteRule(
            validating: try #require(source.videoConfiguration?.rule)
        )
        let runtime: VideoSourceRuntime = VideoSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoSourceListLoader(
                pageContentLoader: pageLoader,
                parser: parser
            )
        )

        let output: SourceListOutput = try await runtime.loadList(
            SourceListInput(
                page: 2,
                urlOverride: nil,
                context: Self.context(sourceID: source.id, pageID: "latest", ruleID: "video-list")
            )
        )

        #expect(output.items.isEmpty)
        #expect(output.pagination?.nextPage == 3)
        #expect(output.pagination?.nextPageURL?.absoluteString == "https://video.example.invalid/videos/page/3/")
        #expect(output.diagnostics.issues.contains { issue in
            return issue.id == "video.v2.emptyPageContinues" && issue.severity == .info
        })
    }

    @Test func videoRuleFirstPageEmptyThrowsSelectorContractError() async throws {
        let pageLoader: RecordingVideoRulePageContentLoader = RecordingVideoRulePageContentLoader(
            html: "<html><body><main class=\"empty\"></main></body></html>"
        )
        let parser: RecordingVideoRuleParser = RecordingVideoRuleParser(
            result: VideoRuleParsedList(items: [], candidateCount: 0, droppedCount: 0)
        )
        let source: Source = Self.source(rule: Self.siteRule())
        let resolvedRule: ResolvedVideoSiteRule = try ResolvedVideoSiteRule(
            validating: try #require(source.videoConfiguration?.rule)
        )
        let runtime: VideoSourceRuntime = VideoSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoSourceListLoader(
                pageContentLoader: pageLoader,
                parser: parser
            )
        )

        do {
            _ = try await runtime.loadList(
                SourceListInput(
                    page: 1,
                    urlOverride: nil,
                    context: Self.context(sourceID: source.id, pageID: "latest", ruleID: "video-list")
                )
            )
            Issue.record("Expected first-page selectorEmpty error.")
        } catch let error as RuleExecutionError {
            #expect(
                error == .selectorEmpty(
                    stage: .list,
                    sourceID: source.id,
                    url: "https://video.example.invalid/videos/",
                    ruleID: "video-list"
                )
            )
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func videoRuleAllDroppedCandidatesThrowMappingContractError() async throws {
        let pageLoader: RecordingVideoRulePageContentLoader = RecordingVideoRulePageContentLoader(
            html: "<html><body><article>Invalid candidates</article></body></html>"
        )
        let parser: RecordingVideoRuleParser = RecordingVideoRuleParser(
            result: VideoRuleParsedList(items: [], candidateCount: 2, droppedCount: 2)
        )
        let source: Source = Self.source(rule: Self.siteRule())
        let resolvedRule: ResolvedVideoSiteRule = try ResolvedVideoSiteRule(
            validating: try #require(source.videoConfiguration?.rule)
        )
        let runtime: VideoSourceRuntime = VideoSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoSourceListLoader(
                pageContentLoader: pageLoader,
                parser: parser
            )
        )

        do {
            _ = try await runtime.loadList(
                SourceListInput(
                    page: 1,
                    urlOverride: nil,
                    context: Self.context(sourceID: source.id, pageID: "latest", ruleID: "video-list")
                )
            )
            Issue.record("Expected all-dropped mapping contract error.")
        } catch let error as RuleExecutionError {
            guard case .ruleConfiguration(let stage, let sourceID, let reason) = error else {
                Issue.record("Expected ruleConfiguration, got \(error)")
                return
            }
            #expect(stage == .list)
            #expect(sourceID == source.id)
            #expect(reason.contains("matched 2 candidates"))
            #expect(reason.contains("title and detailURL"))
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func videoRulePartiallyDroppedCandidatesReturnPartialDiagnostics() async throws {
        let pageLoader: RecordingVideoRulePageContentLoader = RecordingVideoRulePageContentLoader(
            html: "<html><body><article>Mixed candidates</article></body></html>"
        )
        var parsed: VideoRuleParsedList = try Self.parsedListResult(idCode: "accepted")
        parsed.candidateCount = 2
        parsed.droppedCount = 1
        let parser: RecordingVideoRuleParser = RecordingVideoRuleParser(result: parsed)
        let source: Source = Self.source(rule: Self.siteRule())
        let resolvedRule: ResolvedVideoSiteRule = try ResolvedVideoSiteRule(
            validating: try #require(source.videoConfiguration?.rule)
        )
        let runtime: VideoSourceRuntime = VideoSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoSourceListLoader(
                pageContentLoader: pageLoader,
                parser: parser
            )
        )

        let output: SourceListOutput = try await runtime.loadList(
            SourceListInput(
                page: 1,
                urlOverride: nil,
                context: Self.context(sourceID: source.id, pageID: "latest", ruleID: "video-list")
            )
        )

        #expect(output.items.count == 1)
        #expect(output.diagnostics.status == .partial)
        #expect(output.diagnostics.extractionLogs.first?.candidateCount == 2)
        #expect(output.diagnostics.extractionLogs.first?.outputCount == 1)
        #expect(output.diagnostics.issues.contains { issue in
            return issue.id == "video.v2.listItemsDropped" && issue.severity == .warning
        })
    }

    @Test func videoRuleWithoutPaginationRejectsSecondPageAndReportsCapability() async throws {
        let pageLoader: RecordingVideoRulePageContentLoader = RecordingVideoRulePageContentLoader(
            html: "<html><body><article>Page</article></body></html>"
        )
        let parser: RecordingVideoRuleParser = RecordingVideoRuleParser(
            result: try Self.parsedListResult()
        )
        let source: Source = Self.source(rule: Self.siteRule())
        let resolvedRule: ResolvedVideoSiteRule = try ResolvedVideoSiteRule(
            validating: try #require(source.videoConfiguration?.rule)
        )
        let runtime: VideoSourceRuntime = VideoSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoSourceListLoader(
                pageContentLoader: pageLoader,
                parser: parser
            )
        )

        #expect(runtime.capabilities.supportsPagination == false)
        #expect(runtime.capabilities.limitation(for: .pagination)?.reason == .unsupportedBySource)
        do {
            _ = try await runtime.loadList(
                SourceListInput(
                    page: 2,
                    urlOverride: nil,
                    context: Self.context(sourceID: source.id, pageID: "latest", ruleID: "video-list")
                )
            )
            Issue.record("Expected page 2 without pagination to be rejected.")
        } catch let error as SourceRuntimeError {
            guard case .unsupported(.custom(let message)) = error else {
                Issue.record("Expected unsupported pagination error, got \(error)")
                return
            }
            #expect(message.contains("does not declare pagination"))
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func sourceRuntimeResolverRoutesVideoToV2Runtime() throws {
        let source: Source = Self.source(rule: Self.siteRule())
        var didUseRuleRuntime: Bool = false
        let resolver: TestSourceRuntimeResolver = TestSourceRuntimeResolver(
            videoRuntimeFactory: { source in
                didUseRuleRuntime = true
                return VideoRuleStubRuntime(
                    definition: SourceDefinitionMapper().definition(from: source)
                )
            },
            comicRuntimeFactory: { source in
                return VideoRuleStubRuntime(
                    definition: SourceDefinitionMapper().definition(from: source)
                )
            }
        )

        let runtime: any SourceRuntime = try resolver.runtime(for: source)

        #expect(didUseRuleRuntime)
        #expect(runtime.definition.runtimeKind == .video)
        #expect(runtime.definition.comic == nil)
    }

    @Test func videoRuleDetailRuntimeReusesHTMLAndPreservesListHandoff() async throws {
        let pageLoader = RecordingVideoRulePageContentLoader(html: Self.detailHTML)
        let parser = CoreVideoRuleSourceParser()
        let source: Source = Self.source(rule: Self.detailSiteRule())
        let resolvedRule = try ResolvedVideoSiteRule(
            validating: try #require(source.videoConfiguration?.rule)
        )
        let runtime = VideoSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoSourceListLoader(
                pageContentLoader: pageLoader,
                parser: parser
            ),
            detailLoader: VideoSourceDetailLoader(
                pageContentLoader: pageLoader,
                parser: parser
            )
        )
        let item = ContentItem(
            id: "catalog.video.v2.video.v2.movie-7",
            idCode: "movie-7",
            sourceId: source.id,
            title: "List title",
            detailURL: "https://video.example.invalid/detail/movie-7",
            coverURL: nil,
            type: .video,
            latestText: "Episode 2",
            listContext: ListContext(
                pageId: "latest",
                tabId: "latest",
                sectionId: nil,
                listRuleId: "video-list",
                sectionRole: nil
            )
        )
        let context = SourceRuntimeContext(
            sourceID: source.id,
            pageID: "wrong-page-from-transient-context",
            tabID: nil,
            ruleID: nil,
            requestOverride: nil,
            debugMode: false,
            operation: .detail
        )

        let output: SourceDetailOutput = try await runtime.loadDetail(
            SourceDetailInput(
                detailURL: try #require(URL(string: item.detailURL)),
                context: context,
                itemReference: SourceItemReferenceMapper().reference(from: item, intent: .detail)
            )
        )

        #expect(runtime.capabilities.supportsDetail)
        #expect(runtime.capabilities.limitation(for: .detail) == nil)
        #expect(pageLoader.urls.count == 1)
        #expect(pageLoader.requests[0]?.headers?["X-Site"] == "site")
        #expect(pageLoader.requests[0]?.headers?["X-Page"] == "page")
        #expect(pageLoader.requests[0]?.headers?["X-Detail"] == "detail")
        #expect(output.metadata?.idCode == "movie-7")
        #expect(output.metadata?.title == "Movie Seven")
        #expect(output.metadata?.attributes.map(\.displayText) == ["Director: Director Seven"])
        #expect(output.chapters.map(\.subtitle) == ["Route A", "Route B"])
        #expect(output.chapters.map(\.title) == ["Episode 1", "Episode 1"])
        #expect(output.chapters.map(\.url.absoluteString) == [
            "https://video.example.invalid/route-a/episode-1",
            "https://video.example.invalid/route-b/episode-1"
        ])
        #expect(output.diagnostics.requestLogs.count == 1)
    }

    @Test func videoRuleDetailRuntimeLoadsEpisodeDOMAgainWhenRequestDiffers() async throws {
        let pageLoader = RecordingVideoRulePageContentLoader(html: Self.detailHTML)
        let parser = CoreVideoRuleSourceParser()
        let source: Source = Self.source(
            rule: Self.detailSiteRule(
                episodeRequest: RequestConfig(
                    scope: .rule,
                    headers: ["X-Episode": "episode"]
                )
            )
        )
        let resolvedRule = try ResolvedVideoSiteRule(
            validating: try #require(source.videoConfiguration?.rule)
        )
        let runtime = VideoSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoSourceListLoader(pageContentLoader: pageLoader, parser: parser),
            detailLoader: VideoSourceDetailLoader(pageContentLoader: pageLoader, parser: parser)
        )

        let output: SourceDetailOutput = try await runtime.loadDetail(
            SourceDetailInput(
                detailURL: try #require(URL(string: "https://video.example.invalid/detail/movie-7")),
                context: SourceRuntimeContext(
                    sourceID: source.id,
                    pageID: "latest",
                    tabID: "latest",
                    ruleID: "video-list",
                    requestOverride: nil,
                    debugMode: false,
                    operation: .detail
                )
            )
        )

        #expect(output.chapters.count == 2)
        #expect(pageLoader.urls.count == 2)
        #expect(pageLoader.requests[0]?.headers?["X-Episode"] == nil)
        #expect(pageLoader.requests[1]?.headers?["X-Episode"] == "episode")
        #expect(output.diagnostics.requestLogs.count == 2)
    }

    @Test func videoRuleRuntimeClaimsP15APIDetailStrategiesAndRequestCapabilities() throws {
        let rule: VideoSiteRule = Self.apiDetailSiteRule()
        let source: Source = Self.source(rule: rule)
        let resolvedRule = try ResolvedVideoSiteRule(validating: rule)
        let pageLoader = RecordingVideoRulePageContentLoader(html: Self.detailHTML)
        let parser = CoreVideoRuleSourceParser()
        let runtime = VideoSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoSourceListLoader(pageContentLoader: pageLoader, parser: parser),
            detailLoader: VideoSourceDetailLoader(pageContentLoader: pageLoader, parser: parser)
        )

        #expect(runtime.capabilities.supportsDetail)
        #expect(runtime.capabilities.limitation(for: .detail) == nil)
        #expect(runtime.capabilities.requiresWebView)
        #expect(runtime.capabilities.requiresCookieStore)
    }

    @Test func videoRuleDetailAndEpisodeAPIsMapGroupedChaptersAndItemTemplates() async throws {
        let loader = RoutingVideoRulePageContentLoader(responses: [
            "https://video.example.invalid/api/detail/movie-7": """
            {"data":{"item":{"id":"movie-7","title":"Movie Seven API","cover":"/covers/movie-7.jpg","summary":"API detail","director":"Director API"}}}
            """,
            "https://video.example.invalid/api/episodes/movie-7": """
            {"data":{"routes":[
              {"id":"route-b","title":"Route B","episodes":[
                {"id":"ep-2","title":"Episode 2","slug":"route-b/2","order":2,"restricted":false,"paid":true},
                {"id":"ep-1","title":"Episode 1","slug":"route-b/1","order":1,"restricted":true,"paid":false}
              ]}
            ]}}
            """
        ])
        let parser = CoreVideoRuleSourceParser()
        let rule: VideoSiteRule = Self.apiDetailSiteRule()
        let source: Source = Self.source(rule: rule)
        let runtime = VideoSourceRuntime(
            source: source,
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            listLoader: VideoSourceListLoader(pageContentLoader: loader, parser: parser),
            detailLoader: VideoSourceDetailLoader(pageContentLoader: loader, parser: parser)
        )
        let detailURL: URL = try #require(
            URL(string: "https://video.example.invalid/detail/movie-7")
        )
        let reference = SourceItemReference(
            id: "catalog.video.v2.video.v2.movie-7",
            sourceID: source.id,
            title: "List Movie Seven",
            contentType: .video,
            detailURL: detailURL,
            chapterURL: nil,
            coverURL: nil,
            latestText: nil,
            listContext: SourceItemListContext(
                pageID: "latest",
                tabID: "latest",
                ruleID: "video-list"
            ),
            handoffIntent: .detail,
            requestOverride: nil,
            runtimeContext: nil,
            idCode: "movie-7"
        )

        let output: SourceDetailOutput = try await runtime.loadDetail(
            SourceDetailInput(
                detailURL: detailURL,
                context: SourceRuntimeContext(
                    sourceID: source.id,
                    pageID: "latest",
                    tabID: "latest",
                    ruleID: "video-list",
                    requestOverride: nil,
                    debugMode: false,
                    operation: .detail
                ),
                itemReference: reference
            )
        )

        #expect(loader.urls.map(\.absoluteString) == [
            "https://video.example.invalid/api/detail/movie-7",
            "https://video.example.invalid/api/episodes/movie-7"
        ])
        #expect(loader.requests[0]?.headers?["X-Detail-API"] == "detail-api")
        #expect(loader.requests[1]?.headers?["X-Episode-API"] == "episode-api")
        #expect(output.metadata?.idCode == "movie-7")
        #expect(output.metadata?.title == "Movie Seven API")
        #expect(output.metadata?.coverURL?.absoluteString == "https://video.example.invalid/covers/movie-7.jpg")
        #expect(output.metadata?.attributes.map(\.displayText) == ["Director: Director API"])
        #expect(output.chapters.map(\.subtitle) == ["Route B", "Route B"])
        #expect(output.chapters.map(\.title) == ["Episode 1", "Episode 2"])
        #expect(output.chapters.map(\.isRestricted) == [true, false])
        #expect(output.chapters.map(\.isPaid) == [false, true])
        #expect(output.chapters.map { $0.url.absoluteString } == [
            "https://video.example.invalid/play/route-b/1",
            "https://video.example.invalid/play/route-b/2"
        ])
    }

    @Test func videoRuleEpisodeAPIAllowsAllGroupsToBeExplicitlyEmpty() async throws {
        let loader = RoutingVideoRulePageContentLoader(responses: [
            "https://video.example.invalid/api/detail/movie-7": "{\"data\":{\"item\":{\"id\":\"movie-7\",\"title\":\"Movie Seven API\"}}}",
            "https://video.example.invalid/api/episodes/movie-7": "{\"data\":{\"routes\":[{\"id\":\"route-a\",\"episodes\":[]}]}}"
        ])
        let parser = CoreVideoRuleSourceParser()
        let rule: VideoSiteRule = Self.apiDetailSiteRule()
        let source: Source = Self.source(rule: rule)
        let runtime = VideoSourceRuntime(
            source: source,
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            listLoader: VideoSourceListLoader(pageContentLoader: loader, parser: parser),
            detailLoader: VideoSourceDetailLoader(pageContentLoader: loader, parser: parser)
        )
        let detailURL: URL = try #require(
            URL(string: "https://video.example.invalid/detail/movie-7")
        )
        let reference = SourceItemReference(
            id: "movie-7",
            sourceID: source.id,
            title: "Movie Seven",
            contentType: .video,
            detailURL: detailURL,
            chapterURL: nil,
            coverURL: nil,
            latestText: nil,
            listContext: SourceItemListContext(
                pageID: "latest",
                tabID: "latest",
                ruleID: "video-list"
            ),
            handoffIntent: .detail,
            requestOverride: nil,
            runtimeContext: nil,
            idCode: "movie-7"
        )

        let output: SourceDetailOutput = try await runtime.loadDetail(
            SourceDetailInput(
                detailURL: detailURL,
                context: SourceRuntimeContext(
                    sourceID: source.id,
                    pageID: "latest",
                    tabID: "latest",
                    ruleID: "video-list",
                    requestOverride: nil,
                    debugMode: false,
                    operation: .detail
                ),
                itemReference: reference
            )
        )

        #expect(output.metadata?.title == "Movie Seven API")
        #expect(output.chapters.isEmpty)
        #expect(output.diagnostics.status == .succeeded)
    }

    @Test func videoRuleDetailRuntimeClassifiesAllDroppedEpisodesAsResponseContract() async throws {
        let pageLoader = RecordingVideoRulePageContentLoader(
            html: """
            <main class="detail-ready">
              <h1>Movie Seven</h1>
              <section class="route"><h2>Route A</h2><a class="episode">Missing URL</a></section>
            </main>
            """
        )
        let parser = CoreVideoRuleSourceParser()
        let rule: VideoSiteRule = Self.detailSiteRule()
        let source: Source = Self.source(rule: rule)
        let runtime = VideoSourceRuntime(
            source: source,
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            listLoader: VideoSourceListLoader(pageContentLoader: pageLoader, parser: parser),
            detailLoader: VideoSourceDetailLoader(pageContentLoader: pageLoader, parser: parser)
        )

        do {
            _ = try await runtime.loadDetail(
                SourceDetailInput(
                    detailURL: try #require(URL(string: "https://video.example.invalid/detail/movie-7")),
                    context: SourceRuntimeContext(
                        sourceID: source.id,
                        pageID: "latest",
                        tabID: "latest",
                        ruleID: "video-list",
                        requestOverride: nil,
                        debugMode: false,
                        operation: .detail
                    )
                )
            )
            Issue.record("Expected response-contract error for nonempty raw episodes with zero mapped output.")
        } catch let error as RuleExecutionError {
            guard case .responseContract(_, _, let reason) = error else {
                Issue.record("Unexpected rule error: \(error.localizedDescription)")
                return
            }
            #expect(reason.contains("matched 1 candidates"))
        }
    }

    private static func source(rule: VideoSiteRule) -> Source {
        let now: Date = Date(timeIntervalSince1970: 1_000)
        return Source(
            id: "catalog.video.v2",
            name: rule.name,
            baseURL: rule.baseUrl,
            type: .html,
            configuration: .video(VideoSourceConfiguration(rule: rule)),
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }

    private static let detailHTML: String = """
    <main class="detail-ready">
      <h1>Movie Seven</h1>
      <p class="summary">A structured detail description.</p>
      <span class="director">Director Seven</span>
      <section class="route" data-route="route-a">
        <h2>Route A</h2>
        <a class="episode" href="/route-a/episode-1">Episode 1</a>
      </section>
      <section class="route" data-route="route-b">
        <h2>Route B</h2>
        <a class="episode" href="/route-b/episode-1">Episode 1</a>
      </section>
    </main>
    """

    private static func detailSiteRule(
        episodeRequest: RequestConfig? = nil
    ) -> VideoSiteRule {
        var rule: VideoSiteRule = Self.siteRule()
        rule.pages[0].ruleRefs = VideoRuleRefs(
            list: "video-list",
            detail: "video-detail",
            episode: "video-episodes"
        )
        rule.ruleSets.detailRules = [
            VideoDetailRule(
                id: "video-detail",
                fields: VideoDetailFields(
                    title: ExtractRule(selector: "h1", selectorKind: .css, function: .text),
                    description: ExtractRule(
                        selector: ".summary",
                        selectorKind: .css,
                        function: .text
                    ),
                    metadata: [
                        VideoDetailMetadataFieldRule(
                            id: "director",
                            label: "Director",
                            value: ExtractRule(
                                selector: ".director",
                                selectorKind: .css,
                                function: .text
                            )
                        )
                    ]
                ),
                ready: ExtractRule(selector: ".detail-ready", selectorKind: .css, function: .raw),
                request: RequestConfig(
                    scope: .rule,
                    headers: ["X-Detail": "detail"]
                )
            )
        ]
        rule.ruleSets.episodeRules = [
            VideoEpisodeRule(
                id: "video-episodes",
                group: VideoEpisodeGroupDOMRule(
                    item: ExtractRule(selector: ".route", selectorKind: .css, function: .raw),
                    idCode: ExtractRule(
                        selectorKind: .current,
                        function: .attr,
                        param: "data-route"
                    ),
                    title: ExtractRule(selector: "h2", selectorKind: .css, function: .text)
                ),
                item: ExtractRule(selector: ".episode", selectorKind: .css, function: .raw),
                fields: VideoEpisodeFields(
                    title: ExtractRule(selectorKind: .current, function: .text),
                    playURL: ExtractRule(
                        selectorKind: .current,
                        function: .url,
                        param: "href"
                    )
                ),
                ready: ExtractRule(selector: ".detail-ready", selectorKind: .css, function: .raw),
                sort: .source,
                request: episodeRequest
            )
        ]
        return rule
    }

    private static func apiListSiteRule(
        strategy: VideoRuleDataSourceStrategy,
        responsePolicy: APIResponsePolicy = APIResponsePolicy(mode: .transportOnly)
    ) -> VideoSiteRule {
        var rule: VideoSiteRule = Self.siteRule()
        let domRule: VideoListRule = rule.ruleSets.listRules[0]
        rule.ruleSets.listRules[0] = VideoListRule(
            id: domRule.id,
            sourceStrategy: strategy,
            item: strategy.usesDOM ? domRule.item : nil,
            fields: strategy.usesDOM ? domRule.fields : nil,
            ready: strategy.usesDOM ? domRule.ready : nil,
            pagination: nil,
            request: domRule.request,
            listAPI: VideoListAPIRule(
                url: "https://video.example.invalid/api/list",
                request: RequestConfig(
                    scope: .rule,
                    mergePolicy: .mergeHeaders,
                    headers: ["X-List-API": "api"]
                ),
                itemPath: "data.items[]",
                fields: VideoListAPIFields(
                    idCodePath: "id",
                    titlePath: "title",
                    detailURLTemplate: "/detail/{current.slug}",
                    coverPath: "cover"
                ),
                orderPath: "order",
                sort: .ascending,
                responsePolicy: responsePolicy
            )
        )
        return rule
    }

    private static func apiDetailSiteRule() -> VideoSiteRule {
        var rule: VideoSiteRule = Self.siteRule()
        rule.pages[0].ruleRefs = VideoRuleRefs(
            list: "video-list",
            detail: "video-detail-api",
            episode: "video-episode-api"
        )
        rule.ruleSets.detailRules = [
            VideoDetailRule(
                id: "video-detail-api",
                sourceStrategy: .apiOnly,
                detailAPI: VideoDetailAPIRule(
                    url: "https://video.example.invalid/api/detail/{item.idCode}",
                    request: RequestConfig(
                        scope: .rule,
                        mergePolicy: .mergeHeaders,
                        headers: ["X-Detail-API": "detail-api"],
                        cookiePolicy: .browser,
                        needsWebView: true
                    ),
                    itemPath: "data.item",
                    fields: VideoDetailAPIFields(
                        idCodePath: "id",
                        titlePath: "title",
                        coverPath: "cover",
                        descriptionPath: "summary",
                        metadata: [
                            VideoDetailAPIMetadataFieldRule(
                                id: "director",
                                label: "Director",
                                valuePath: "director"
                            )
                        ]
                    ),
                    responsePolicy: APIResponsePolicy(mode: .transportOnly)
                )
            )
        ]
        rule.ruleSets.episodeRules = [
            VideoEpisodeRule(
                id: "video-episode-api",
                sourceStrategy: .apiOnly,
                episodeAPI: VideoEpisodeAPIRule(
                    url: "https://video.example.invalid/api/episodes/{item.idCode}",
                    request: RequestConfig(
                        scope: .rule,
                        mergePolicy: .mergeHeaders,
                        headers: ["X-Episode-API": "episode-api"]
                    ),
                    groupPath: "data.routes[]",
                    groupFields: VideoEpisodeAPIGroupFields(
                        idCodePath: "id",
                        titlePath: "title"
                    ),
                    itemPath: "episodes[]",
                    fields: VideoEpisodeAPIFields(
                        idCodePath: "id",
                        titlePath: "title",
                        playURLTemplate: "/play/{current.slug}",
                        orderPath: "order",
                        restrictionPath: "restricted",
                        restrictedValues: [.boolean(true)],
                        paidPath: "paid",
                        paidValues: [.boolean(true)]
                    ),
                    sort: .ascending,
                    responsePolicy: APIResponsePolicy(mode: .transportOnly)
                )
            )
        ]
        return rule
    }

    private static func siteRule() -> VideoSiteRule {
        return VideoSiteRule(
            version: 2,
            name: "Video V2",
            baseUrl: "https://video.example.invalid/",
            site: SiteConfig(
                name: "Video V2",
                domain: "video.example.invalid",
                baseURL: "https://video.example.invalid/"
            ),
            sharedRequest: RequestConfig(
                scope: .site,
                headers: ["X-Site": "site"],
                needsWebView: true
            ),
            pages: [
                VideoPageRule(
                    id: "latest",
                    title: "Latest",
                    type: .list,
                    url: "/videos/",
                    request: RequestConfig(
                        scope: .page,
                        headers: ["X-Page": "page"],
                        needsWebView: false
                    ),
                    ruleRefs: VideoRuleRefs(list: "video-list")
                )
            ],
            ruleSets: VideoRuleSets(
                listRules: [
                    VideoListRule(
                        id: "video-list",
                        item: ExtractRule(
                            selector: ".video-card",
                            selectorKind: .css,
                            function: .raw
                        ),
                        fields: VideoListFields(
                            title: ExtractRule(selectorKind: .current, function: .text),
                            detailURL: ExtractRule(
                                selectorKind: .current,
                                function: .url,
                                param: "href"
                            )
                        ),
                        request: RequestConfig(
                            scope: .rule,
                            headers: ["X-Rule": "rule"]
                        )
                    )
                ]
            )
        )
    }

    private static func requestInheritanceSiteRule() -> VideoSiteRule {
        return VideoSiteRule(
            version: 2,
            name: "Video V2 Request Inheritance",
            baseUrl: "https://video.example.invalid/",
            site: SiteConfig(
                name: "Video V2 Request Inheritance",
                domain: "video.example.invalid",
                baseURL: "https://video.example.invalid/"
            ),
            sharedRequest: RequestConfig(
                scope: .site,
                mergePolicy: .mergeHeadersAndCookies,
                method: .get,
                headers: [
                    "X-Site": "site",
                    "X-Shared-Case": "site"
                ],
                body: RequestBody(
                    contentType: "application/site",
                    value: "site-body"
                ),
                cookiePolicy: .custom,
                cookiePriority: .custom,
                cookieScope: .site,
                charset: .gb18030,
                needsWebView: true,
                autoScroll: true,
                imageHeaders: [
                    "Referer": "site-image",
                    "X-Image-Site": "site-image"
                ],
                imageRequest: ImageRequestConfig(
                    headers: [
                        "Referer": "site-nested",
                        "X-Nested-Site": "site-nested"
                    ],
                    cookiePolicy: .custom,
                    cookiePriority: .custom,
                    cookieScope: .site,
                    mergePolicy: .mergeHeaders
                )
            ),
            pages: [
                VideoPageRule(
                    id: "latest",
                    title: "Latest",
                    type: .list,
                    url: "/videos/",
                    request: RequestConfig(
                        scope: .page,
                        headers: [
                            "x-shared-case": "page",
                            "X-Page": "page"
                        ],
                        body: RequestBody(
                            contentType: "application/page",
                            value: "page-body"
                        ),
                        cookiePolicy: .browserThenCustom,
                        cookiePriority: .browser,
                        cookieScope: .page,
                        charset: .shiftJIS,
                        needsWebView: false,
                        autoScroll: false,
                        imageHeaders: [
                            "referer": "page-image",
                            "X-Image-Page": "page-image"
                        ],
                        imageRequest: ImageRequestConfig(
                            headers: [
                                "referer": "page-nested",
                                "X-Nested-Page": "page-nested"
                            ],
                            cookiePolicy: .browser,
                            cookiePriority: .image,
                            cookieScope: .image,
                            mergePolicy: .mergeHeaders
                        )
                    ),
                    ruleRefs: VideoRuleRefs(list: "video-list")
                )
            ],
            ruleSets: VideoRuleSets(
                listRules: [
                    VideoListRule(
                        id: "video-list",
                        item: ExtractRule(
                            selector: ".video-card",
                            selectorKind: .css,
                            function: .raw
                        ),
                        fields: VideoListFields(
                            title: ExtractRule(selectorKind: .current, function: .text),
                            detailURL: ExtractRule(
                                selectorKind: .current,
                                function: .url,
                                param: "href"
                            )
                        ),
                        request: RequestConfig(
                            scope: .rule,
                            method: .post,
                            headers: ["X-Rule": "rule"],
                            cookiePriority: .request,
                            cookieScope: .rule,
                            imageHeaders: ["X-Image-Rule": "rule-image"],
                            imageRequest: ImageRequestConfig(
                                headers: ["X-Nested-Rule": "rule-nested"],
                                mergePolicy: .mergeHeaders
                            )
                        )
                    )
                ]
            )
        )
    }

    private static func paginatedSiteRule(
        stopWhenEmpty: Bool = true,
        maxPages: Int? = 4
    ) -> VideoSiteRule {
        var rule: VideoSiteRule = Self.siteRule()
        rule.pages[0].url = "/videos/page/{page}/"
        rule.ruleSets.listRules[0].pagination = PaginationRule(
            pagePlaceholder: "{page}",
            maxPages: maxPages,
            stopWhenEmpty: stopWhenEmpty
        )
        return rule
    }

    private static func parsedListResult(
        idCode: String = "movie-1"
    ) throws -> VideoRuleParsedList {
        return VideoRuleParsedList(
            items: [
                VideoRuleParsedListItem(
                    idCode: idCode,
                    title: "Movie \(idCode)",
                    detailURL: try #require(
                        URL(string: "https://video.example.invalid/watch/\(idCode)")
                    ),
                    coverURL: nil,
                    latestText: nil
                )
            ],
            candidateCount: 1,
            droppedCount: 0
        )
    }

    private static func listRule() -> VideoListRule {
        return VideoListRule(
            id: "video-list",
            item: ExtractRule(
                selector: "a.video-card",
                selectorKind: .css,
                function: .raw
            ),
            fields: VideoListFields(
                idCode: ExtractRule(
                    selectorKind: .current,
                    function: .attr,
                    param: "data-id"
                ),
                title: ExtractRule(
                    selector: ".title",
                    selectorKind: .css,
                    function: .text
                ),
                detailURL: ExtractRule(
                    selectorKind: .current,
                    function: .url,
                    param: "href"
                ),
                cover: ExtractRule(
                    selector: "img",
                    selectorKind: .css,
                    function: .url,
                    param: "data-src|src"
                ),
                latestText: ExtractRule(
                    selector: ".latest",
                    selectorKind: .css,
                    function: .text
                )
            ),
            ready: ExtractRule(
                selector: ".ready",
                selectorKind: .css,
                function: .raw
            )
        )
    }

    private static func context(
        sourceID: String,
        pageID: String? = nil,
        ruleID: String? = nil,
        requestOverride: SourceRequestOverride? = nil
    ) -> SourceRuntimeContext {
        return SourceRuntimeContext(
            sourceID: sourceID,
            pageID: pageID,
            tabID: pageID,
            ruleID: ruleID,
            requestOverride: requestOverride,
            debugMode: false,
            operation: .list
        )
    }
}

private final class RecordingVideoRuleParser: VideoRuleSourceParsingService {
    let result: VideoRuleParsedList
    private(set) var lastPageURL: URL?
    private(set) var lastRule: VideoListRule?

    init(result: VideoRuleParsedList) {
        self.result = result
    }

    func parseList(
        html: String,
        pageURL: URL,
        rule: VideoListRule
    ) throws -> VideoRuleParsedList {
        self.lastPageURL = pageURL
        self.lastRule = rule
        return self.result
    }

    func parseDetail(
        html: String,
        pageURL: URL,
        rule: VideoDetailRule
    ) throws -> VideoRuleParsedDetail {
        throw VideoRuleSourceParsingError.incompleteDOMRule(kind: "detail", ruleID: rule.id)
    }

    func parseEpisodes(
        html: String,
        pageURL: URL,
        rule: VideoEpisodeRule
    ) throws -> VideoRuleParsedEpisodes {
        throw VideoRuleSourceParsingError.incompleteDOMRule(kind: "episode", ruleID: rule.id)
    }

    func parsePlayback(
        html: String,
        pageURL: URL,
        rule: VideoPlaybackRule
    ) throws -> VideoRuleParsedPlayback {
        throw VideoRuleSourceParsingError.incompleteDOMRule(kind: "playback", ruleID: rule.id)
    }
}

private final class RecordingVideoRulePageContentLoader: PageContentLoader {
    let html: String
    private(set) var lastURL: URL?
    private(set) var lastRequest: RequestConfig?
    private(set) var urls: [URL] = []
    private(set) var requests: [RequestConfig?] = []

    init(html: String) {
        self.html = html
    }

    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        self.lastURL = request.url
        self.lastRequest = request.requestConfig
        self.urls.append(request.url)
        self.requests.append(request.requestConfig)
        return PageContentResponse(content: self.html, finalURL: request.url)
    }
}

private final class RoutingVideoRulePageContentLoader: PageContentLoader {
    let responses: [String: String]
    private(set) var urls: [URL] = []
    private(set) var requests: [RequestConfig?] = []

    init(responses: [String: String]) {
        self.responses = responses
    }

    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        self.urls.append(request.url)
        self.requests.append(request.requestConfig)
        guard let response: String = self.responses[request.url.absoluteString] else {
            throw SourceRuntimeError.invalidInput(
                "No test response was registered for \(request.url.absoluteString)."
            )
        }
        return PageContentResponse(content: response, finalURL: request.url)
    }
}

private struct VideoRuleStubRuntime: SourceRuntime {
    let definition: SourceDefinition

    var capabilities: SourceRuntimeCapabilities {
        return SourceRuntimeCapabilities(
            supportsSearch: false,
            supportsPagination: false,
            supportsDetail: false,
            supportsReader: false,
            supportsDebug: false,
            supportsCandidateAnalysis: false,
            requiresWebView: false,
            requiresCookieStore: false,
            requiresAccount: false
        )
    }

    func loadList(_ input: SourceListInput) async throws -> SourceListOutput {
        return SourceListOutput(
            items: [],
            pagination: nil,
            diagnostics: SourceRuntimeDiagnostics.succeeded()
        )
    }

    func search(_ input: SourceSearchInput) async throws -> SourceListOutput {
        throw SourceRuntimeError.unsupported(.custom("Stub runtime."))
    }

    func loadDetail(_ input: SourceDetailInput) async throws -> SourceDetailOutput {
        throw SourceRuntimeError.unsupported(.custom("Stub runtime."))
    }

    func loadReader(_ input: SourceReaderInput) async throws -> SourceReaderOutput {
        throw SourceRuntimeError.unsupported(.custom("Stub runtime."))
    }

    func debug(_ input: SourceRuntimeContext) async throws -> SourceDebugOutput {
        return SourceDebugOutput(
            diagnostics: SourceRuntimeDiagnostics.skipped(message: "Stub runtime.")
        )
    }
}
