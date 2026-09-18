import BrowseCraftDomain
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
    private let userID: String
    private let throttleNanoseconds: UInt64
    private var pendingSave: Task<Void, Never>?

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
        self.throttleNanoseconds = throttleNanoseconds
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
                try await self.openSite(selection)
                self.recordSiteHistory()
            }
            if let publication: Publication = self.publication, case .success(let links) = await publication.tableOfContents() {
                self.tableOfContents = links
            }
            await self.loadBookmarks()
            self.state = .ready
        } catch {
            self.state = .failed(error.localizedDescription)
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

    /// 中文注释：站点书——详情 → manifest → Readium 出版物；起点优先续读位置，其次点开的章节，最后第一章。有声作品的播放器在后续批次。
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
        let publication: Publication = self.sitePublicationBuilder.build(manifest: loaded.manifest, contentProvider: loaded.contentProvider)
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
                    self?.audioPlayback = info
                    self?.remoteControls?.update(info: info)
                },
                onLocationChange: { [weak self] locator in
                    self?.navigatorDidChangeLocation(locator)
                }
            )
            navigator.delegate = bridge
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
            let controls: AudiobookRemoteControls = AudiobookRemoteControls(navigator: navigator, title: self.title, chapterCount: publication.readingOrder.count)
            controls.attach()
            self.remoteControls = controls
        }
        navigator.play()
    }

    func stopAudioPlayback() {
        self.audioNavigator?.pause()
        self.remoteControls?.detach()
        self.remoteControls = nil
        self.flush()
    }

    /// 中文注释：当前正在播的章节标题（AudioNavigator 报的资源序号对应 readingOrder）。
    var audioChapterTitle: String? {
        guard let publication: Publication = self.publication else {
            return nil
        }
        let index: Int = self.audioPlayback.resourceIndex
        guard publication.readingOrder.indices.contains(index) else {
            return nil
        }
        return publication.readingOrder[index].title
    }

    /// 中文注释：Navigator 每翻一页都会报位置；这里只记最新的，1 秒后写一次库。
    func navigatorDidChangeLocation(_ locator: Locator) {
        self.currentLocator = locator
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
            await self.loadBookmarks()
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }

    func removeBookmark(_ bookmark: BookBookmark) async {
        do {
            try await self.persistence.removeBookmark(bookmarkID: bookmark.id, userID: self.userID)
            await self.loadBookmarks()
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }

    func jump(to bookmark: BookBookmark) async {
        guard let locator: Locator = Self.locator(fromJSON: bookmark.locatorJSON) else {
            return
        }
        _ = await self.navigatorProxy.go(to: locator)
    }

    func jump(to link: Link) async {
        _ = await self.navigatorProxy.go(to: link)
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
            return "This book cannot be opened here."
        case .unexpectedPublicationHandle:
            return "Unexpected publication handle."
        }
    }
}

/// 中文注释：AudioNavigator 的代理桥：播放状态与位置变化转成闭包回给 VM（VM 是 @Observable 类，不直接做代理）。
@MainActor
final class AudioNavigatorBridge: NSObject, AudioNavigatorDelegate {
    private let onPlaybackChange: @MainActor (MediaPlaybackInfo) -> Void
    private let onLocationChange: @MainActor (Locator) -> Void

    init(onPlaybackChange: @escaping @MainActor (MediaPlaybackInfo) -> Void, onLocationChange: @escaping @MainActor (Locator) -> Void) {
        self.onPlaybackChange = onPlaybackChange
        self.onLocationChange = onLocationChange
    }

    func navigator(_ navigator: AudioNavigator, playbackDidChange info: MediaPlaybackInfo) {
        self.onPlaybackChange(info)
    }

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        self.onLocationChange(locator)
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
