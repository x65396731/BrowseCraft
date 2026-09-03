import Foundation
@preconcurrency import BrowseCraftCore
import BrowseCraftDomain

// 中文注释：VideoEpisode 是 Video V2 详情页内部剧集模型，不属于已删除的 V1 runtime。
struct VideoEpisode: Identifiable, Hashable {
    var id: String
    var title: String
    var playPageURL: URL
    var sourceName: String? = nil
    var playbackHandoff: SourceVideoPlaybackHandoff? = nil
}

private struct VideoEpisodeDisplayGroup: Hashable {
    let subtitle: String?
    let chapters: [SourceChapter]
}

// 中文注释：VideoPlaybackRoute 承载视频详情页进入播放器时需要的 ViewModel。
struct VideoPlaybackRoute: Identifiable {
    let id: String
    let viewModel: VideoPlayerViewModel
}

// 中文注释：VideoDetailViewModel 负责加载视频剧集列表，并把单集解析成播放器入口。
@MainActor
final class VideoDetailViewModel: ObservableObject {
    private static let sourceDetectionLexicon: SourceDetectionLexicon = .default

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
    private let persistenceCoordinator: ReadingActivityPersistenceCoordinator
    private let credentialProvider: any SourceCredentialProviding
    private let systemCookieHeaderProvider: any SystemCookieHeaderProviding
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let fallbackUserID: String

