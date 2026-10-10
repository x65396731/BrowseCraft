import Observation
import Foundation
@preconcurrency import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftRuntime

// 中文注释：VideoEpisode 是 Video V2 详情页内部剧集模型，不属于已删除的 V1 runtime。
struct VideoEpisode: Identifiable, Hashable {
    var id: String
    var title: String
    var playPageURL: URL
    var sourceName: String? = nil
    var playbackHandoff: SourceVideoPlaybackHandoff? = nil
    /// 中文注释：规则给了才有；nil 不标（`docs/design/Video-Detail-Page-Redesign-Design.md` 第六节）。
    var isRestricted: Bool? = nil
    var isPaid: Bool? = nil
}

/// 一条线路：同一 `sourceName`（group 标题 / titleStrip / App 切出来的「线路 N」）下连续的选集；没有线路名的站只有一条、`title` 为 nil。
struct VideoEpisodeLine: Identifiable, Hashable {
    let id: String
    let title: String?
    let episodes: [VideoEpisode]
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
@Observable
final class VideoDetailViewModel {
    private static let sourceDetectionLexicon: SourceDetectionLexicon = .default

    /// 中文注释：集表、历史、线路选择一变就把派生状态算一次存起来（2026-10-10 复审 B-6）：之前 `lines` 等都是计算属性，
    /// 一次 body 重新分组 5 到 6 次，每个格子再对全表 `first(where:)` 找「上次看的那一集」——500 集的页面一次渲染 33 ms。
    private(set) var episodes: [VideoEpisode] = [] {
        didSet { self.rebuildEpisodeDerivedState() }
    }
    private(set) var synopsis: String?
    private(set) var metadataRows: [String] = []
    /// 规则给的元数据原样留着，页面按 `key` 决定摆哪（第五节、第九节）。
    private(set) var metadataAttributes: [SourceDetailAttribute] = []
    private(set) var detailTitle: String?
    private(set) var detailCoverURL: URL?
    private(set) var isLoadingEpisodes: Bool = false
    private(set) var hasLoadedEpisodes: Bool = false
    private(set) var isLoadingPlayback: Bool = false
    /// 正在解析的那一集（格子里转圈）；继续看按钮解析时为 `continueResolving`。
    private(set) var resolvingEpisodeID: String?
    private(set) var isResolvingContinue: Bool = false
    var playbackRoute: VideoPlaybackRoute?
    /// 详情取失败：网格位置的失败态，不弹警告框。
    private(set) var detailErrorMessage: String?
    /// 解析播放失败：网格上方的警示横幅，点别的集时清掉。
    private(set) var playbackErrorMessage: String?
    /// 本作品最近一条历史（继续看按钮与集号高亮）。
    private(set) var continueWatchingHistory: VideoWatchHistory? {
        didSet { self.rebuildContinueDerivedState() }
    }
    private(set) var isFavorite: Bool = false
    /// 当前线路；nil 时取含上次看的那一集的线路，再没有取第一条。
    private(set) var selectedLineID: String? {
        didSet { self.rebuildSelectionDerivedState() }
    }
    var isDescendingOrder: Bool = false {
        didSet { self.rebuildSelectionDerivedState() }
    }
    /// 派生状态：按 `sourceName` 分出的线路、当前线路、当前线路按顺序的集、是否等宽网格、历史对上的那一集、格子文字。
    private(set) var lines: [VideoEpisodeLine] = []
    private(set) var selectedLine: VideoEpisodeLine?
    private(set) var visibleEpisodes: [VideoEpisode] = []
    private(set) var usesNumericGrid: Bool = false
    private(set) var continueTargetEpisode: VideoEpisode?
    /// 集名 → 紧凑集号；解不出数字的集不在表里。
    private var compactLabelsByTitle: [String: String] = [:]

    let item: ContentItem
    let source: Source

