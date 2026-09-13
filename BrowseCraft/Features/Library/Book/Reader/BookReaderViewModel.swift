import Foundation
import Observation
import ReadiumNavigator
import ReadiumShared

// 中文注释：BookReaderViewModel 打开一本本地书，把 Navigator 报来的位置节流后写成续读进度，管理书签与目录。
// Readium 类型只在这里与 Representable 里出现；落库的是 Locator 的 JSON。

@MainActor
@Observable
final class BookReaderViewModel {
    enum State: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let book: LocalBook
    private(set) var state: State = .loading
    private(set) var publication: Publication?
    private(set) var initialLocator: Locator?
    private(set) var bookmarks: [BookBookmark] = []
    private(set) var tableOfContents: [Link] = []
    private(set) var currentLocator: Locator?
    /// 中文注释：视图层把 Navigator 的跳转能力挂在这里；VM 只发跳转请求。
    let navigatorProxy: BookNavigatorProxy = BookNavigatorProxy()

    private let openUseCase: OpenLocalBookUseCase
    private let saveProgressUseCase: SaveBookReadingProgressUseCase
    private let addBookmarkUseCase: AddBookBookmarkUseCase
    private let listBookmarksUseCase: ListBookBookmarksUseCase
    private let removeBookmarkUseCase: RemoveBookBookmarkUseCase
    private let userID: String
    private let throttleNanoseconds: UInt64
    private var pendingSave: Task<Void, Never>?

    init(
        book: LocalBook,
        userID: String,
        openUseCase: OpenLocalBookUseCase,
        saveProgressUseCase: SaveBookReadingProgressUseCase,
        addBookmarkUseCase: AddBookBookmarkUseCase,
        listBookmarksUseCase: ListBookBookmarksUseCase,
        removeBookmarkUseCase: RemoveBookBookmarkUseCase,
        throttleNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.book = book
        self.userID = userID
        self.openUseCase = openUseCase
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
            let opened: OpenedLocalBook = try await self.openUseCase.execute(bookID: self.book.id, userID: self.userID)
            guard let handle: ReadiumBookPublicationHandle = opened.publication as? ReadiumBookPublicationHandle else {
                self.state = .failed("unexpected-publication-handle")
                return
            }
            self.publication = handle.publication
            self.initialLocator = opened.initialLocatorJSON.flatMap(Self.locator(fromJSON:))
            self.currentLocator = self.initialLocator
            if case .success(let links) = await handle.publication.tableOfContents() {
                self.tableOfContents = links
            }
            self.loadBookmarks()
            self.state = .ready
        } catch {
            self.state = .failed(error.localizedDescription)
        }
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
                bookID: self.book.id,
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
        self.bookmarks = (try? self.listBookmarksUseCase.execute(bookID: self.book.id, userID: self.userID)) ?? []
    }

    private func persistCurrentLocation() {
        guard let locator: Locator = self.currentLocator, let json: String = Self.json(from: locator) else {
            return
        }
        try? self.saveProgressUseCase.execute(
            bookID: self.book.id,
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