    init(
        item: ContentItem,
        source: Source,
        runtimeResolver: any SourceRuntimeResolving,
        persistenceCoordinator: ReadingActivityPersistenceCoordinator,
        credentialProvider: any SourceCredentialProviding = EmptySourceCredentialProvider(),
        systemCookieHeaderProvider: any SystemCookieHeaderProviding = EmptySystemCookieHeaderProvider(),
        activeAppUser: (any ActiveAppUserProviding)? = nil,
        userID: String = AppUser.localDefaultID
    ) {
        self.item = item
        self.source = source
        self.runtimeResolver = runtimeResolver
        self.persistenceCoordinator = persistenceCoordinator
        self.credentialProvider = credentialProvider
        self.systemCookieHeaderProvider = systemCookieHeaderProvider
        self.activeAppUser = activeAppUser
        self.fallbackUserID = userID

        #if DEBUG
        AppDebugLog.write(
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

    static func filteredEpisodeChapters(
        from chapters: [SourceChapter]
    ) -> [SourceChapter] {
        let groups: [VideoEpisodeDisplayGroup] = self.displayGroups(from: chapters)
        guard groups.count > 1 else {
            return chapters
        }

        return groups
            .filter { candidate in
                self.shouldKeepEpisodeGroup(candidate, among: groups)
            }
            .flatMap(\.chapters)
    }

    private static func displayGroups(
        from chapters: [SourceChapter]
    ) -> [VideoEpisodeDisplayGroup] {
        var groups: [VideoEpisodeDisplayGroup] = []
        var currentSubtitle: String?
        var currentChapters: [SourceChapter] = []

        func flushCurrentGroup() {
            guard currentChapters.isEmpty == false else {
                return
            }
            groups.append(
                VideoEpisodeDisplayGroup(
                    subtitle: currentSubtitle,
                    chapters: currentChapters
                )
            )
            currentChapters = []
        }

        for chapter in chapters {
            let normalizedSubtitle: String? = self.trimmedSubtitle(chapter.subtitle)
            if currentChapters.isEmpty {
                currentSubtitle = normalizedSubtitle
                currentChapters = [chapter]
                continue
            }

            if normalizedSubtitle == currentSubtitle {
                currentChapters.append(chapter)
                continue
            }

            flushCurrentGroup()
            currentSubtitle = normalizedSubtitle
            currentChapters = [chapter]
        }

        flushCurrentGroup()
        return groups
    }

    private static func shouldKeepEpisodeGroup(
        _ candidate: VideoEpisodeDisplayGroup,
        among groups: [VideoEpisodeDisplayGroup]
    ) -> Bool {
        if self.isSingletonDuplicateEntryGroup(candidate, among: groups) {
            return false
        }

        guard self.isSuspiciousEpisodeGroupTitle(candidate.subtitle),
              candidate.chapters.count >= 2 else {
            return true
        }

        let candidateTitles: Set<String> = Set(
            candidate.chapters.compactMap { self.normalizedEpisodeTitle($0.title) }
        )
        guard candidateTitles.isEmpty == false else {
            return true
        }

        for other in groups {
            guard other != candidate else {
                continue
            }

            let otherTitles: Set<String> = Set(
                other.chapters.compactMap { self.normalizedEpisodeTitle($0.title) }
            )
            guard otherTitles.isEmpty == false else {
                continue
            }

            let overlapCount: Int = candidateTitles.intersection(otherTitles).count
            let overlapRatio: Double = Double(overlapCount) / Double(min(candidateTitles.count, otherTitles.count))
            if overlapRatio >= 0.7 {
                return false
            }
        }

        return true
    }

    private static func isSingletonDuplicateEntryGroup(
        _ candidate: VideoEpisodeDisplayGroup,
        among groups: [VideoEpisodeDisplayGroup]
    ) -> Bool {
        guard candidate.chapters.count == 1,
              let candidateURL: URL = candidate.chapters.first?.url else {
            return false
        }

        for other in groups {
            guard other != candidate,
                  other.chapters.count >= 2 else {
                continue
            }

            if other.chapters.contains(where: { $0.url == candidateURL }) {
                return true
            }
        }

        return false
    }

    private static func isSuspiciousEpisodeGroupTitle(_ subtitle: String?) -> Bool {
        guard let subtitle: String = self.trimmedSubtitle(subtitle) else {
            return false
        }

        return self.sourceDetectionLexicon.containsMarker(
            in: subtitle,
            category: .episodeGroupNoise
        )
    }

    private static func normalizedEpisodeTitle(_ value: String) -> String? {
        let normalized: String = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(
                of: #"[^a-z0-9\u4e00-\u9fff]+"#,
                with: "",
                options: .regularExpression
            )
        return normalized.isEmpty ? nil : normalized
    }

    private static func trimmedSubtitle(_ subtitle: String?) -> String? {
        guard let subtitle else {
            return nil
        }
        let trimmed: String = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
            AppDebugLog.write(
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
            #if DEBUG
            self.logEpisodeGroupDiagnostics(chapters: output.chapters)
            #endif
            let filteredChapters: [SourceChapter] = Self.filteredEpisodeChapters(from: output.chapters)
            self.episodes = filteredChapters.map { chapter in
                return VideoEpisode(
                    id: chapter.id,
                    title: chapter.title,
                    playPageURL: chapter.url,
                    sourceName: chapter.subtitle,
                    playbackHandoff: chapter.videoPlaybackHandoff
                )
            }
            if self.episodes.isEmpty, let action: SourceVideoDetailPlaybackAction = output.videoPlaybackAction {
                self.episodes = [
                    VideoEpisode(
                        id: action.id,
                        title: action.title,
                        playPageURL: action.playPageURL,
                        sourceName: action.sourceName,
                        playbackHandoff: action.handoff
                    )
                ]
            }
            self.synopsis = output.metadata?.description
            self.metadataRows = output.metadata?.attributes.map(\.displayText) ?? []
            #if DEBUG
            AppDebugLog.write(
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

    #if DEBUG
    private func logEpisodeGroupDiagnostics(chapters: [SourceChapter]) {
        let groups: [VideoEpisodeDisplayGroup] = Self.displayGroups(from: chapters)
        guard groups.isEmpty == false else {
            return
        }

        AppDebugLog.write(
            "[BrowseCraftVideoDetail] group-diagnostics " +
            "source=\(self.source.id) " +
            "item=\(self.item.id) " +
            "groupCount=\(groups.count)"
        )

        for (index, group) in groups.prefix(4).enumerated() {
            let bestMatch: (index: Int, overlap: Double)? = self.bestOverlap(for: index, in: groups)
            let kept: Bool = Self.shouldKeepEpisodeGroup(group, among: groups)
            let titlePreview: String = group.chapters
                .prefix(6)
                .map(\.title)
                .joined(separator: " | ")
            let urlPreview: String = group.chapters
                .prefix(3)
                .map { $0.url.absoluteString }
                .joined(separator: " | ")

            AppDebugLog.write(
                "[BrowseCraftVideoDetail] group[\(index)] " +
                "subtitle=\(group.subtitle ?? "nil") " +
                "chapterCount=\(group.chapters.count) " +
                "kept=\(kept) " +
                "bestMatchIndex=\(bestMatch?.index.description ?? "nil") " +
                "bestOverlap=\(bestMatch.map { String(format: "%.2f", $0.overlap) } ?? "nil") " +
                "titles=\(titlePreview) " +
                "urls=\(urlPreview)"
            )
        }
    }

    private func bestOverlap(
        for candidateIndex: Int,
        in groups: [VideoEpisodeDisplayGroup]
    ) -> (index: Int, overlap: Double)? {
        let candidate: VideoEpisodeDisplayGroup = groups[candidateIndex]
        let candidateTitles: Set<String> = Set(
            candidate.chapters.compactMap { Self.normalizedEpisodeTitle($0.title) }
        )
        guard candidateTitles.isEmpty == false else {
            return nil
        }

        var best: (index: Int, overlap: Double)?
        for (otherIndex, other) in groups.enumerated() where otherIndex != candidateIndex {
            let otherTitles: Set<String> = Set(
                other.chapters.compactMap { Self.normalizedEpisodeTitle($0.title) }
            )
            guard otherTitles.isEmpty == false else {
                continue
            }

            let overlapCount: Int = candidateTitles.intersection(otherTitles).count
            let overlapRatio: Double = Double(overlapCount) / Double(min(candidateTitles.count, otherTitles.count))
            if let best, best.overlap >= overlapRatio {
                continue
            }
            best = (index: otherIndex, overlap: overlapRatio)
        }

        return best
    }
    #endif

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
            AppDebugLog.write(
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
                persistenceCoordinator: self.persistenceCoordinator,
                runtimeResolver: self.runtimeResolver,
                credentialProvider: self.credentialProvider,
                systemCookieHeaderProvider: self.systemCookieHeaderProvider,
                activeAppUser: self.activeAppUser,
                userID: self.currentUserID
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
            AppDebugLog.write(
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

    private var currentUserID: String {
        return self.activeAppUser?.currentUserID.uuidString ?? self.fallbackUserID
    }
}
