import Foundation
import BrowseCraftCore

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
    private let saveVideoWatchHistoryUseCase: SaveVideoWatchHistoryUseCase
    private let loadVideoWatchHistoryUseCase: LoadVideoWatchHistoryUseCase

    init(
        item: ContentItem,
        source: Source,
        runtimeResolver: any SourceRuntimeResolving,
        saveVideoWatchHistoryUseCase: SaveVideoWatchHistoryUseCase,
        loadVideoWatchHistoryUseCase: LoadVideoWatchHistoryUseCase
    ) {
        self.item = item
        self.source = source
        self.runtimeResolver = runtimeResolver
        self.saveVideoWatchHistoryUseCase = saveVideoWatchHistoryUseCase
        self.loadVideoWatchHistoryUseCase = loadVideoWatchHistoryUseCase

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
                context: self.runtimeContext(operation: .detail)
            )

            if let videoRuntime: any VideoPlaybackRuntimeCapability = runtime as? any VideoPlaybackRuntimeCapability {
                let content: VideoDetailContent = try await videoRuntime.loadVideoDetailContent(input)
                self.episodes = content.episodes
                self.synopsis = content.synopsis
                self.metadataRows = content.metadataRows
                #if DEBUG
                print(
                    "[BrowseCraftVideoDetail] loadEpisodes video-result " +
                    "source=\(self.source.id) " +
                    "episodes=\(content.episodes.count) " +
                    "firstEpisode=\(content.episodes.first?.id ?? "nil")"
                )
                #endif
            } else {
                let output: SourceDetailOutput = try await runtime.loadDetail(input)
                self.episodes = output.chapters.map { chapter in
                    return VideoEpisode(
                        id: chapter.id,
                        title: chapter.title,
                        playPageURL: chapter.url
                    )
                }
                self.synopsis = nil
                self.metadataRows = []
                #if DEBUG
                print(
                    "[BrowseCraftVideoDetail] loadEpisodes fallback-result " +
                    "source=\(self.source.id) " +
                    "episodes=\(self.episodes.count)"
                )
                #endif
            }
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: "video-detail-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    func openEpisode(_ episode: VideoEpisode) async {
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
            guard let playbackRuntime: any VideoPlaybackRuntimeCapability = runtime as? any VideoPlaybackRuntimeCapability else {
                throw SourceRuntimeError.unsupported(
                    .custom("Selected source does not expose video playback runtime.")
                )
            }

            let output: SourceVideoPlaybackOutput = try await playbackRuntime.loadPlayback(
                SourceVideoPlaybackInput(
                    playPageURL: episode.playPageURL,
                    context: self.runtimeContext(operation: nil)
                )
            )
            let playerViewModel: VideoPlayerViewModel = VideoPlayerViewModel(
                source: self.source,
                reference: output.reference,
                videoTitle: self.item.title,
                detailURL: URL(string: self.item.detailURL),
                coverURL: self.coverURL,
                saveVideoWatchHistoryUseCase: self.saveVideoWatchHistoryUseCase,
                loadVideoWatchHistoryUseCase: self.loadVideoWatchHistoryUseCase,
                runtimeResolver: self.runtimeResolver
            )
            self.playbackRoute = VideoPlaybackRoute(
                id: [
                    output.reference.vodID,
                    String(output.reference.sourceIndex),
                    String(output.reference.episodeIndex)
                ].joined(separator: "::"),
                viewModel: playerViewModel
            )
            #if DEBUG
            print(
                "[BrowseCraftVideoDetail] openEpisode playback-result " +
                "source=\(self.source.id) " +
                "episodeKey=\(output.reference.episodeKey) " +
                "mediaKind=\(output.reference.candidateMediaKind.rawValue) " +
                "status=\(output.reference.status)"
            )
            #endif
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: "video-playback-error")
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
