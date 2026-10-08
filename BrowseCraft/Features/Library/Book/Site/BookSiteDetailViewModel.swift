import BrowseCraftCore
import BrowseCraftDomain
import Foundation
import Observation

// 中文注释：BookSiteDetailViewModel 是规则来源里一部作品的详情页（`docs/design/Book-Detail-Page-Redesign-Design.md`）：
// 头部（manifest 的标题 / 作者 / 封面 / 简介）、继续卡片（读书历史的章节与时刻、进度表的全书进度）、
// 编号柱行列表的目录（解析、显示顺序、分段、上次读到），以及收藏与登录入口。文字书与有声书同一套，有声只换措辞。

/// 目录里的一行：章节 + 解析出的编号与话名 + 显示顺序里的序号。
struct BookChapterEntry: Identifiable, Hashable {
    let item: BookPublicationItem
    let numberLabel: String?
    let name: String
    let ordinal: Int

    var id: String {
        return self.item.chapterURL.absoluteString
    }

    /// 行标题：解出编号写话名，话名为空写「第 N 章」；解不出写原标题。
    var rowTitle: String {
        guard let numberLabel: String = self.numberLabel else {
            return self.item.title
        }
        if self.name.isEmpty {
            return String(format: NSLocalizedString("book_detail_chapter_number", comment: ""), numberLabel)
        }
        return self.name
    }
}

@MainActor
@Observable
final class BookSiteDetailViewModel {
    let item: ContentItem
    let source: Source

    /// 中文注释：作品页封面与书架封面同一份请求配置（来源 `sharedRequest` 的 Cookie 策略等），见
    /// `ResolveLibrarySourcePresentationUseCase.bookImageRequestConfig`（2026-10-07 半夏小說封面）。
    var coverRequestConfig: RequestConfig? {
        guard case .book(let configuration) = self.source.configuration else {
            return nil
        }
        return ResolveLibrarySourcePresentationUseCase.bookImageRequestConfig(for: configuration.rule, listTab: nil)
    }
    private(set) var manifest: BookPublicationManifest?
    private(set) var isLoading: Bool = false
    private(set) var didLoad: Bool = false
    private(set) var errorMessage: String?
    private(set) var lastReadChapterURL: URL?
    /// 中文注释：读书历史（一书一条）——续读章的稳定键，继续卡片的章名与时刻从这来（第五、八节）。
    private(set) var readingHistory: BookReadingHistory?
    /// 中文注释：进度表那一条：全书进度 `totalProgression`，Locator 里的章内 `progression` 与有声 `t=`。
    private(set) var readingProgress: BookReadingProgress?
    private(set) var isFavorite: Bool = false
    private(set) var requestedSourceLogin: LibrarySourceLoginState?

    /// 目录派生状态：章节变化或翻转顺序时算一次（第六节）。
    private(set) var displayEntries: [BookChapterEntry] = []
    private(set) var segments: [ComicChapterSegment] = []
    private var isDisplayOrderFlipped: Bool = false
    private var selectedSegmentID: String?
    private(set) var pendingScrollChapterURL: String?
    private var isProgrammaticScrolling: Bool = false

    private let loadPublicationUseCase: LoadBookPublicationUseCase
    private let loadProgressUseCase: LoadBookReadingProgressUseCase
    private let userID: String
    private let readingHistoryRepository: (any BookReadingHistoryRepository)?
    private let toggleFavoriteUseCase: ToggleFavoriteUseCase?
    private let sourceCredentialStore: (any SourceCredentialStoring)?
    private let presentationUseCase: ResolveLibrarySourcePresentationUseCase
    private let now: () -> Date

    init(
        item: ContentItem,
        source: Source,
        loadPublicationUseCase: LoadBookPublicationUseCase,
        loadProgressUseCase: LoadBookReadingProgressUseCase,
        userID: String,
        readingHistoryRepository: (any BookReadingHistoryRepository)? = nil,
        toggleFavoriteUseCase: ToggleFavoriteUseCase? = nil,
        sourceCredentialStore: (any SourceCredentialStoring)? = nil,
        presentationUseCase: ResolveLibrarySourcePresentationUseCase = ResolveLibrarySourcePresentationUseCase(),
        now: @escaping () -> Date = Date.init
    ) {
        self.item = item
        self.source = source
        self.loadPublicationUseCase = loadPublicationUseCase
        self.loadProgressUseCase = loadProgressUseCase
        self.userID = userID
        self.readingHistoryRepository = readingHistoryRepository
        self.toggleFavoriteUseCase = toggleFavoriteUseCase
        self.sourceCredentialStore = sourceCredentialStore
        self.presentationUseCase = presentationUseCase
        self.now = now
    }

