import Combine
import Foundation
import BrowseCraftCore

struct ComicDetailMetadataRow: Identifiable, Hashable {
    let label: String
    let value: String

    var id: String {
        return "\(self.label)|\(self.value)"
    }
}

struct ComicDetailRelatedLink: Identifiable, Hashable {
    let title: String
    let url: URL

    var id: String {
        return "\(self.title)|\(self.url.absoluteString)"
    }
}

enum ComicReaderDestination: Hashable {
    case chapter(ChapterLink)
    case history(ComicChapterHistory)
}

/// 中文注释：ComicDetailViewModel 持有漫画详情页状态；ReaderViewModel 只负责具体章节阅读。
@MainActor
final class ComicDetailViewModel: ObservableObject {
    @Published private(set) var metadata: SourceDetailMetadata?
    @Published private(set) var chapters: [ChapterLink] = []
    @Published private(set) var latestReadingHistory: ComicChapterHistory?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var didLoad: Bool = false
    @Published var errorMessage: String?

    let item: ContentItem
    let source: Source

    private let loadComicDetailUseCase: LoadComicDetailUseCase
    private let loadLatestComicChapterHistoryUseCase: LoadLatestComicChapterHistoryUseCase
    private let resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase
    private let userID: String

    init(
        item: ContentItem,
        source: Source,
        loadComicDetailUseCase: LoadComicDetailUseCase,
        loadLatestComicChapterHistoryUseCase: LoadLatestComicChapterHistoryUseCase,
        resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase,
        userID: String = AppUser.localDefaultID
    ) {
        self.item = item
        self.source = source
        self.loadComicDetailUseCase = loadComicDetailUseCase
        self.loadLatestComicChapterHistoryUseCase = loadLatestComicChapterHistoryUseCase
        self.resolveReaderSourcePresentationUseCase = resolveReaderSourcePresentationUseCase
        self.userID = userID

        #if DEBUG
        print(
            "[BrowseCraftNavigation] Init ComicDetailViewModel " +
            "itemId=\(item.id) title=\(item.title) " +
            "detailURL=\(item.detailURL) sourceId=\(source.id)"
        )
        #endif
    }

    var displayTitle: String {
        return self.nonEmpty(self.metadata?.title) ?? self.item.title
    }

    var coverURLString: String? {
        return self.metadata?.coverURL?.absoluteString ?? self.item.coverURL
    }

    var descriptionText: String? {
        return self.nonEmpty(self.metadata?.description)
    }

    var authorText: String? {
        return self.nonEmpty(self.metadata?.author)
    }

    var statusText: String? {
        return self.nonEmpty(self.metadata?.status)
    }

    var categoryText: String? {
        return self.nonEmpty(self.metadata?.category)
    }

    var tags: [String] {
        return self.metadata?.tags.filter { self.nonEmpty($0) != nil } ?? []
    }

    var metadataRows: [ComicDetailMetadataRow] {
        guard let metadata: SourceDetailMetadata = self.metadata else {
            return []
        }

        var rows: [ComicDetailMetadataRow] = []
        self.appendRow(label: "Author", value: metadata.author, to: &rows)
        self.appendRow(label: "Status", value: metadata.status, to: &rows)
        self.appendRow(label: "Category", value: metadata.category, to: &rows)
        self.appendRow(label: "Language", value: metadata.language, to: &rows)
        self.appendRow(label: "Published", value: metadata.publishedAt, to: &rows)
        self.appendRow(label: "Updated", value: metadata.updatedAt, to: &rows)
        self.appendRow(label: "License", value: metadata.license, to: &rows)
        self.appendRow(label: "ID", value: metadata.idCode, to: &rows)
        if let totalImages: Int = metadata.totalImages {
            rows.append(ComicDetailMetadataRow(label: "Images", value: String(totalImages)))
        }
        for attribute: SourceDetailAttribute in metadata.attributes {
            guard let value: String = self.nonEmpty(attribute.value) else {
                continue
            }
            rows.append(
                ComicDetailMetadataRow(
                    label: self.nonEmpty(attribute.label) ?? "Info",
                    value: value
                )
            )
        }
        return rows
    }

