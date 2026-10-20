import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftLog
import Foundation
import Observation
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared
import UIKit

// 中文注释：BookReaderViewModel 打开一本书（本地文件或站点作品），把 Navigator 报来的位置节流后写成续读进度，管理书签与目录。
// Readium 类型只在这里、Representable 与 Infrastructure 出现；落库的是 Locator 的 JSON。

@MainActor
@Observable
final class BookReaderViewModel {
    enum State: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let subject: BookReaderSubject
    private(set) var state: State = .loading
    private(set) var publication: Publication?
    private(set) var initialLocator: Locator?
    private(set) var bookmarks: [BookBookmark] = []
    private(set) var tableOfContents: [Link] = []
    private(set) var currentLocator: Locator?
    /// 中文注释：视图层把 Navigator 的跳转能力挂在这里；VM 只发跳转请求。
    let navigatorProxy: BookNavigatorProxy = BookNavigatorProxy()

    private let openLocalUseCase: OpenLocalBookUseCase?
    private let loadSitePublicationUseCase: LoadBookPublicationUseCase?
    private let sitePublicationBuilder: any SiteReadiumPublicationBuilding
    /// 中文注释：续读位置与书签的读写在专用 actor 上执行，主线程不做 SQLite I/O；进度节流落库仍同步（flush 必须立即完成）。
    private let persistence: BookReaderPersistenceCoordinator
    private let saveProgressUseCase: SaveBookReadingProgressUseCase
    private let saveHistoryUseCase: SaveBookReadingHistoryUseCase?
    /// 中文注释：广告积分（设计书 30.8）：站点书每换一章 +50、有声书实际播放每 600 秒 +50；本地书不计、测试里不注入。
    private let adPoints: ReadingActivityPersistenceCoordinator?
    private let userID: String
    private let throttleNanoseconds: UInt64
    private var pendingSave: Task<Void, Never>?
    /// 中文注释：积分满额、页面要弹激励广告；由 `BookReaderView` 的修饰器消费。
    private(set) var shouldPlayAd: Bool = false
    /// 同一阅读器实例里同一章只计一次积分；退出再进算新会话。
    private var adPointAwardedChapterKeys: Set<String> = []
    private var lastAudioTimeForAdPoints: Double?
    private var audioPlayedIntervalForAdPoints: Double = 0

    // MARK: 埋点会话
    /// 中文注释：从哪里打开的阅读器，由 `BookReaderView` 在打开前写入（`reader_opened` / 有声书 `playback_started` 的 entry）。
    var openEntry: ReaderOpenEntry = .detailStart
    private var openedAt: Date?
    /// 中文注释：本次进入过的不同章节（`reader_closed` 的章节数）；第一章在打开时记入，不报 `chapter_opened`。
    private var visitedChapterKeys: Set<String> = []
    /// 中文注释：目录 / 书签跳转发出后、新章位置到达前置为 `.toc`，其余换章算阅读中自然进入（`.auto`）。
    private var pendingChapterNavigation: ChapterNavigation?
    private var isJumpInFlight: Bool = false
    private var didReportClose: Bool = false
    private var didReportAudioPlaybackStarted: Bool = false
    private var lastAudioTimeForPlayedDuration: Double?
    /// 中文注释：有声书本次实际播放时长（暂停与大跳变不计），`playback_closed` 用。
    private var audioPlayedDuration: Double = 0

    /// 中文注释：站点书加载出版物后的标题，与详情页同一条规则 `SiteBookTitle`：列表标题与 manifest 标题一个包含另一个时取较短的
    ///（biquhua 列表「[玄幻]普罗之主」→ 取详情「普罗之主」；sfacg 详情「大傩目录列表 - 小说频道 - SF轻小说」→ 取列表「大傩」）。
    private(set) var loadedTitle: String?
    /// 中文注释：有声作品：Readium AudioNavigator 负责播放、seek、章节切换与 Locator；界面只是它的壳。
    private(set) var audioNavigator: AudioNavigator?
    private(set) var audioPlayback: MediaPlaybackInfo = MediaPlaybackInfo()
    private(set) var coverURL: URL?
    /// 中文注释：站点书的章节表，写阅读历史时把位置 href 对回章节标题与地址。
    private var siteManifest: BookPublicationManifest?
    private var audioBridge: AudioNavigatorBridge?
    private var remoteControls: AudiobookRemoteControls?
    /// 中文注释：单集取不到（`APP-MEMO-043`）：本次打开里按集序号记哪几集取不到；当前集在里面时播放页显示横条。
    /// 已失效（gone）不会被之后的暂时性失败（unavailable）盖掉。
    private(set) var audioChapterFailures: [Int: BookAudioResourceFailure.Kind] = [:]
    /// 中文注释：最后一集播完（眉行「全部听完了」）；再次开始播放时清掉。
    private(set) var didFinishAudiobook: Bool = false
    /// 中文注释：倍速，全局一个值（裁定 6）。
    private(set) var playbackSpeed: AudiobookPlaybackSpeed = AudiobookPlaybackSpeed.stored()
    /// 中文注释：播放页取到的封面图，给锁屏 Now Playing 用；控制器挂上之前取到的先存着。
    private var audioArtwork: UIImage?
    /// 中文注释：播放页刚请求的集序号。`AudioNavigator.go` 换了音频后还要等一次 seek，取不到音频的那一集 seek 不一定返回，
    /// 之后也不再回调播放状态；只看引擎报的序号，页面会停在上一集（2026-10-20 模拟器走查）。引擎报来同一集时交还给引擎。
    private var requestedAudioChapterIndex: Int?