    private let runtimeResolver: any SourceRuntimeResolving
    private let itemReferenceMapper: SourceItemReferenceMapper = SourceItemReferenceMapper()
    private let persistenceCoordinator: ReadingActivityPersistenceCoordinator
    private let credentialProvider: any SourceCredentialProviding
    private let systemCookieHeaderProvider: any SystemCookieHeaderProviding
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let fallbackUserID: String
    private let toggleFavoriteUseCase: ToggleFavoriteUseCase?
    /// 中文注释：收藏读写走 actor，不在主线程跑 GRDB（复审 B-3）。
    private let favoritePersistence: FavoriteStatePersistenceCoordinator?
    private let videoPlayerViewModelFactory: (@MainActor (VideoWatchHistory, Source) -> VideoPlayerViewModel)?
    private let now: () -> Date

    init(
        item: ContentItem,
        source: Source,
        runtimeResolver: any SourceRuntimeResolving,
        persistenceCoordinator: ReadingActivityPersistenceCoordinator,
        credentialProvider: any SourceCredentialProviding = EmptySourceCredentialProvider(),
        systemCookieHeaderProvider: any SystemCookieHeaderProviding = EmptySystemCookieHeaderProvider(),
        activeAppUser: (any ActiveAppUserProviding)? = nil,
        userID: String = AppUser.localDefaultID,
        toggleFavoriteUseCase: ToggleFavoriteUseCase? = nil,
        videoPlayerViewModelFactory: (@MainActor (VideoWatchHistory, Source) -> VideoPlayerViewModel)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.item = item
        self.source = source
        self.runtimeResolver = runtimeResolver
        self.persistenceCoordinator = persistenceCoordinator
        self.credentialProvider = credentialProvider
        self.systemCookieHeaderProvider = systemCookieHeaderProvider
        self.activeAppUser = activeAppUser
        self.fallbackUserID = userID
        self.toggleFavoriteUseCase = toggleFavoriteUseCase
        self.favoritePersistence = toggleFavoriteUseCase.map(FavoriteStatePersistenceCoordinator.init(useCase:))
        self.videoPlayerViewModelFactory = videoPlayerViewModelFactory
        self.now = now

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
            return self.labelingRepeatedRoutes(chapters)
        }

        return groups
            .filter { candidate in
                self.shouldKeepEpisodeGroup(candidate, among: groups)
            }
            .flatMap(\.chapters)
    }

    /// 中文注释：用户 2026-09-29「选集按片源分组显示」（选「App 按重复集号切线路」）。整份选集都没有线路名、
    /// 而第一集的标题在后面又出现时，说明规则把几条线路的选集接成了一份扁平列表（小宝影院两组「第01集…」）：
    /// 从每次重新出现处切开，依次标「线路 1 / 线路 2 …」。只改显示、不增删选集；规则带了线路名的站原样不动。
    static func labelingRepeatedRoutes(_ chapters: [SourceChapter]) -> [SourceChapter] {
        guard chapters.count >= 2,
              chapters.allSatisfy({ self.trimmedSubtitle($0.subtitle) == nil }),
              let firstTitle: String = chapters.first.flatMap({ self.normalizedEpisodeTitle($0.title) }) else {
            return chapters
        }
        var routeIndex: Int = 0
        var labeled: [SourceChapter] = []
        for (index, chapter) in chapters.enumerated() {
            if index == 0 || self.normalizedEpisodeTitle(chapter.title) == firstTitle {
                routeIndex += 1
            }
            var copy: SourceChapter = chapter
            copy.subtitle = String(
                format: NSLocalizedString("video_episode_route_label", comment: ""),
                routeIndex
            )
            labeled.append(copy)
        }
        return routeIndex >= 2 ? labeled : chapters
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
            self.detailErrorMessage = NSLocalizedString("video_detail_invalid_url", comment: "详情地址无效")
            self.hasLoadedEpisodes = true
            return
        }

