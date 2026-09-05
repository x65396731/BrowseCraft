import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft
import BrowseCraftDomain
import BrowseCraftRuntime

/// 历史记录里的直链会过期：从历史打开先按播放页规则重新解析；直链播放失败也按规则重试一次。
@MainActor
struct VideoPlayerViewModelHistoryTests {
    private typealias Harness = ViewModelTestHarness

    private final class ScriptedVideoPlaybackRuntime: SourceRuntime, SourceVideoPlaybackRuntime, @unchecked Sendable {
        let definition: SourceDefinition
        private let lock: NSLock = NSLock()
        private var handler: @Sendable (SourceVideoPlaybackInput) async throws -> SourceVideoPlaybackOutput
        private(set) var inputs: [SourceVideoPlaybackInput] = []

        init(source: Source, playback: @escaping @Sendable (SourceVideoPlaybackInput) async throws -> SourceVideoPlaybackOutput) {
            self.definition = SourceDefinitionMapper().definition(from: source)
            self.handler = playback
        }

        var capabilities: SourceRuntimeCapabilities {
            return SourceRuntimeCapabilities(
                supportsSearch: false, supportsPagination: false, supportsDetail: true, supportsReader: false,
                supportsPlayback: true, supportsDebug: false, supportsCandidateAnalysis: false,
                requiresWebView: false, requiresCookieStore: false, requiresAccount: false
            )
        }

        func loadList(_ input: SourceListInput) async throws -> SourceListOutput {
            throw SourceRuntimeError.unsupported(.custom("list not scripted"))
        }

        func loadPlayback(_ input: SourceVideoPlaybackInput) async throws -> SourceVideoPlaybackOutput {
            self.lock.lock()
            self.inputs.append(input)
            let handler = self.handler
            self.lock.unlock()
            return try await handler(input)
        }
    }

    private static func videoSource() -> Source {
        let rule: VideoSiteRule = VideoSiteRule(
            version: 2,
            name: "Video V2",
            baseUrl: "https://video.example.invalid/",
            site: SiteConfig(name: "Video V2", domain: "video.example.invalid", baseURL: "https://video.example.invalid/"),
            pages: [
                VideoPageRule(id: "latest", title: "Latest", type: .list, url: "/videos/", ruleRefs: VideoRuleRefs(list: "video-list"))
            ],
            ruleSets: VideoRuleSets(listRules: [
                VideoListRule(
                    id: "video-list",
                    item: ExtractRule(selector: ".video-card", selectorKind: .css, function: .raw),
                    fields: VideoListFields(
                        title: ExtractRule(selectorKind: .current, function: .text),
                        detailURL: ExtractRule(selectorKind: .current, function: .url, param: "href")
                    )
                )
            ])
        )
        let now: Date = Date(timeIntervalSince1970: 1_000)
        return Source(
            id: "video.history.test", name: rule.name, baseURL: rule.baseUrl, type: .html,
            configuration: .video(VideoSourceConfiguration(rule: rule)), enabled: true, createdAt: now, updatedAt: now
        )
    }

    nonisolated private static func reference(media: String?) -> SourceVideoPlaybackReference {
        return SourceVideoPlaybackReference(
            vodID: "51343", sourceIndex: 0, episodeIndex: 0,
            episodeKey: SourceVideoPlaybackReference.episodeKey(vodID: "51343", sourceIndex: 0, episodeIndex: 0),
            episodeTitle: "第1集",
            playPageURL: URL(string: "https://video.example.invalid/ep-51343-1-1.html")!,
            candidateMediaURL: media.flatMap(URL.init(string:)),
            candidateMediaKind: .m3u8,
            playbackRequestConfig: nil,
            nextEpisodeURL: nil,
            previousEpisodeURL: nil,
            sourceName: "Video V2",
            status: .playable
        )
    }

    nonisolated private static func output(media: String) -> SourceVideoPlaybackOutput {
        return SourceVideoPlaybackOutput(reference: Self.reference(media: media), diagnostics: .succeeded())
    }