    var bookID: UUID {
        return SiteBookIdentity.bookID(sourceID: self.source.id, detailURL: self.item.detailURL)
    }

    var chapters: [BookPublicationItem] {
        return self.manifest?.items ?? []
    }

    // MARK: - 头部（第五节）

    /// 中文注释：导航栏与头部标题，规则见 `SiteBookTitle`（与阅读器同一个）。
    var displayTitle: String {
        return SiteBookTitle.preferred(itemTitle: self.item.title, detailTitle: self.manifest?.title)
    }

    var coverURLString: String? {
        return self.manifest?.coverURL?.absoluteString ?? self.item.coverURL
    }

    var authorText: String? {
        return Self.nonEmpty(self.manifest?.author)
    }

    var descriptionText: String? {
        return Self.nonEmpty(self.manifest?.description)
    }

    /// 「来源 · 分类」：分类是列表项所属的列表页标题（规则有两个以上列表页时才有意义）。
    var sourceLine: String {
        let tabs: [ListTabRule] = self.presentationUseCase.listTabs(for: self.source)
        let tabID: String? = self.item.listContext?.tabId ?? self.item.listContext?.pageId
        if tabs.count > 1, let tabID: String = tabID, let tab: ListTabRule = tabs.first(where: { $0.id == tabID }) {
            return "\(self.source.name) · \(tab.title)"
        }
        return self.source.name
    }

    /// 是不是有声书：章节装配完按 manifest；取回来之前先按整站有声（reader 规则全 audio）。
    var isAudiobook: Bool {
        if let manifest: BookPublicationManifest = self.manifest {
            return manifest.isAudiobook
        }
        return self.presentationUseCase.isAudiobookSource(for: self.source)
    }

    /// 「1,297 章」/ 有声「有声书 · 17 章」；章节取回来之前为 nil（画骨架条）。
    var chapterCountText: String? {
        guard self.didLoad else {
            return nil
        }
        let count: String = Self.integerFormatter.string(from: NSNumber(value: self.chapters.count)) ?? String(self.chapters.count)
        let key: String = self.isAudiobook ? "book_detail_audiobook_chapter_count" : "book_detail_chapter_count"
        return String(format: NSLocalizedString(key, comment: ""), count)
    }

    var chapterCountNumberText: String {
        return Self.integerFormatter.string(from: NSNumber(value: self.chapters.count)) ?? String(self.chapters.count)
    }

    // MARK: - 继续卡片 / 开始按钮（第五节）

    /// 上次读到的章节：先按读书历史的 `chapterURL`（稳定键），没有再退回 Locator `href` 的下标对法。
    var currentEntry: BookChapterEntry? {
        guard let url: URL = self.lastReadChapterURL else {
            return nil
        }
        return self.displayEntries.first { $0.item.chapterURL == url }
    }

    /// 有续读位置就出继续卡片，否则出开始按钮。
    var hasContinueCard: Bool {
        return self.didLoad && self.currentEntry != nil
    }

    var continueLabel: String {
        return NSLocalizedString(self.isAudiobook ? "book_detail_continue_listening" : "book_detail_continue_reading", comment: "")
    }

    /// 继续卡片的章名：读书历史的章节名，没有用目录里那一章的标题。
    var continueChapterTitle: String? {
        if let title: String = Self.nonEmpty(self.readingHistory?.chapterTitle) {
            return title
        }
        return self.currentEntry?.item.title
    }