        self.isLoadingEpisodes = true
        self.detailErrorMessage = nil
        defer {
            self.isLoadingEpisodes = false
            self.hasLoadedEpisodes = true
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
                    playbackHandoff: chapter.videoPlaybackHandoff,
                    isRestricted: chapter.isRestricted,
                    isPaid: chapter.isPaid
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
            self.synopsis = Self.nonEmpty(output.metadata?.description)
            self.metadataAttributes = output.metadata?.attributes ?? []
            self.metadataRows = self.metadataAttributes.map(\.displayText)
            self.detailTitle = Self.nonEmpty(output.metadata?.title)
            self.detailCoverURL = output.metadata?.coverURL
            self.ensureSelectedLine()
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
            AppAnalytics.shared.logDiagnosticFailure(kind: RuleExecutionErrorClassifier.diagnosticFailureKind(for: error), stage: .detail, errorCode: "video-detail-error")
            CrashDiagnostics.shared.record(
                error: error,
                category: .parser,
                errorCode: "video-detail-error",
                event: "video-detail-error"
            )
            self.detailErrorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
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
        self.resolvingEpisodeID = episode.id
        self.playbackErrorMessage = nil
        defer {
            self.isLoadingPlayback = false
            self.resolvingEpisodeID = nil
            self.isResolvingContinue = false
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
            // 中文注释：为什么没走直接媒体——把 Runtime 的抽取计数与诊断 issue 原样打出来，
            // 不在 App 里再做一遍判断（用户 2026-09-05 要求 HLS 探测原因可见）。
            let extractionSummary: String = output.diagnostics.extractionLogs.map { log in
                "\(log.field)=\(log.candidateCount)/\(log.outputCount)"
            }.joined(separator: " ")
            AppDebugLog.write(
                "[BrowseCraftVideoDetail] openEpisode playback-diagnostics " +
                "source=\(self.source.id) " +
                "episodeKey=\(reference.episodeKey) " +
                "extraction=[\(extractionSummary)]"
            )
            for issue in output.diagnostics.issues {
                AppDebugLog.write(
                    "[BrowseCraftVideoDetail] openEpisode playback-issue " +
                    "source=\(self.source.id) " +
                    "id=\(issue.id) severity=\(issue.severity.rawValue) message=\(issue.message)"
                )
            }
            #endif
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .playback, event: "video-playback-error")
            AppAnalytics.shared.logDiagnosticFailure(kind: RuleExecutionErrorClassifier.diagnosticFailureKind(for: error), stage: .videoPlayback, errorCode: "video-playback-error")
            CrashDiagnostics.shared.record(
                error: error,
                category: .playback,
                errorCode: "video-playback-error",
                event: "video-playback-error"
            )
            // 中文注释：解析失败走网格上方的横幅，不弹警告框（第八节）；原因照 classifier 的用户文案。
            self.playbackErrorMessage = String(
                format: NSLocalizedString("video_detail_resolve_failed", comment: ""),
                episode.title
            ) + "\n" + RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    // MARK: - 线路与集号（第六节）

    /// 按 `sourceName` 把连续的选集归成线路；没有线路名的站只有一条。
    private static func makeLines(from episodes: [VideoEpisode]) -> [VideoEpisodeLine] {
        var lines: [VideoEpisodeLine] = []
        var currentTitle: String?? = nil
        var current: [VideoEpisode] = []
        func flush() {
            guard current.isEmpty == false else {
                return
            }
            let title: String? = currentTitle ?? nil
            lines.append(VideoEpisodeLine(id: title ?? "line-\(lines.count)", title: title, episodes: current))
            current = []
        }
        for episode: VideoEpisode in episodes {
            let title: String? = Self.nonEmpty(episode.sourceName)
            if current.isEmpty == false, (currentTitle ?? nil) != title {
                flush()
            }
            currentTitle = .some(title)
            current.append(episode)
        }
        flush()
        return lines
    }

    /// 集表变了：重新分线路、重算每个集名的紧凑集号，再往下算历史与线路选择。
    private func rebuildEpisodeDerivedState() {
        self.lines = Self.makeLines(from: self.episodes)
        var labels: [String: String] = [:]
        for episode: VideoEpisode in self.episodes where labels[episode.title] == nil {
            if let label: String = Self.compactEpisodeLabel(episode.title) {
                labels[episode.title] = label
            }
        }
        self.compactLabelsByTitle = labels
        self.rebuildContinueDerivedState()
    }

    /// 历史变了：重新对「上次看的那一集」，它会影响默认选中的线路。
    private func rebuildContinueDerivedState() {
        self.continueTargetEpisode = Self.continueTarget(in: self.episodes, history: self.continueWatchingHistory)
        self.rebuildSelectionDerivedState()
    }

    /// 线路选择或顺序变了：当前线路、可见的集、是否等宽网格。
    private func rebuildSelectionDerivedState() {
        let lines: [VideoEpisodeLine] = self.lines
        let selected: VideoEpisodeLine?
        if let selectedLineID: String = self.selectedLineID,
           let line: VideoEpisodeLine = lines.first(where: { $0.id == selectedLineID }) {
            selected = line
        } else if let target: VideoEpisode = self.continueTargetEpisode,
                  let line: VideoEpisodeLine = lines.first(where: { $0.episodes.contains(target) }) {
            selected = line
        } else {
            selected = lines.first
        }
        self.selectedLine = selected
        let episodes: [VideoEpisode] = selected?.episodes ?? []
        self.visibleEpisodes = self.isDescendingOrder ? episodes.reversed() : episodes
        // 当前线路的集名都解得出数字时用等宽网格，否则按内容宽排。
        self.usesNumericGrid = episodes.isEmpty == false
            && episodes.allSatisfy { self.compactLabelsByTitle[$0.title] != nil }
    }

    func selectLine(_ lineID: String) {
        self.selectedLineID = lineID
        self.playbackErrorMessage = nil
    }

    private func ensureSelectedLine() {
        guard let selectedLineID: String = self.selectedLineID,
              self.lines.contains(where: { $0.id == selectedLineID }) == false else {
            return
        }
        self.selectedLineID = nil
    }

    /// 中文注释：两条正则进程内只编译一次（2026-10-10 复审 B-9：`range(of:options:.regularExpression)` 每次调用都重编译，
    /// 500 集的页面一次渲染上千次）。编译失败用可选值兜底，不强制解包（`BCA-ARCH-005`）。
    private static let episodeNumberPattern: NSRegularExpression? = try? NSRegularExpression(pattern: #"\d+"#, options: [])
    private static let episodeLabelNoisePattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^(第|ep|episode|e|#|话|話|集|回|期|\s|\.|-|_)*$"#,
        options: [.caseInsensitive]
    )

    /// 格子里显示什么：「第01集」「01」「EP 12」「第 3 话」→「01」「12」「03」；解不出数字的显示原文。
    /// 只影响显示，不改顺序、不进存储。
    static func compactEpisodeLabel(_ title: String) -> String? {
        let trimmed: String = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let numberPattern: NSRegularExpression = Self.episodeNumberPattern,
              let noisePattern: NSRegularExpression = Self.episodeLabelNoisePattern,
              let numberMatch: NSTextCheckingResult = numberPattern.firstMatch(
                in: trimmed,
                options: [],
                range: NSRange(trimmed.startIndex..., in: trimmed)
              ),
              let numberRange: Range<String.Index> = Range(numberMatch.range, in: trimmed) else {
            return nil
        }
        let rest: String = trimmed.replacingCharacters(in: numberRange, with: "")
        // 中文注释：去掉数字后只剩「第 / EP / 集 / 分隔符」这类噪音才算纯编号；整串匹配即为噪音。
        guard noisePattern.firstMatch(in: rest, options: [], range: NSRange(rest.startIndex..., in: rest)) != nil,
              let number: Int = Int(trimmed[numberRange]) else {
            return nil
        }
        return number < 10 ? "0\(number)" : String(number)
    }

    func displayLabel(for episode: VideoEpisode) -> String {
        return self.compactLabelsByTitle[episode.title] ?? episode.title
    }

    // MARK: - 继续看（第七节）

    /// 历史对上的那一集：先按播放页地址，再按集名。
    private static func continueTarget(in episodes: [VideoEpisode], history: VideoWatchHistory?) -> VideoEpisode? {
        guard let history: VideoWatchHistory = history else {
            return nil
        }
        if let byURL: VideoEpisode = episodes.first(where: { $0.playPageURL == history.playPageURL }) {
            return byURL
        }
        guard let episodeTitle: String = Self.nonEmpty(history.episodeTitle) else {
            return nil
        }
        return episodes.first { $0.title == episodeTitle }
    }

    /// 继续看按钮要开的集：看完了就是下一集；对不上任何一集为 nil（此时用历史记录直接开播放器）。
    var continueActionEpisode: VideoEpisode? {
        guard let history: VideoWatchHistory = self.continueWatchingHistory else {
            return self.episodes.count == 1 ? self.episodes.first : self.lines.first?.episodes.first
        }
        guard let target: VideoEpisode = self.continueTargetEpisode else {
            return nil
        }
        if self.isFinished(history), let next: VideoEpisode = self.nextEpisode(after: target) {
            return next
        }
        return target
    }

    var continueButtonTitle: String {
        if self.episodes.count == 1, self.continueWatchingHistory == nil {
            return NSLocalizedString("video_detail_play", comment: "")
        }
        guard let history: VideoWatchHistory = self.continueWatchingHistory else {
            guard let first: VideoEpisode = self.lines.first?.episodes.first else {
                return NSLocalizedString("video_detail_play", comment: "")
            }
            if Self.compactEpisodeLabel(first.title) != nil {
                return NSLocalizedString("video_detail_start_from_first", comment: "")
            }
            return String(format: NSLocalizedString("video_detail_start_with", comment: ""), first.title)
        }
        let target: VideoEpisode? = self.continueTargetEpisode
        let targetTitle: String = target?.title ?? Self.nonEmpty(history.episodeTitle) ?? self.item.title
        // 中文注释：只有一集时集名往往就是页面标题（电影站），按钮上不重复写它。
        let isSingle: Bool = self.episodes.count == 1
        if let target, self.isFinished(history) {
            if let next: VideoEpisode = self.nextEpisode(after: target) {
                return String(format: NSLocalizedString("video_detail_next_episode", comment: ""), next.title)
            }
            return isSingle
                ? NSLocalizedString("video_detail_rewatch_single", comment: "")
                : String(format: NSLocalizedString("video_detail_rewatch", comment: ""), targetTitle)
        }
        return isSingle
            ? NSLocalizedString("video_detail_continue_single", comment: "")
            : String(format: NSLocalizedString("video_detail_continue", comment: ""), targetTitle)
    }

    /// 按钮右侧小字「23:14 / 45:00」；看完或没播起来不写。
    var continueButtonSubtitle: String? {
        guard let history: VideoWatchHistory = self.continueWatchingHistory,
              self.isFinished(history) == false,
              history.lastPlaybackTime > 0 else {
            return nil
        }
        if let duration: TimeInterval = history.duration, duration > 0 {
            return HistoryViewModel.clockText(history.lastPlaybackTime) + " / " + HistoryViewModel.clockText(duration)
        }
        return HistoryViewModel.clockText(history.lastPlaybackTime)
    }

    private func isFinished(_ history: VideoWatchHistory) -> Bool {
        guard let duration: TimeInterval = history.duration, duration > 0 else {
            return false
        }
        return history.lastPlaybackTime >= duration * HistoryViewModel.finishedThreshold
    }

    private func nextEpisode(after episode: VideoEpisode) -> VideoEpisode? {
        guard let line: VideoEpisodeLine = self.lines.first(where: { $0.episodes.contains(episode) }),
              let index: Int = line.episodes.firstIndex(of: episode),
              index + 1 < line.episodes.count else {
            return nil
        }
        return line.episodes[index + 1]
    }

    @MainActor
    func openContinue() async {
        if let episode: VideoEpisode = self.continueActionEpisode {
            self.isResolvingContinue = true
            await self.openEpisode(episode)
            return
        }
        // 中文注释：规则换过、站点改了地址，历史对不上任何一集：用历史记录直接开播放器，与历史页点行同一条路。
        guard let history: VideoWatchHistory = self.continueWatchingHistory,
              let factory: @MainActor (VideoWatchHistory, Source) -> VideoPlayerViewModel = self.videoPlayerViewModelFactory else {
            return
        }
        self.playbackRoute = VideoPlaybackRoute(id: history.id, viewModel: factory(history, self.source))
    }

    /// 进页、下拉、播放器关闭后都重读一次本作品的历史。
    func reloadContinueWatching() async {
        do {
            let transfer: VideoWatchHistoryTransfer? = try await self.persistenceCoordinator.loadLatestVideoHistory(
                userID: self.currentUserID,
                sourceID: self.source.id,
                detailURL: URL(string: self.item.detailURL),
                vodID: self.item.idCode
            )
            self.continueWatchingHistory = transfer?.value
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: "video-detail-history-error")
            self.continueWatchingHistory = nil
        }
    }

    // MARK: - 收藏（第五节）

    func reloadFavoriteState() async {
        guard let persistence: FavoriteStatePersistenceCoordinator = self.favoritePersistence else {
            return
        }
        do {
            self.isFavorite = try await persistence.isFavorite(itemID: self.item.id, sourceID: self.source.id)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: "video-detail-favorite-error")
        }
    }

