import Foundation
import BrowseCraftCore

// 中文注释：VideoEpisode 是 Video V2 详情页内部剧集模型，不属于已删除的 V1 runtime。
struct VideoEpisode: Identifiable, Hashable {
    var id: String
    var title: String
    var playPageURL: URL
    var sourceName: String? = nil
    var playbackHandoff: SourceVideoPlaybackHandoff? = nil
}

// 中文注释：VideoPlaybackRoute 承载视频详情页进入播放器时需要的 ViewModel。
struct VideoPlaybackRoute: Identifiable {
    let id: String
    let viewModel: VideoPlayerViewModel
}

// 中文注释：VideoDetailViewModel 负责加载视频剧集列表，并把单集解析成播放器入口。
@MainActor
final class VideoDetailViewModel: ObservableObject {
    @Published private(set) var episodes: [VideoEpisode] = []
    @Published private(set) var synopsis: String?
    @Published private(set) var metadataRows: [String] = []
    @Published private(set) var isLoadingEpisodes: Bool = false
    @Published private(set) var isLoadingPlayback: Bool = false
    @Published var playbackRoute: VideoPlaybackRoute?
    @Published var errorMessage: String?

    let item: ContentItem
    let source: Source

    private let runtimeResolver: any SourceRuntimeResolving
    private let itemReferenceMapper: SourceItemReferenceMapper = SourceItemReferenceMapper()
    private let saveVideoWatchHistoryUseCase: SaveVideoWatchHistoryUseCase
    private let loadVideoWatchHistoryUseCase: LoadVideoWatchHistoryUseCase
    private let accumulateAdPointsUseCase: AccumulateAdPointsUseCase?
    private let credentialProvider: any SourceCredentialProviding

    init(
        item: ContentItem,
        source: Source,
        runtimeResolver: any SourceRuntimeResolving,
        saveVideoWatchHistoryUseCase: SaveVideoWatchHistoryUseCase,
        loadVideoWatchHistoryUseCase: LoadVideoWatchHistoryUseCase,
        accumulateAdPointsUseCase: AccumulateAdPointsUseCase? = nil,
        credentialProvider: any SourceCredentialProviding = EmptySourceCredentialProvider()
    ) {
        self.item = item
        self.source = source
        self.runtimeResolver = runtimeResolver
        self.saveVideoWatchHistoryUseCase = saveVideoWatchHistoryUseCase
        self.loadVideoWatchHistoryUseCase = loadVideoWatchHistoryUseCase
        self.accumulateAdPointsUseCase = accumulateAdPointsUseCase
        self.credentialProvider = credentialProvider

        #if DEBUG
        print(
            "[BrowseCraftVideoDetail] init " +
            "source=\(source.id) " +
            "kind=\(source.configuration.kind.rawValue) " +
            "item=\(item.id) " +
            "detailURL=\(item.detailURL)"
        )
        #endif
    }

    var sourceName: String {
        return self.source.name
    }

    var coverURL: URL? {
        return self.item.coverURL.flatMap(URL.init(string:))
    }

    func loadEpisodesIfNeeded() async {
        if self.episodes.isEmpty == false || self.isLoadingEpisodes {
            return
        }

        await self.loadEpisodes()
    }

