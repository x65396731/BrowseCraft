import BrowseCraftDomain
import Foundation
import Observation

// 中文注释：BookSiteDetailViewModel 是规则来源里一部作品的详情页：标题 / 作者 / 封面 + 章节列表（来自 Runtime 的详情输出），
// 以及「继续阅读」用的续读位置。有声作品先只列章节，不可点（播放器在后续批次）。

@MainActor
@Observable
final class BookSiteDetailViewModel {
    let item: ContentItem
    let source: Source
    private(set) var manifest: BookPublicationManifest?
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var lastReadChapterURL: URL?

    private let loadPublicationUseCase: LoadBookPublicationUseCase
    private let loadProgressUseCase: LoadBookReadingProgressUseCase
    private let userID: String

    init(
        item: ContentItem,
        source: Source,
        loadPublicationUseCase: LoadBookPublicationUseCase,
        loadProgressUseCase: LoadBookReadingProgressUseCase,
        userID: String
    ) {
        self.item = item
        self.source = source
        self.loadPublicationUseCase = loadPublicationUseCase
        self.loadProgressUseCase = loadProgressUseCase
        self.userID = userID
    }

    var bookID: UUID {
        return SiteBookIdentity.bookID(sourceID: self.source.id, detailURL: self.item.detailURL)
    }

    var chapters: [BookPublicationItem] {
        return self.manifest?.items ?? []
    }

    var isAudiobook: Bool {
        return self.manifest?.isAudiobook ?? false
    }

    func loadIfNeeded() async {
        guard self.isLoading == false else {
            return
        }
        if let manifest: BookPublicationManifest = self.manifest {
            // 中文注释：从阅读器 / 播放页退回来时 manifest 还在，但续读位置已经变了——只重读进度，不重取详情
            //（2026-09-14 loyalbooks 模拟器复验：播到第 03–04 章退回详情页仍显示「Start Listening」）。
            self.lastReadChapterURL = self.resolveLastReadChapter(in: manifest)
            return
        }
        await self.load()
    }

    func load() async {
        guard let detailURL: URL = URL(string: self.item.detailURL) else {
            self.errorMessage = "Invalid detail URL."
            return
        }
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        do {
            let loaded: LoadedBookPublication = try await self.loadPublicationUseCase.execute(source: self.source, detailURL: detailURL)
            self.manifest = loaded.manifest
            self.lastReadChapterURL = self.resolveLastReadChapter(in: loaded.manifest)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// 中文注释：起点章节：有续读位置就从那一章继续，否则第一章。
    var primaryChapter: BookPublicationItem? {
        if let url: URL = self.lastReadChapterURL, let item: BookPublicationItem = self.chapters.first(where: { $0.chapterURL == url }) {
            return item
        }
        return self.chapters.first
    }

    var hasReadingProgress: Bool {
        return self.lastReadChapterURL != nil
    }

    func selection(for chapter: BookPublicationItem?) -> SiteBookChapterSelection {
        return SiteBookChapterSelection(
            source: self.source,
            item: self.item,
            chapterURL: chapter?.chapterURL,
            chapterTitle: chapter?.title
        )
    }

    private func resolveLastReadChapter(in manifest: BookPublicationManifest) -> URL? {
        guard let progress: BookReadingProgress = try? self.loadProgressUseCase.execute(bookID: self.bookID, userID: self.userID),
              let href: String = Self.href(fromLocatorJSON: progress.locatorJSON) else {
            return nil
        }
        return manifest.items.first { $0.href == href || "/" + $0.href == href }?.chapterURL
    }

    private static func href(fromLocatorJSON json: String) -> String? {
        guard let object: [String: Any] = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else {
            return nil
        }
        return object["href"] as? String
    }
}
