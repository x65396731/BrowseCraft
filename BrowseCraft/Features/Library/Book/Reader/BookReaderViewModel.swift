import BrowseCraftDomain
import Foundation
import Observation
import ReadiumNavigator
import ReadiumShared

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
    private let sitePublicationBuilder: ReadiumSitePublicationBuilder
    private let loadProgressUseCase: LoadBookReadingProgressUseCase
    private let saveProgressUseCase: SaveBookReadingProgressUseCase
    private let addBookmarkUseCase: AddBookBookmarkUseCase
    private let listBookmarksUseCase: ListBookBookmarksUseCase
    private let removeBookmarkUseCase: RemoveBookBookmarkUseCase
    private let userID: String
    private let throttleNanoseconds: UInt64
    private var pendingSave: Task<Void, Never>?

    /// 中文注释：站点书加载出版物后，标题用 manifest 的（详情规则清洗后的作品名，与详情页同一个），
    /// 不再用列表条目的原标题（biquhua 列表标题带分类前缀「[玄幻]普罗之主」，详情页是「普罗之主」，两处曾不一致）。
    private(set) var loadedTitle: String?

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
        sitePublicationBuilder: ReadiumSitePublicationBuilder = ReadiumSitePublicationBuilder(),
        loadProgressUseCase: LoadBookReadingProgressUseCase,
        saveProgressUseCase: SaveBookReadingProgressUseCase,
        addBookmarkUseCase: AddBookBookmarkUseCase,
        listBookmarksUseCase: ListBookBookmarksUseCase,
        removeBookmarkUseCase: RemoveBookBookmarkUseCase,
        throttleNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.subject = subject
        self.userID = userID
        self.openLocalUseCase = openLocalUseCase
        self.loadSitePublicationUseCase = loadSitePublicationUseCase
        self.sitePublicationBuilder = sitePublicationBuilder
        self.loadProgressUseCase = loadProgressUseCase
        self.saveProgressUseCase = saveProgressUseCase
        self.addBookmarkUseCase = addBookmarkUseCase
        self.listBookmarksUseCase = listBookmarksUseCase
        self.removeBookmarkUseCase = removeBookmarkUseCase
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
            }
            if let publication: Publication = self.publication, case .success(let links) = await publication.tableOfContents() {
                self.tableOfContents = links
            }
            self.loadBookmarks()
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
        guard let handle: ReadiumBookPublicationHandle = opened.publication as? ReadiumBookPublicationHandle else {
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
        if loaded.manifest.isAudiobook {
            throw BookReaderError.audiobookNotSupportedYet
        }
        let manifestTitle: String = loaded.manifest.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if manifestTitle.isEmpty == false {
            self.loadedTitle = manifestTitle
        }
        let publication: Publication = self.sitePublicationBuilder.build(manifest: loaded.manifest, contentProvider: loaded.contentProvider)
        self.publication = publication
        let saved: Locator? = try self.loadProgressUseCase.execute(bookID: self.bookID, userID: self.userID)
            .flatMap { Self.locator(fromJSON: $0.locatorJSON) }
        let chapterLocator: Locator? = selection.chapterURL
            .flatMap { chapterURL in loaded.manifest.items.first { $0.chapterURL == chapterURL } }
            .flatMap { item in AnyURL(string: item.href).map { Locator(href: $0, mediaType: .xhtml, title: item.title) } }
        // 中文注释：明确点了某一章就去那一章；没点（从「继续阅读」进来）才用续读位置。
        self.initialLocator = chapterLocator ?? saved
        self.currentLocator = self.initialLocator
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

    func addBookmarkAtCurrentLocation() {
        guard let locator: Locator = self.currentLocator, let json: String = Self.json(from: locator) else {
            return
        }
        do {
            try self.addBookmarkUseCase.execute(
                bookID: self.bookID,
                userID: self.userID,
                locatorJSON: json,
                title: locator.title,
                snippet: locator.text.highlight ?? locator.text.before
            )
            self.loadBookmarks()
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }

    func removeBookmark(_ bookmark: BookBookmark) {
        do {
            try self.removeBookmarkUseCase.execute(bookmarkID: bookmark.id, userID: self.userID)
            self.loadBookmarks()
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

    private func loadBookmarks() {
        self.bookmarks = (try? self.listBookmarksUseCase.execute(bookID: self.bookID, userID: self.userID)) ?? []
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
    case audiobookNotSupportedYet

    var errorDescription: String? {
        switch self {
        case .subjectNotSupported:
            return "This book cannot be opened here."
        case .unexpectedPublicationHandle:
            return "Unexpected publication handle."
        case .audiobookNotSupportedYet:
            return NSLocalizedString("Audiobook player is coming in a later batch.", comment: "有声书播放器待接入")
        }
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