    var isAudiobook: Bool {
        return self.audioNavigator != nil
    }

    var title: String {
        return self.loadedTitle ?? self.subject.title
    }

    var bookID: UUID {
        return self.subject.bookID
    }

    init(
        subject: BookReaderSubject,
        userID: String,
        openLocalUseCase: OpenLocalBookUseCase?,
        loadSitePublicationUseCase: LoadBookPublicationUseCase?,
        sitePublicationBuilder: any SiteReadiumPublicationBuilding,
        loadProgressUseCase: LoadBookReadingProgressUseCase,
        saveProgressUseCase: SaveBookReadingProgressUseCase,
        addBookmarkUseCase: AddBookBookmarkUseCase,
        listBookmarksUseCase: ListBookBookmarksUseCase,
        removeBookmarkUseCase: RemoveBookBookmarkUseCase,
        saveHistoryUseCase: SaveBookReadingHistoryUseCase? = nil,
        adPoints: ReadingActivityPersistenceCoordinator? = nil,
        throttleNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.subject = subject
        self.userID = userID
        self.openLocalUseCase = openLocalUseCase
        self.loadSitePublicationUseCase = loadSitePublicationUseCase
        self.sitePublicationBuilder = sitePublicationBuilder
        self.persistence = BookReaderPersistenceCoordinator(
            loadProgressUseCase: loadProgressUseCase,
            addBookmarkUseCase: addBookmarkUseCase,
            listBookmarksUseCase: listBookmarksUseCase,
            removeBookmarkUseCase: removeBookmarkUseCase
        )
        self.saveProgressUseCase = saveProgressUseCase
        self.saveHistoryUseCase = saveHistoryUseCase
        self.adPoints = adPoints
        self.throttleNanoseconds = throttleNanoseconds
    }

    /// 中文注释：打开失败后下拉重试：回到加载中再开一次（两种阅读页共用失败态）。
    func reopen() async {
        guard case .failed = self.state else {
            return
        }
        self.state = .loading
        await self.open()
    }