    func loadEpisodes() async {
        CrashDiagnostics.shared.setRuleStage(.detail)
        guard let detailURL: URL = URL(string: self.item.detailURL) else {
            self.errorMessage = "Video detail URL is invalid."
            return
        }

        self.isLoadingEpisodes = true
        defer {
            self.isLoadingEpisodes = false
        }

        do {
            let runtime: any SourceRuntime = try self.runtimeResolver.runtime(for: self.source)
            #if DEBUG
            print(
                "[BrowseCraftVideoDetail] loadEpisodes request " +
                "source=\(self.source.id) " +
                "item=\(self.item.id) " +
                "detailURL=\(detailURL.absoluteString) " +
                "runtime=\(type(of: runtime))"
            )
            #endif
            let input: SourceDetailInput = SourceDetailInput(
                detailURL: detailURL,
                context: self.runtimeContext(operation: .detail),
                itemReference: self.itemReferenceMapper.reference(
                    from: self.item,
                    intent: .detail
                )
            )

            guard let detailRuntime: any SourceDetailRuntime = runtime as? any SourceDetailRuntime else {
                throw SourceRuntimeError.unsupported(
                    .custom("Selected source does not expose detail runtime capability.")
                )
            }
            let output: SourceDetailOutput = try await detailRuntime.loadDetail(input)
            self.episodes = output.chapters.map { chapter in
                return VideoEpisode(
                    id: chapter.id,
                    title: chapter.title,
                    playPageURL: chapter.url,
                    sourceName: chapter.subtitle,
                    playbackHandoff: chapter.videoPlaybackHandoff
                )
            }
            self.synopsis = output.metadata?.description
            self.metadataRows = output.metadata?.attributes.map(\.displayText) ?? []
            #if DEBUG
            print(
                "[BrowseCraftVideoDetail] loadEpisodes runtime-result " +
                "source=\(self.source.id) " +
                "episodes=\(self.episodes.count) " +
                "firstEpisode=\(self.episodes.first?.id ?? "nil") " +
                "hasSynopsis=\(self.synopsis?.isEmpty == false) " +
                "metadataRows=\(self.metadataRows.count)"
            )
            #endif
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: "video-detail-error")
            AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .detail, errorCode: "video-detail-error")
            CrashDiagnostics.shared.record(
                error: error,
                category: .parser,
                errorCode: "video-detail-error",
                event: "video-detail-error"
            )
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    func openEpisode(_ episode: VideoEpisode) async {
        CrashDiagnostics.shared.setRuleStage(.videoPlayback)
        if self.isLoadingPlayback {
            return
        }

        self.isLoadingPlayback = true
        defer {
            self.isLoadingPlayback = false
        }

        do {
            let runtime: any SourceRuntime = try self.runtimeResolver.runtime(for: self.source)
            #if DEBUG
            print(
                "[BrowseCraftVideoDetail] openEpisode request " +
                "source=\(self.source.id) " +
                "episode=\(episode.id) " +
                "playPageURL=\(episode.playPageURL.absoluteString)"
            )
            #endif
            let reference: SourceVideoPlaybackReference
            guard let playbackRuntime: any SourceVideoPlaybackRuntime = runtime as? any SourceVideoPlaybackRuntime else {
                throw SourceRuntimeError.unsupported(
                    .custom("Selected source does not expose video playback runtime.")
                )
            }
            let output: SourceVideoPlaybackOutput = try await playbackRuntime.loadPlayback(
                SourceVideoPlaybackInput(
                    playPageURL: episode.playPageURL,
                    context: self.runtimeContext(operation: .playback),
                    handoff: episode.playbackHandoff
                )
            )
            reference = output.reference

            let playerViewModel: VideoPlayerViewModel = VideoPlayerViewModel(
                source: self.source,
                reference: reference,
                videoTitle: self.item.title,
                detailURL: URL(string: self.item.detailURL),
                coverURL: self.coverURL,
                saveVideoWatchHistoryUseCase: self.saveVideoWatchHistoryUseCase,
                loadVideoWatchHistoryUseCase: self.loadVideoWatchHistoryUseCase,
                accumulateAdPointsUseCase: self.accumulateAdPointsUseCase,
                runtimeResolver: self.runtimeResolver,
                credentialProvider: self.credentialProvider
            )
            self.playbackRoute = VideoPlaybackRoute(
                id: [
                    reference.vodID,
                    String(reference.sourceIndex),
                    String(reference.episodeIndex)
                ].joined(separator: "::"),
                viewModel: playerViewModel
            )
            #if DEBUG
            print(
                "[BrowseCraftVideoDetail] openEpisode playback-result " +
                "source=\(self.source.id) " +
                "episodeKey=\(reference.episodeKey) " +
                "mediaKind=\(reference.candidateMediaKind.rawValue) " +
                "status=\(reference.status)"
            )
            #endif
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .playback, event: "video-playback-error")
            AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .videoPlayback, errorCode: "video-playback-error")
            CrashDiagnostics.shared.record(
                error: error,
                category: .playback,
                errorCode: "video-playback-error",
                event: "video-playback-error"
            )
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    private func runtimeContext(operation: SourceRuntimeOperation?) -> SourceRuntimeContext {
        let listContext: ListContext? = self.item.listContext
        return SourceRuntimeContext(
            sourceID: self.source.id,
            pageID: listContext?.pageId,
            tabID: listContext?.tabId,
            sectionID: listContext?.sectionId,
            sectionRole: nil,
            ruleID: listContext?.listRuleId,
            requestOverride: nil,
            debugMode: false,
            operation: operation
        )
    }
}