    private static func makeViewModel(
        database: AppDatabase,
        source: Source,
        runtime: ScriptedVideoPlaybackRuntime,
        resolvesPlaybackOnPrepare: Bool
    ) -> VideoPlayerViewModel {
        let activeAppUser: ActiveAppUserStore = ActiveAppUserStore(initialUserID: UUID())
        let resolver: TestSourceRuntimeResolver = TestSourceRuntimeResolver(
            videoRuntimeFactory: { _ in runtime },
            comicRuntimeFactory: { source in ScriptedSourceRuntime(source: source) }
        )
        return VideoPlayerViewModel(
            source: source,
            reference: Self.reference(media: "https://old.cdn.invalid/index.m3u8"),
            videoTitle: "妖神记",
            detailURL: nil,
            coverURL: nil,
            persistenceCoordinator: ReadingActivityPersistenceCoordinator(
                rssRepository: GRDBRSSReadingHistoryRepository(database: database),
                comicRepository: GRDBComicChapterHistoryRepository(database: database),
                videoRepository: GRDBVideoWatchHistoryRepository(database: database),
                appUserRepository: GRDBAppUserRepository(database: database),
                activeAppUser: activeAppUser
            ),
            runtimeResolver: resolver,
            activeAppUser: activeAppUser,
            resolvesPlaybackOnPrepare: resolvesPlaybackOnPrepare,
            now: { Harness.fixedNow }
        )
    }

    @Test func historyPlaybackReResolvesFromThePlayPageBeforePlaying() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let source: Source = Self.videoSource()
        try GRDBSourceRepository(database: database).saveSource(source)
        let runtime = ScriptedVideoPlaybackRuntime(source: source) { _ in Self.output(media: "https://fresh.cdn.invalid/index.m3u8") }
        let viewModel: VideoPlayerViewModel = Self.makeViewModel(
            database: database, source: source, runtime: runtime, resolvesPlaybackOnPrepare: true
        )

        await viewModel.prepareForPlayback()

        #expect(runtime.inputs.map(\.playPageURL.absoluteString) == ["https://video.example.invalid/ep-51343-1-1.html"])
        #expect(viewModel.nativeMediaURL?.absoluteString == "https://fresh.cdn.invalid/index.m3u8")
        #expect(viewModel.errorMessage == nil)
    }

    @Test func historyPlaybackKeepsTheStoredMediaWhenRuleResolutionFails() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let source: Source = Self.videoSource()
        try GRDBSourceRepository(database: database).saveSource(source)
        let runtime = ScriptedVideoPlaybackRuntime(source: source) { _ in throw URLError(.notConnectedToInternet) }
        let viewModel: VideoPlayerViewModel = Self.makeViewModel(
            database: database, source: source, runtime: runtime, resolvesPlaybackOnPrepare: true
        )

        await viewModel.prepareForPlayback()

        #expect(runtime.inputs.count == 1)
        #expect(viewModel.nativeMediaURL?.absoluteString == "https://old.cdn.invalid/index.m3u8")
        // 中文注释：解析失败不弹错，继续用存下的直链兜底。
        #expect(viewModel.errorMessage == nil)
    }

    @Test func nativeFailureRecoversOnceThroughTheRuleThenReportsTheError() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let source: Source = Self.videoSource()
        try GRDBSourceRepository(database: database).saveSource(source)
        let runtime = ScriptedVideoPlaybackRuntime(source: source) { _ in Self.output(media: "https://fresh.cdn.invalid/index.m3u8") }
        let viewModel: VideoPlayerViewModel = Self.makeViewModel(
            database: database, source: source, runtime: runtime, resolvesPlaybackOnPrepare: false
        )
        await viewModel.prepareForPlayback()
        #expect(runtime.inputs.isEmpty)

        await viewModel.handleNativePlaybackFailure(URLError(.cannotFindHost))
        #expect(runtime.inputs.count == 1)
        #expect(viewModel.nativeMediaURL?.absoluteString == "https://fresh.cdn.invalid/index.m3u8")
        #expect(viewModel.errorMessage == nil)

        await viewModel.handleNativePlaybackFailure(URLError(.cannotFindHost))
        #expect(runtime.inputs.count == 1)
        #expect(viewModel.errorMessage != nil)
    }
}