    func open() async {
        guard self.state == .loading else {
            return
        }
        do {
            switch self.subject {
            case .local(let book):
                try await self.openLocal(book)
            case .site(let selection):
                CrashDiagnostics.shared.setSource(selection.source)
                CrashDiagnostics.shared.setRuleStage(.reader)
                try await self.openSite(selection)
                self.recordSiteHistory()
                self.openedAt = Date()
                if let chapterKey: String = self.currentChapterKey() {
                    self.visitedChapterKeys.insert(chapterKey)
                }
                // 中文注释：有声书不报 reader_opened，开始播放时报 playback_started（见 `startAudioPlayback`）。
                if self.isAudiobook == false {
                    AppAnalytics.shared.logReaderOpened(source: selection.source, kind: .book, entry: self.openEntry)
                }
                // 中文注释：按章计分只给文字书；有声书只按实际播放计分（`accumulateAudioPlayedInterval`）。
                // 此前这里不分类型，有声书一打开就先记一次「进一章 +50」，音频还没加载、甚至取不到也会凑满弹广告（2026-10-20 用户发现）。
                if self.isAudiobook == false {
                    self.awardChapterAdPointsIfNeeded()
                }
            }
            if let publication: Publication = self.publication, case .success(let links) = await publication.tableOfContents() {
                self.tableOfContents = links
            }
            await self.loadBookmarks()
            self.state = .ready
        } catch {
            if case .site(let selection) = self.subject {
                RuleFailureDiagnostics.report(
                    error: error,
                    kind: RuleExecutionErrorClassifier.diagnosticFailureKind(for: error),
                    stage: .reader,
                    point: .bookReaderOpen,
                    source: selection.source
                )
                // 中文注释：站点书走分类器的三语短句；`RuleExecutionError.errorDescription` 是写死简体中文
                // 加 `stage=… source=… url=…` 诊断字段，只进日志不给用户看（2026-10-20 审计发布前清单第 5 项）。
                self.state = .failed(RuleExecutionErrorClassifier.userMessage(for: error))
            } else {
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    private func openLocal(_ book: LocalBook) async throws {
        guard let openLocalUseCase: OpenLocalBookUseCase = self.openLocalUseCase else {
            throw BookReaderError.subjectNotSupported
        }
        let opened: OpenedLocalBook = try await openLocalUseCase.execute(bookID: book.id, userID: self.userID)
        guard let handle: any ReadiumPublicationProviding = opened.publication as? any ReadiumPublicationProviding else {
            throw BookReaderError.unexpectedPublicationHandle
        }
        self.publication = handle.publication
        self.initialLocator = opened.initialLocatorJSON.flatMap(Self.locator(fromJSON:))
        self.currentLocator = self.initialLocator
    }

    /// 中文注释：站点书——详情 → manifest → Readium 出版物；起点优先续读位置，其次点开的章节，最后第一章；有声作品随后在 `load()` 里建 `AudioNavigator`。
    private func openSite(_ selection: SiteBookChapterSelection) async throws {
        guard let loadSitePublicationUseCase: LoadBookPublicationUseCase = self.loadSitePublicationUseCase,
              let detailURL: URL = URL(string: selection.item.detailURL) else {
            throw BookReaderError.subjectNotSupported
        }
        let loaded: LoadedBookPublication = try await loadSitePublicationUseCase.execute(source: selection.source, detailURL: detailURL)
        let resolvedTitle: String = SiteBookTitle.preferred(itemTitle: selection.item.title, detailTitle: loaded.manifest.title)
        if resolvedTitle.isEmpty == false {
            self.loadedTitle = resolvedTitle
        }
        self.coverURL = loaded.manifest.coverURL
        self.siteManifest = loaded.manifest
        let publication: Publication = self.sitePublicationBuilder.build(
            manifest: loaded.manifest,
            contentProvider: loaded.contentProvider,
            audioFailureHandler: { [weak self] failure in
                Task { @MainActor in
                    self?.audioResourceDidFail(failure)
                }
            }
        )
        self.publication = publication
        let saved: Locator? = try await self.persistence.readingProgress(bookID: self.bookID, userID: self.userID)
            .flatMap { Self.locator(fromJSON: $0.locatorJSON) }
        let chapterLocator: Locator? = selection.chapterURL
            .flatMap { chapterURL in loaded.manifest.items.first { $0.chapterURL == chapterURL } }
            .flatMap { item in AnyURL(string: item.href).map { Locator(href: $0, mediaType: Self.mediaType(for: item), title: item.title) } }
        // 中文注释：明确点了某一章就去那一章；没点（从「继续阅读」进来）才用续读位置。
        self.initialLocator = chapterLocator ?? saved
        self.currentLocator = self.initialLocator
        if loaded.manifest.isAudiobook {
            // 中文注释：有声作品不走 EPUB Navigator——播放内核用 Readium 的 AudioNavigator（AVPlayer + Locator），
            // 位置回调与文字书同一条进度 / 书签链路；播放由视图出现时触发（`startAudioPlayback`）。
            let navigator: AudioNavigator = AudioNavigator(publication: publication, initialLocation: self.initialLocator)
            let bridge: AudioNavigatorBridge = AudioNavigatorBridge(
                onPlaybackChange: { [weak self] info in
                    self?.audioPlaybackDidChange(info)
                },
                onLocationChange: { [weak self] locator in
                    self?.navigatorDidChangeLocation(locator)
                },
                onResourceFinished: { [weak self] info in
                    self?.audioResourceDidFinish(info)
                }
            )
            navigator.delegate = bridge
            navigator.submitPreferences(AudioPreferences(speed: self.playbackSpeed.rawValue))
            self.audioBridge = bridge
            self.audioNavigator = navigator
            self.navigatorProxy.navigator = navigator
        }
    }

    private static func mediaType(for item: BookPublicationItem) -> MediaType {
        switch item.kind {
        case .text:
            return .xhtml
        case .audio(let mediaType, _):
            return mediaType.flatMap { MediaType($0) } ?? .mp3
        }
    }

    // MARK: - 有声播放

    /// 中文注释：播放页出现时开始播放并挂锁屏 / 耳机控制；离开时暂停、卸下控制并落一次进度。
    func startAudioPlayback() {
        guard let navigator: AudioNavigator = self.audioNavigator, let publication: Publication = self.publication else {
            return
        }
        if self.remoteControls == nil {
            self.attachRemoteControls(navigator: navigator, publication: publication)
        }
        navigator.play()
        if self.didReportAudioPlaybackStarted == false, case .site(let selection) = self.subject {
            self.didReportAudioPlaybackStarted = true
            AppAnalytics.shared.logPlaybackStarted(
                source: selection.source,
                kind: .audiobook,
                playerType: .audio,
                entry: Self.playbackEntry(for: self.openEntry)
            )
        }
    }

    /// 中文注释：有声书沿用阅读器的入口参数，映射到播放入口：从目录 / 开始收听算选集。
    private static func playbackEntry(for entry: ReaderOpenEntry) -> PlaybackEntry {
        switch entry {
        case .detailStart, .chapterList:
            return .episode
        case .detailContinue:
            return .continue
        case .history:
            return .history
        case .continueTile:
            return .continueTile
        }
    }

    /// 中文注释：离开阅读器时报一次：文字书 `reader_closed`，有声书 `playback_closed`（时长为实际播放时长）。
    /// 激励广告盖在上面时视图也会消失，那不算离开。
    func reportClosedIfNeeded() {
        guard self.didReportClose == false,
              self.shouldPlayAd == false,
              case .site = self.subject,
              let openedAt: Date = self.openedAt else {
            return
        }
        self.didReportClose = true
        if self.isAudiobook {
            AppAnalytics.shared.logPlaybackClosed(kind: .audiobook, playerType: .audio, duration: self.audioPlayedDuration)
        } else {
            AppAnalytics.shared.logReaderClosed(
                kind: .book,
                duration: Date().timeIntervalSince(openedAt),
                chapterCount: self.visitedChapterKeys.count
            )
        }
    }

    private func attachRemoteControls(navigator: AudioNavigator, publication: Publication) {
        let controls: AudiobookRemoteControls = AudiobookRemoteControls(
            navigator: navigator,
            title: self.title,
            chapterCount: publication.readingOrder.count,
            artwork: self.audioArtwork
        )
        controls.attach()
        self.remoteControls = controls
    }

    func stopAudioPlayback() {
        self.audioNavigator?.pause()
        self.remoteControls?.detach()
        self.remoteControls = nil
        self.flush()
    }

    /// 中文注释：当前集的序号（从 0 起，AudioNavigator 报的资源序号）与总集数，播放页眉行「第 N / M 集」用。
    var audioChapterIndex: Int {
        return self.requestedAudioChapterIndex ?? self.audioPlayback.resourceIndex
    }

    var audioChapterCount: Int {
        return self.publication?.readingOrder.count ?? 0
    }

    /// 中文注释：播放页显示用的播放信息：引擎还没报到刚请求的那一集时，按「那一集、加载中、时长未知」显示，
    /// 不把上一集的进度与时长挂在新一集的名下。
    var displayedAudioPlayback: MediaPlaybackInfo {
        guard let requested: Int = self.requestedAudioChapterIndex, requested != self.audioPlayback.resourceIndex else {
            return self.audioPlayback
        }
        return MediaPlaybackInfo(resourceIndex: requested, state: .loading, time: 0, duration: nil)
    }

    /// 中文注释：当前集取不到时是哪一类；nil 表示没有失败。
    var currentAudioChapterFailure: BookAudioResourceFailure.Kind? {
        return self.audioChapterFailures[self.audioChapterIndex]
    }

    /// 中文注释：目录 sheet 的集名（readingOrder 的标题，可能缺）。
    var audioChapterTitles: [String?] {
        return self.publication?.readingOrder.map(\.title) ?? []
    }

    /// 中文注释：打开前就判断「整站有声」（reader 规则全是 audio，与库页、详情页同一判据），打开中的骨架按播放页的样子画。
    var expectsAudiobook: Bool {
        guard case .site(let selection) = self.subject, case .book(let configuration) = selection.source.configuration else {
            return false
        }
        let readers: [BookReaderRule] = configuration.rule.ruleSets.readerRules
        return readers.isEmpty == false && readers.allSatisfy { reader in reader.contentType == .audio }
    }

    var canGoToPreviousAudioChapter: Bool {
        return self.audioChapterIndex > 0
    }

    var canGoToNextAudioChapter: Bool {
        return self.audioChapterIndex + 1 < self.audioChapterCount
    }

    /// 中文注释：当前正在播的章节标题（AudioNavigator 报的资源序号对应 readingOrder）。
    var audioChapterTitle: String? {
        guard let publication: Publication = self.publication else {
            return nil
        }
        let index: Int = self.audioChapterIndex
        guard publication.readingOrder.indices.contains(index) else {
            return nil
        }
        return publication.readingOrder[index].title
    }

    /// 中文注释：Navigator 每翻一页都会报位置；这里只记最新的，1 秒后写一次库。
    func navigatorDidChangeLocation(_ locator: Locator) {
        self.currentLocator = locator
        if self.isAudiobook == false {
            self.trackChapterVisit()
            self.awardChapterAdPointsIfNeeded()
        }
        guard self.pendingSave == nil else {
            return
        }
        self.pendingSave = Task { [weak self] in
            guard let self: BookReaderViewModel = self else {
                return
            }
            try? await Task.sleep(nanoseconds: self.throttleNanoseconds)
            self.pendingSave = nil
            self.persistCurrentLocation()
        }
    }

    /// 中文注释：离开阅读器时立即落一次，不等节流。
    func flush() {
        self.pendingSave?.cancel()
        self.pendingSave = nil
        self.persistCurrentLocation()
    }

    func addBookmarkAtCurrentLocation() async {
        guard let locator: Locator = self.currentLocator, let json: String = Self.json(from: locator) else {
            return
        }
        do {
            try await self.persistence.addBookmark(
                bookID: self.bookID,
                userID: self.userID,
                locatorJSON: json,
                title: locator.title,
                snippet: locator.text.highlight ?? locator.text.before
            )
            AppAnalytics.shared.logReaderBookmarkChanged(isAdded: true, kind: self.analyticsKind)
            await self.loadBookmarks()
        } catch {
            // 中文注释：书签增删失败只记日志，不把整个阅读器换成失败页——正文还在，用户仍可继续读。
            AppLog.error(.reader, "book-bookmark-add-failed", ["error": .error(error)])
        }
    }

    func removeBookmark(_ bookmark: BookBookmark) async {
        do {
            try await self.persistence.removeBookmark(bookmarkID: bookmark.id, userID: self.userID)
            AppAnalytics.shared.logReaderBookmarkChanged(isAdded: false, kind: self.analyticsKind)
            await self.loadBookmarks()
        } catch {
            AppLog.error(.reader, "book-bookmark-remove-failed", ["error": .error(error)])
        }
    }

    func jump(to bookmark: BookBookmark) async {
        guard let locator: Locator = Self.locator(fromJSON: bookmark.locatorJSON) else {
            return
        }
        self.beginJump()
        _ = await self.navigatorProxy.go(to: locator)
        self.isJumpInFlight = false
    }

    func jump(to link: Link) async {
        self.beginJump()
        _ = await self.navigatorProxy.go(to: link)
        self.isJumpInFlight = false
    }

    private func beginJump() {
        self.pendingChapterNavigation = .toc
        self.isJumpInFlight = true
    }

    private var analyticsKind: AnalyticsContentKind {
        return self.isAudiobook ? .audiobook : .book
    }

    private func currentChapterKey() -> String? {
        guard let locator: Locator = self.currentLocator else {
            return nil
        }
        return self.siteChapter(forHref: locator.href.string)?.chapterURL.absoluteString ?? locator.href.string
    }

    /// 中文注释：站点文字书每进入一个本次没进过的章节报一次 `chapter_opened`；打开时那一章由 `reader_opened` 代表。
    private func trackChapterVisit() {
        guard case .site(let selection) = self.subject,
              self.openedAt != nil,
              let chapterKey: String = self.currentChapterKey() else {
            return
        }
        // 中文注释：打开时还没有位置（无续读、未点章节）的话，第一次报来的位置就是首章，同样不报。
        if self.visitedChapterKeys.isEmpty {
            self.visitedChapterKeys.insert(chapterKey)
            return
        }
        guard self.visitedChapterKeys.insert(chapterKey).inserted else {
            // 中文注释：跳转已落地但仍在本章（或旧章），不把 `.toc` 留给之后的自然换章。
            if self.isJumpInFlight == false {
                self.pendingChapterNavigation = nil
            }
            return
        }
        AppAnalytics.shared.logChapterOpened(
            source: selection.source,
            kind: .book,
            navigation: self.pendingChapterNavigation ?? .auto
        )
        self.pendingChapterNavigation = nil
    }

    private func loadBookmarks() async {
        self.bookmarks = (try? await self.persistence.bookmarks(bookID: self.bookID, userID: self.userID)) ?? []
    }

    private func persistCurrentLocation() {
        guard let locator: Locator = self.currentLocator, let json: String = Self.json(from: locator) else {
            return
        }
        try? self.saveProgressUseCase.execute(
            bookID: self.bookID,
            userID: self.userID,
            locatorJSON: json,
            totalProgression: locator.locations.totalProgression
        )
        self.recordSiteHistory()
    }

    /// 中文注释：站点书写一条阅读历史（一本书一条，upsert），章节取当前位置所在的那一章；本地书不进历史。
    /// 打开时写一次、之后随进度落库一起更新，所以历史里的章节与访问时间跟着最近一次阅读走。
    private func recordSiteHistory() {
        guard case .site(let selection) = self.subject,
              let saveHistoryUseCase: SaveBookReadingHistoryUseCase = self.saveHistoryUseCase else {
            return
        }
        let chapter: BookPublicationItem? = self.currentLocator.map { self.siteChapter(forHref: $0.href.string) }
            ?? self.siteManifest?.items.first
        try? saveHistoryUseCase.execute(
            history: BookReadingHistory(
                userID: self.userID,
                sourceID: selection.source.id,
                detailURL: selection.item.detailURL,
                bookItemID: selection.item.id,
                bookTitle: self.title,
                coverURL: self.coverURL ?? selection.item.coverURL.flatMap(URL.init(string:)),
                chapterTitle: chapter?.title ?? self.currentLocator?.title ?? selection.chapterTitle,
                chapterURL: chapter?.chapterURL ?? selection.chapterURL,
                visitedAt: Date(),
                sourceSnapshot: SourceSnapshot(source: selection.source)
            )
        )
    }

    /// 中文注释：与详情页找续读章节同一条对法：出版物内相对 href（Navigator 可能补前导斜杠），有声章节的 href 就是远程地址。
    private func siteChapter(forHref href: String) -> BookPublicationItem? {
        return self.siteManifest?.items.first { item in
            return item.href == href || "/" + item.href == href || item.chapterURL.absoluteString == href
        }
    }

    // MARK: - 广告积分（设计书 30.8）

    /// 中文注释：站点文字书按「当前位置所在章」计分，同一章只计一次；不挂在每次翻页的落库上。本地书不计。
    private func awardChapterAdPointsIfNeeded() {
        guard case .site = self.subject,
              let adPoints: ReadingActivityPersistenceCoordinator = self.adPoints,
              let locator: Locator = self.currentLocator else {
            return
        }
        let chapterKey: String = self.siteChapter(forHref: locator.href.string)?.chapterURL.absoluteString ?? locator.href.string
        guard self.adPointAwardedChapterKeys.insert(chapterKey).inserted else {
            return
        }
        self.accumulateAdPoints(AdPointRule.bookChapterPoints, trigger: .book, using: adPoints)
    }

    /// 中文注释：AudioNavigator 报来的播放状态：更新界面与锁屏控制，并累计广告积分。
    func audioPlaybackDidChange(_ info: MediaPlaybackInfo) {
        self.audioPlayback = info
        if self.requestedAudioChapterIndex == info.resourceIndex {
            self.requestedAudioChapterIndex = nil
        }
        if info.state == .playing {
            // 中文注释：真的在播，说明这一集取得到，也不再是「全部听完了」。
            self.didFinishAudiobook = false
            self.audioChapterFailures[info.resourceIndex] = nil
        }
        self.remoteControls?.update(info: info)
        self.accumulateAudioPlayedDuration(info)
        self.accumulateAudioPlayedInterval(info)
    }

    /// 中文注释：AudioNavigator 播完一个章节要接下一章时回调；播完的是最后一章即整本播完。
    func audioResourceDidFinish(_ info: MediaPlaybackInfo) {
        guard let publication: Publication = self.publication,
              info.resourceIndex >= publication.readingOrder.count - 1 else {
            return
        }
        self.didFinishAudiobook = true
        AppAnalytics.shared.logPlaybackCompleted(kind: .audiobook, playerType: .audio)
    }

    /// 中文注释：音频客户端报来的单集失败（`APP-MEMO-043`）：按地址对回集序号记下。不自动跳下一集（裁定 9），由播放页的横条让用户决定。
    func audioResourceDidFail(_ failure: BookAudioResourceFailure) {
        guard let index: Int = self.audioChapterIndex(for: failure.chapterURL) else {
            return
        }
        if self.audioChapterFailures[index] == .gone {
            return
        }
        self.audioChapterFailures[index] = failure.kind
        if index == self.audioChapterIndex {
            self.audioNavigator?.pause()
        }
    }

    /// 中文注释：出版物里登记的地址可能是 http（请求时才升 https），两种写法都认。
    private func audioChapterIndex(for chapterURL: URL) -> Int? {
        guard let items: [BookPublicationItem] = self.siteManifest?.items else {
            return nil
        }
        let target: String = Self.schemeless(chapterURL.absoluteString)
        return items.firstIndex { item in
            return item.chapterURL == chapterURL
                || Self.schemeless(item.chapterURL.absoluteString) == target
                || Self.schemeless(item.href) == target
        }
    }

    private static func schemeless(_ address: String) -> String {
        guard let range: Range<String.Index> = address.range(of: "://") else {
            return address
        }
        return String(address[range.upperBound...])
    }

    /// 中文注释：横条上的「重试」：清掉这一集的失败记录，从这一集开头重新取。
    /// Readium 的媒体加载器按集缓存资源、HTTP 资源又缓存第一次的请求结果（连失败一起），同一个 AudioNavigator 里切回这一集
    /// 不会再发请求（2026-10-20 模拟器走查）；所以重试时为这一集新建一个 AudioNavigator，接上同一个代理桥、倍速与锁屏控制。
    func retryCurrentAudioChapter() async {
        let index: Int = self.audioChapterIndex
        guard let previous: AudioNavigator = self.audioNavigator,
              let publication: Publication = self.publication,
              let bridge: AudioNavigatorBridge = self.audioBridge,
              publication.readingOrder.indices.contains(index) else {
            return
        }
        self.audioChapterFailures[index] = nil
        previous.pause()
        let locator: Locator? = await publication.locate(publication.readingOrder[index])
        let navigator: AudioNavigator = AudioNavigator(publication: publication, initialLocation: locator)
        navigator.delegate = bridge
        navigator.submitPreferences(AudioPreferences(speed: self.playbackSpeed.rawValue))
        self.audioNavigator = navigator
        self.navigatorProxy.navigator = navigator
        self.requestedAudioChapterIndex = index
        if let controls: AudiobookRemoteControls = self.remoteControls {
            controls.detach()
            self.attachRemoteControls(navigator: navigator, publication: publication)
        }
        navigator.play()
    }

    /// 中文注释：横条上的「下一集」与主控件的下一集同一个动作。
    func playNextAudioChapter() async {
        guard self.canGoToNextAudioChapter else {
            return
        }
        await self.playAudioChapter(at: self.audioChapterIndex + 1)
    }

    func playPreviousAudioChapter() async {
        guard self.canGoToPreviousAudioChapter else {
            return
        }
        await self.playAudioChapter(at: self.audioChapterIndex - 1)
    }

    /// 中文注释：从某一集开头播（目录 sheet 点一集、上下集、重试）。先记下请求的集序号再交给引擎，页面立刻跟上。
    func playAudioChapter(at index: Int) async {
        guard let navigator: AudioNavigator = self.audioNavigator,
              let publication: Publication = self.publication,
              publication.readingOrder.indices.contains(index) else {
            return
        }
        self.requestedAudioChapterIndex = index
        self.didFinishAudiobook = false
        _ = await navigator.go(to: publication.readingOrder[index])
        navigator.play()
    }

    /// 中文注释：选倍速：记到全局，立即交给引擎（暂停中也生效，下次播放按它的速度）。
    func setPlaybackSpeed(_ speed: AudiobookPlaybackSpeed) {
        self.playbackSpeed = speed
        speed.store()
        self.audioNavigator?.submitPreferences(AudioPreferences(speed: speed.rawValue))
        self.remoteControls?.update(info: self.audioPlayback)
    }

    /// 中文注释：播放页取到封面后交给锁屏 Now Playing。
    func setAudioArtwork(_ image: UIImage) {
        self.audioArtwork = image
        self.remoteControls?.setArtwork(image)
    }

    /// 中文注释：与广告积分同一种累计法（只计播放中的小步进），但不依赖积分是否注入。
    private func accumulateAudioPlayedDuration(_ info: MediaPlaybackInfo) {
        defer {
            self.lastAudioTimeForPlayedDuration = info.time
        }
        guard info.state == .playing,
              let lastTime: Double = self.lastAudioTimeForPlayedDuration else {
            return
        }
        let step: Double = info.time - lastTime
        guard step > 0, step <= AdPointRule.maxPlaybackProgressStep else {
            return
        }
        self.audioPlayedDuration += step
    }

    /// 中文注释：有声书只计实际播放：按 AudioNavigator 上报的时间差累计，暂停不动；换章 / 拖动的大跳变不计。
    private func accumulateAudioPlayedInterval(_ info: MediaPlaybackInfo) {
        guard let adPoints: ReadingActivityPersistenceCoordinator = self.adPoints else {
            return
        }
        defer {
            self.lastAudioTimeForAdPoints = info.time
        }
        guard info.state == .playing,
              let lastTime: Double = self.lastAudioTimeForAdPoints else {
            return
        }
        let step: Double = info.time - lastTime
        guard step > 0, step <= AdPointRule.maxPlaybackProgressStep else {
            return
        }
        self.audioPlayedIntervalForAdPoints += step
        guard self.audioPlayedIntervalForAdPoints >= AdPointRule.audiobookPlaybackInterval else {
            return
        }
        self.audioPlayedIntervalForAdPoints -= AdPointRule.audiobookPlaybackInterval
        self.accumulateAdPoints(AdPointRule.audiobookPoints, trigger: .audiobook, using: adPoints)
    }

    private func accumulateAdPoints(
        _ points: Int,
        trigger: RewardedAdPlaybackTrigger,
        using adPoints: ReadingActivityPersistenceCoordinator
    ) {
        Task {
            do {
                let result: AdPointAccumulationResult = try await adPoints.accumulateAdPoints(points)
                guard result.shouldPlayAd else {
                    return
                }
                AppAnalytics.shared.logAdPointsThreshold(trigger: trigger)
                // 中文注释：有声书积分只在播放中累计，触发时一定在播；广告结束后 `markAdPlaybackHandled` 继续播。
                self.audioNavigator?.pause()
                self.shouldPlayAd = true
            } catch {
                AppLog.error(.sync, "book-ad-points-save-failed", ["error": .error(error)])
            }
        }
    }

    /// 中文注释：广告播过（看完 / 提前关闭）才清零积分；没播出来积分保留、下个计分点再试（30.8）。有声书恢复播放。
    func markAdPlaybackHandled(outcome: RewardedAdPlaybackOutcome) {
        self.shouldPlayAd = false
        self.audioNavigator?.play()
        guard outcome.consumesAdPoints, let adPoints: ReadingActivityPersistenceCoordinator = self.adPoints else {
            return
        }
        Task {
            do {
                try await adPoints.consumeAdPoints()
            } catch {
                AppLog.error(.sync, "book-ad-points-consume-failed", ["error": .error(error)])
            }
        }
    }

    static func locator(fromJSON json: String) -> Locator? {
        guard let value: JSONValue = try? JSONValue(jsonString: json) else {
            return nil
        }
        return try? Locator(json: value, warnings: nil)
    }

    static func json(from locator: Locator) -> String? {
        return try? locator.jsonString()
    }
}

enum BookReaderError: LocalizedError, Equatable {
    case subjectNotSupported
    case unexpectedPublicationHandle

    var errorDescription: String? {
        switch self {
        case .subjectNotSupported:
            return NSLocalizedString("book_reader_error_subject_not_supported", comment: "这本书打不开")
        case .unexpectedPublicationHandle:
            return NSLocalizedString("book_reader_error_unexpected_handle", comment: "出版物句柄异常")
        }
    }
}

/// 中文注释：AudioNavigator 的代理桥：播放状态与位置变化转成闭包回给 VM（VM 是 @Observable 类，不直接做代理）。
@MainActor
final class AudioNavigatorBridge: NSObject, AudioNavigatorDelegate {
    private let onPlaybackChange: @MainActor (MediaPlaybackInfo) -> Void
    private let onLocationChange: @MainActor (Locator) -> Void
    private let onResourceFinished: @MainActor (MediaPlaybackInfo) -> Void

    init(
        onPlaybackChange: @escaping @MainActor (MediaPlaybackInfo) -> Void,
        onLocationChange: @escaping @MainActor (Locator) -> Void,
        onResourceFinished: @escaping @MainActor (MediaPlaybackInfo) -> Void = { _ in }
    ) {
        self.onPlaybackChange = onPlaybackChange
        self.onLocationChange = onLocationChange
        self.onResourceFinished = onResourceFinished
    }

    func navigator(_ navigator: AudioNavigator, playbackDidChange info: MediaPlaybackInfo) {
        self.onPlaybackChange(info)
    }

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        self.onLocationChange(locator)
    }

    func navigator(_ navigator: AudioNavigator, shouldPlayNextResource info: MediaPlaybackInfo) -> Bool {
        self.onResourceFinished(info)
        return true
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {}

    func navigator(_ navigator: Navigator, presentExternalURL url: URL) {
        UIApplication.shared.open(url)
    }
}

/// 中文注释：Navigator 的弱引用代理；Representable 建好 Navigator 后挂上来，VM 通过它跳转。
@MainActor
final class BookNavigatorProxy {
    weak var navigator: (any Navigator)?

    func go(to locator: Locator) async -> Bool {
        guard let navigator: any Navigator = self.navigator else {
            return false
        }
        return await navigator.go(to: locator, options: NavigatorGoOptions(animated: true))
    }

    func go(to link: Link) async -> Bool {
        guard let navigator: any Navigator = self.navigator else {
            return false
        }
        return await navigator.go(to: link, options: NavigatorGoOptions(animated: true))
    }
}