    /// 第三行：文字书「全书 12% · 昨天 21:40」、有声书「12:34 · 昨天 21:40」；没有进度只写时刻。
    var continueMetaText: String? {
        var parts: [String] = []
        if self.isAudiobook {
            if let seconds: Double = self.locatorAudioSeconds {
                parts.append(Self.clockText(seconds))
            }
        } else if let progression: Double = self.readingProgress?.totalProgression {
            parts.append(String(format: NSLocalizedString("book_detail_progress_total", comment: ""), Self.percentOrJustStarted(progression)))
        }
        if let date: Date = self.readingHistory?.visitedAt ?? self.readingProgress?.updatedAt {
            parts.append(Self.relativeDateFormatter.string(from: date))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 0 … 1 的全书进度；有声书没有时长算不出，为 nil（不画进度条）。
    var continueProgress: Double? {
        guard self.isAudiobook == false, let progression: Double = self.readingProgress?.totalProgression else {
            return nil
        }
        return min(1, max(0, progression))
    }

    /// 没有续读位置：「从第 1 章开始读 / 听」；起始章解不出编号「开始读 · 章名」；只有一章「开始阅读 / 收听」。
    var startButtonTitle: String {
        let audio: Bool = self.isAudiobook
        guard self.displayEntries.count > 1, let starting: BookChapterEntry = self.displayEntries.first else {
            return NSLocalizedString(audio ? "book_detail_start_listening" : "book_detail_start_reading", comment: "")
        }
        if starting.numberLabel != nil {
            return NSLocalizedString(audio ? "book_detail_start_listening_from_first" : "book_detail_start_from_first", comment: "")
        }
        return String(
            format: NSLocalizedString(audio ? "book_detail_start_listening_with" : "book_detail_start_with", comment: ""),
            starting.item.title
        )
    }

    /// 中文注释：起点章节：有续读位置就从那一章继续，否则显示顺序的第一章。
    var primaryChapter: BookPublicationItem? {
        if let url: URL = self.lastReadChapterURL, let item: BookPublicationItem = self.chapters.first(where: { $0.chapterURL == url }) {
            return item
        }
        return self.displayEntries.first?.item ?? self.chapters.first
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

    // MARK: - 目录（第六节）

    func isCurrent(_ entry: BookChapterEntry) -> Bool {
        return entry.item.chapterURL == self.lastReadChapterURL
    }

    /// 已读推定：manifest 顺序里排在上次读到之前的章（倒序显示时同样按这个位置算）。
    func isRead(_ entry: BookChapterEntry) -> Bool {
        guard let url: URL = self.lastReadChapterURL,
              let currentIndex: Int = self.chapters.firstIndex(where: { $0.chapterURL == url }),
              let index: Int = self.chapters.firstIndex(where: { $0.chapterURL == entry.item.chapterURL }) else {
            return false
        }
        return index < currentIndex
    }

    /// 上次读到那一行的行尾：文字书「读到 12%」（章内 `progression`）、有声书「12:34」。
    var currentChapterTrailingText: String? {
        if self.isAudiobook {
            return self.locatorAudioSeconds.map(Self.clockText)
        }
        guard let progression: Double = self.locatorProgression else {
            return nil
        }
        return String(format: NSLocalizedString("book_detail_read_to_percent", comment: ""), Self.percentText(progression))
    }

    var isDisplayDescending: Bool {
        return self.isDisplayOrderFlipped
    }

    var showsOrderToggle: Bool {
        return self.chapters.count >= 2
    }

    func toggleDisplayOrder() {
        self.isDisplayOrderFlipped.toggle()
        self.selectedSegmentID = nil
        self.rebuildChapterDerivedState()
    }

    var effectiveSelectedSegmentID: String? {
        guard let selected: String = self.selectedSegmentID, self.segments.contains(where: { $0.id == selected }) else {
            return self.segments.first?.id
        }
        return selected
    }

    func selectSegment(_ segmentID: String) {
        self.selectedSegmentID = segmentID
        self.isProgrammaticScrolling = true
        self.pendingScrollChapterURL = segmentID
    }

    func didFinishProgrammaticScroll() {
        self.pendingScrollChapterURL = nil
        self.isProgrammaticScrolling = false
    }

    /// 行滚进视口时把分段芯片跟到它所在的段；点芯片滚动期间不反过来改。
    func chapterDidAppear(_ entry: BookChapterEntry) {
        guard self.isProgrammaticScrolling == false,
              let segment: ComicChapterSegment = self.segments.first(where: { $0.chapterURLs.contains(entry.id) }),
              segment.id != self.selectedSegmentID else {
            return
        }
        self.selectedSegmentID = segment.id
    }

    private func rebuildChapterDerivedState() {
        let parsed: [ComicChapterTitleParser.ParsedTitle] = ComicChapterTitleParser.parse(self.chapters.map(\.title))
        var ordered: [(item: BookPublicationItem, parsed: ComicChapterTitleParser.ParsedTitle)] = Array(zip(self.chapters, parsed))
        if self.isDisplayOrderFlipped {
            ordered.reverse()
        }
        let entries: [BookChapterEntry] = ordered.enumerated().map { index, pair in
            BookChapterEntry(item: pair.item, numberLabel: pair.parsed.numberLabel, name: pair.parsed.name, ordinal: index + 1)
        }
        self.displayEntries = entries
        self.segments = Self.makeSegments(entries)
        if let selected: String = self.selectedSegmentID, self.segments.contains(where: { $0.id == selected }) == false {
            self.selectedSegmentID = self.segments.first?.id
        } else if self.selectedSegmentID == nil {
            self.selectedSegmentID = self.segments.first?.id
        }
    }

    /// ≥ 60 章时按显示顺序每 50 章一段；芯片文字是段首与段尾的编号（解不出编号用序号）。与漫画详情同一规则。
    private static func makeSegments(_ entries: [BookChapterEntry]) -> [ComicChapterSegment] {
        guard entries.count >= ComicChapterTitleParser.segmentThreshold else {
            return []
        }
        return stride(from: 0, to: entries.count, by: ComicChapterTitleParser.segmentSize).map { start in
            let end: Int = min(start + ComicChapterTitleParser.segmentSize, entries.count)
            let slice: ArraySlice<BookChapterEntry> = entries[start..<end]
            let first: BookChapterEntry = slice.first!
            let last: BookChapterEntry = slice.last!
            let firstLabel: String = first.numberLabel ?? String(first.ordinal)
            let lastLabel: String = last.numberLabel ?? String(last.ordinal)
            return ComicChapterSegment(
                id: first.id,
                title: slice.count == 1 ? firstLabel : "\(firstLabel)–\(lastLabel)",
                chapterURLs: Set(slice.map(\.id))
            )
        }
    }

    // MARK: - 收藏

    func reloadFavoriteState() async {
        guard let useCase: ToggleFavoriteUseCase = self.toggleFavoriteUseCase else {
            return
        }
        do {
            self.isFavorite = try useCase.loadFavoriteItemIDs(sourceID: self.source.id).contains(self.item.id)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: "book-detail-favorite-error")
        }
    }

    func toggleFavorite() async {
        guard let useCase: ToggleFavoriteUseCase = self.toggleFavoriteUseCase else {
            return
        }
        do {
            let ids: Set<String> = try useCase.execute(item: self.item, source: self.source, favoritedAt: self.now())
            let wasFavorite: Bool = self.isFavorite
            self.isFavorite = ids.contains(self.item.id)
            AppAnalytics.shared.logBookmarkChanged(isFavorite: wasFavorite == false, source: self.source)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: "book-detail-favorite-error")
        }
    }

    var canToggleFavorite: Bool {
        return self.toggleFavoriteUseCase != nil
    }

    // MARK: - 登录（第七节）

    /// 来源有登录页时失败横幅多一个「登录」；凭据存储没注入（测试替身）就没有。
    var sourceLoginState: LibrarySourceLoginState? {
        guard let store: any SourceCredentialStoring = self.sourceCredentialStore else {
            return nil
        }
        return LibrarySourceLoginStateResolver(credentialStore: store, now: self.now).resolve(source: self.source)
    }

    func requestSourceLogin() {
        self.requestedSourceLogin = self.sourceLoginState
    }

    func dismissRequestedSourceLogin() {
        self.requestedSourceLogin = nil
    }

    /// 登录后存凭据并重取详情；登录不一定解锁，结果照页面状态显示。
    func completeRequestedSourceLogin(credential: SourceCredential) async {
        guard credential.sourceID == self.requestedSourceLogin?.sourceID,
              let store: any SourceCredentialStoring = self.sourceCredentialStore else {
            return
        }
        store.save(credential)
        self.requestedSourceLogin = nil
        await self.load()
    }

    // MARK: - 加载

    func loadIfNeeded() async {
        guard self.isLoading == false else {
            return
        }
        if let manifest: BookPublicationManifest = self.manifest {
            // 中文注释：从阅读器 / 播放页退回来时 manifest 还在，但续读位置已经变了——只重读进度与历史，不重取详情
            //（2026-09-14 loyalbooks 模拟器复验：播到第 03–04 章退回详情页仍显示「Start Listening」）。
            self.reloadReadingPosition(in: manifest)
            return
        }
        await self.load()
    }

    func load() async {
        guard let detailURL: URL = URL(string: self.item.detailURL) else {
            self.errorMessage = "Invalid detail URL."
            return
        }
        CrashDiagnostics.shared.setRuleStage(.detail)
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        do {
            let loaded: LoadedBookPublication = try await self.loadPublicationUseCase.execute(source: self.source, detailURL: detailURL)
            self.manifest = loaded.manifest
            self.didLoad = true
            self.rebuildChapterDerivedState()
            self.reloadReadingPosition(in: loaded.manifest)
        } catch {
            AppAnalytics.shared.logDiagnosticFailure(kind: RuleExecutionErrorClassifier.diagnosticFailureKind(for: error), stage: .detail, errorCode: "book-detail-error")
            self.errorMessage = error.localizedDescription
        }
    }

    /// 重读进度表与读书历史，再定上次读到的章：先按历史的 `chapterURL`，没有再按 Locator 的 `href`。
    private func reloadReadingPosition(in manifest: BookPublicationManifest) {
        self.readingProgress = try? self.loadProgressUseCase.execute(bookID: self.bookID, userID: self.userID)
        self.readingHistory = self.fetchReadingHistory()
        self.lastReadChapterURL = self.resolveLastReadChapter(in: manifest)
    }

    private func fetchReadingHistory() -> BookReadingHistory? {
        guard let repository: any BookReadingHistoryRepository = self.readingHistoryRepository else {
            return nil
        }
        do {
            return try repository.fetchHistory(userID: self.userID).first { history in
                history.sourceID == self.source.id && history.bookItemID == self.item.id
            }
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: "book-detail-history-error")
            return nil
        }
    }

