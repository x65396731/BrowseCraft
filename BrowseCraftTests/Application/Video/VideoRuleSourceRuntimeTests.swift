import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

struct VideoRuleSourceRuntimeTests {
    @Test func swiftSoupVideoRuleParserExecutesStructuredExtractRules() throws {
        let parser: SwiftSoupVideoRuleSourceParser = SwiftSoupVideoRuleSourceParser()
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
            validating: try #require(source.videoConfiguration?.ruleDrivenConfiguration?.rule)
        )
        let runtime: VideoRuleSourceRuntime = VideoRuleSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoRuleSourceListLoader(
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
        #expect(output.pagination == nil)
        #expect(output.diagnostics.extractionLogs.first?.candidateCount == 1)
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
            validating: try #require(source.videoConfiguration?.ruleDrivenConfiguration?.rule)
        )
        let runtime: VideoRuleSourceRuntime = VideoRuleSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoRuleSourceListLoader(
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
            validating: try #require(source.videoConfiguration?.ruleDrivenConfiguration?.rule)
        )
        let runtime: VideoRuleSourceRuntime = VideoRuleSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoRuleSourceListLoader(
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
            validating: try #require(source.videoConfiguration?.ruleDrivenConfiguration?.rule)
        )
        let runtime: VideoRuleSourceRuntime = VideoRuleSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoRuleSourceListLoader(
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
            validating: try #require(source.videoConfiguration?.ruleDrivenConfiguration?.rule)
        )
        let runtime: VideoRuleSourceRuntime = VideoRuleSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoRuleSourceListLoader(
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
            validating: try #require(source.videoConfiguration?.ruleDrivenConfiguration?.rule)
        )
        let runtime: VideoRuleSourceRuntime = VideoRuleSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoRuleSourceListLoader(
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
            validating: try #require(source.videoConfiguration?.ruleDrivenConfiguration?.rule)
        )
        let runtime: VideoRuleSourceRuntime = VideoRuleSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoRuleSourceListLoader(
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
            validating: try #require(source.videoConfiguration?.ruleDrivenConfiguration?.rule)
        )
        let runtime: VideoRuleSourceRuntime = VideoRuleSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoRuleSourceListLoader(
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
            validating: try #require(source.videoConfiguration?.ruleDrivenConfiguration?.rule)
        )
        let runtime: VideoRuleSourceRuntime = VideoRuleSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoRuleSourceListLoader(
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
            validating: try #require(source.videoConfiguration?.ruleDrivenConfiguration?.rule)
        )
        let runtime: VideoRuleSourceRuntime = VideoRuleSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoRuleSourceListLoader(
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
            validating: try #require(source.videoConfiguration?.ruleDrivenConfiguration?.rule)
        )
        let runtime: VideoRuleSourceRuntime = VideoRuleSourceRuntime(
            source: source,
            resolvedRule: resolvedRule,
            listLoader: VideoRuleSourceListLoader(
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

    @Test func sourceRuntimeResolverRoutesRuleDrivenVideoWithoutLegacyDefinition() throws {
        let source: Source = Self.source(rule: Self.siteRule())
        var didUseRuleRuntime: Bool = false
        var didUseLegacyRuntime: Bool = false
        let resolver: SourceRuntimeResolver = SourceRuntimeResolver(
            videoRuntimeFactory: { definition in
                didUseLegacyRuntime = true
                return VideoRuleStubRuntime(definition: definition)
            },
            videoRuleRuntimeFactory: { source in
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
        #expect(didUseLegacyRuntime == false)
        #expect(runtime.definition.runtimeKind == .video)
        #expect(runtime.definition.video == nil)
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
}

private final class RecordingVideoRulePageContentLoader: PageContentLoader {
    let html: String
    private(set) var lastURL: URL?
    private(set) var lastRequest: RequestConfig?

    init(html: String) {
        self.html = html
    }

    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        self.lastURL = url
        self.lastRequest = request
        return self.html
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