    var relatedLinks: [ComicDetailRelatedLink] {
        guard let metadata: SourceDetailMetadata = self.metadata else {
            return []
        }

        var links: [ComicDetailRelatedLink] = []
        if let photoAlbumURL: URL = metadata.photoAlbumURL {
            links.append(ComicDetailRelatedLink(title: "Photo Album", url: photoAlbumURL))
        }
        if let secondLevelPageURL: URL = metadata.secondLevelPageURL,
           secondLevelPageURL != metadata.photoAlbumURL {
            links.append(ComicDetailRelatedLink(title: "Related Page", url: secondLevelPageURL))
        }
        return links
    }

    var chapterNavigationOrder: ChapterNavigationOrder {
        let detailRule: DetailRule? = self.source.rule.primaryDetailRule
        let chapterSort: ChapterSort? = detailRule?.chapterAPI?.sort ?? detailRule?.chapterRule?.sort
        return chapterSort == .ascending ? .ascending : .descending
    }

    var startingChapter: ChapterLink? {
        switch self.chapterNavigationOrder {
        case .ascending:
            return self.chapters.first
        case .descending:
            return self.chapters.last
        }
    }

    var latestChapter: ChapterLink? {
        switch self.chapterNavigationOrder {
        case .ascending:
            return self.chapters.last
        case .descending:
            return self.chapters.first
        }
    }

    var primaryReadingTarget: ComicReaderDestination? {
        if let latestReadingHistory: ComicChapterHistory = self.latestReadingHistory {
            return .history(latestReadingHistory)
        }
        if let latestChapter: ChapterLink = self.latestChapter {
            return .chapter(latestChapter)
        }
        return nil
    }

    var detailCoverRequestConfig: RequestConfig? {
        return self.resolveReaderSourcePresentationUseCase.detailCoverRequestConfig(for: self.source)
    }

    func loadIfNeeded() async {
        guard self.didLoad == false, self.isLoading == false else {
            return
        }
        await self.load()
    }

    func reload() async {
        await self.load()
    }

    private func load() async {
        CrashDiagnostics.shared.setRuleStage(.detail)
        self.isLoading = true
        self.errorMessage = nil
        self.refreshLatestReadingHistory()
        defer {
            self.isLoading = false
        }

        do {
            let output: SourceDetailOutput = try await self.loadComicDetailUseCase.execute(
                source: self.source,
                item: self.item
            )
            self.metadata = output.metadata
            self.chapters = output.chapters.map { chapter in
                return ChapterLink(
                    title: chapter.title,
                    subtitle: chapter.subtitle,
                    url: chapter.url.absoluteString,
                    navigationChapterURLs: chapter.navigationChapterURLs.map(\.absoluteString),
                    navigationChapterTitles: chapter.navigationChapterTitles,
                    navigationOrder: chapter.navigationOrder == .ascending ? .ascending : .descending
                )
            }
            self.didLoad = true

            #if DEBUG
            print(
                "[BrowseCraftNavigation] Loaded comic detail " +
                "itemId=\(self.item.id) title=\(self.displayTitle) " +
                "chapters=\(self.chapters.count) hasMetadata=\(self.metadata != nil)"
            )
            #endif
        } catch is CancellationError {
            return
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: "comic-detail-error")
            AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .detail, errorCode: "comic-detail-error")
            CrashDiagnostics.shared.record(
                error: error,
                category: .parser,
                errorCode: "comic-detail-error",
                event: "comic-detail-error"
            )
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    /// 中文注释：详情页重新出现时可单独刷新历史，不必重复请求详情和章节列表。
    func refreshLatestReadingHistory() {
        self.latestReadingHistory = try? self.loadLatestComicChapterHistoryUseCase.execute(
            userID: self.userID,
            sourceID: self.source.id,
            comicItemID: self.item.id
        )
    }

    private func appendRow(
        label: String,
        value: String?,
        to rows: inout [ComicDetailMetadataRow]
    ) {
        guard let value: String = self.nonEmpty(value) else {
            return
        }
        rows.append(ComicDetailMetadataRow(label: label, value: value))
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value: String = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }
        return value
    }
}