    private func resolveLastReadChapter(in manifest: BookPublicationManifest) -> URL? {
        if let historyURL: URL = self.readingHistory?.chapterURL,
           manifest.items.contains(where: { $0.chapterURL == historyURL }) {
            return historyURL
        }
        guard let progress: BookReadingProgress = self.readingProgress,
              let href: String = Self.locatorValue(progress.locatorJSON)?["href"] as? String else {
            return nil
        }
        return manifest.items.first { $0.href == href || "/" + $0.href == href || $0.chapterURL.absoluteString == href }?.chapterURL
    }

    // MARK: - Locator

    private var locatorLocations: [String: Any]? {
        guard let progress: BookReadingProgress = self.readingProgress else {
            return nil
        }
        return Self.locatorValue(progress.locatorJSON)?["locations"] as? [String: Any]
    }

    /// 章内进度 0 … 1。
    private var locatorProgression: Double? {
        return self.locatorLocations?["progression"] as? Double
    }

    /// 有声书的时间点：Readium Audio Navigator 写在 `locations.fragments` 里的 `t=秒`。
    private var locatorAudioSeconds: Double? {
        guard let fragments: [String] = self.locatorLocations?["fragments"] as? [String] else {
            return nil
        }
        for fragment in fragments where fragment.hasPrefix("t=") {
            if let seconds: Double = Double(fragment.dropFirst(2)) {
                return seconds
            }
        }
        return nil
    }

    private static func locatorValue(_ json: String) -> [String: Any]? {
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
    }

    // MARK: - 文案工具

    private static func percentText(_ progression: Double) -> String {
        return "\(Int((min(1, max(0, progression)) * 100).rounded()))%"
    }

    /// 全书进度小于 1% 写「刚开始」（几百章的书读到第 3 章就是 0%）。
    private static func percentOrJustStarted(_ progression: Double) -> String {
        guard progression >= 0.01 else {
            return NSLocalizedString("book_detail_just_started", comment: "")
        }
        return Self.percentText(progression)
    }

    static func clockText(_ seconds: Double) -> String {
        let total: Int = max(0, Int(seconds.rounded()))
        let hours: Int = total / 3600
        let minutes: Int = (total % 3600) / 60
        let secs: Int = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed: String = text?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter: NumberFormatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static let relativeDateFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