    @MainActor
    func toggleFavorite() async {
        guard let persistence: FavoriteStatePersistenceCoordinator = self.favoritePersistence else {
            return
        }
        do {
            let wasFavorite: Bool = self.isFavorite
            self.isFavorite = try await persistence.toggle(item: self.item, source: self.source, favoritedAt: self.now())
            AppAnalytics.shared.logBookmarkChanged(isFavorite: wasFavorite == false, source: self.source)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: "video-detail-favorite-error")
        }
    }

    // MARK: - 头图区取值（第五节）

    /// 中文注释：列表项的标题优先——它是用户点进来时看到的那个名字；详情规则取到的常是带 SEO 后缀的页面标题
    /// （低端影视：「危机13小时免费在线观看_高清网盘下载」，2026-10-08 模拟器），只在列表没给标题时才用。
    var displayTitle: String {
        return Self.nonEmpty(self.item.title) ?? self.detailTitle ?? self.item.title
    }

    var displayCoverURLString: String? {
        return self.detailCoverURL?.absoluteString ?? self.item.coverURL
    }

    var imageRequestConfig: RequestConfig? {
        return ResolveLibrarySourcePresentationUseCase().imageRequestConfig(for: self.source, listTab: nil)
    }

    var sourceHostText: String {
        return CatalogDisplayText.displayHost(CatalogDisplayText.addressParts(of: self.source.baseURL).host)
    }

    /// 元数据行「2024 · 日本 · 动画 · 日语」：按 key 取，有几个写几个。
    private static let headlineMetadataKeys: [String] = ["year", "releaseDate", "region", "genre", "language"]
    private static let creditMetadataKeys: [(key: String, stringKey: String)] = [
        ("director", "video_detail_credits_director"),
        ("cast", "video_detail_credits_cast"),
        ("writer", "video_detail_credits_writer"),
        ("studio", "video_detail_credits_studio")
    ]

    var headlineMetadataText: String? {
        let values: [String] = Self.headlineMetadataKeys.compactMap { key in
            self.metadataAttributes.first { $0.key == key }.flatMap { Self.nonEmpty($0.value) }
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    /// 状态徽章：列表的 `latestText` 优先，没有用 metadata 的 status。
    var statusBadgeText: String? {
        if let latestText: String = Self.nonEmpty(self.item.latestText) {
            return latestText
        }
        return self.metadataAttributes.first { $0.key == "status" }.flatMap { Self.nonEmpty($0.value) }
    }

    /// 简介下的署名行：「导演 · xxx」。
    var creditLines: [String] {
        return Self.creditMetadataKeys.compactMap { entry in
            guard let value: String = self.metadataAttributes.first(where: { $0.key == entry.key }).flatMap({ Self.nonEmpty($0.value) }) else {
                return nil
            }
            return NSLocalizedString(entry.stringKey, comment: "") + " · " + value
        }
    }

    /// 没落在元数据行、徽章、署名里的其余条目，照旧 label: value。
    var otherMetadataLines: [String] {
        let used: Set<String> = Set(Self.headlineMetadataKeys + Self.creditMetadataKeys.map(\.key) + ["status"])
        return self.metadataAttributes
            .filter { attribute in attribute.key.map { used.contains($0) == false } ?? true }
            .map(\.displayText)
    }

    var hasSynopsisSection: Bool {
        return self.synopsis != nil || self.creditLines.isEmpty == false || self.otherMetadataLines.isEmpty == false
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text: String = text?.trimmingCharacters(in: .whitespacesAndNewlines), text.isEmpty == false else {
            return nil
        }
        return text
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
