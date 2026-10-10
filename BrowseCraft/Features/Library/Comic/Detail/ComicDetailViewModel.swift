import Observation
import Foundation
import BrowseCraftCore
import BrowseCraftDomain

// 中文注释：漫画详情与章节页的状态（`docs/design/Comic-Detail-Page-Redesign-Design.md`）。
// 页上每一块只在规则或本机历史给了数据时出现：头部按 `SourceDetailMetadata` 有什么出什么，
// 目录版式按章节标题的形状二选一，已读 / 上次读到按本作品的全部章节历史标。

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

struct ComicDetailSourceLoginPrompt: Identifiable, Hashable {
    let state: LibrarySourceLoginState
    let isPaid: Bool?

    var id: String {
        return state.id
    }
}

/// 目录里的一条：章节 + 解析出来的编号与话名（第七节）。`ordinal` 是显示顺序里的序号，从 1 起。
struct ComicChapterEntry: Identifiable, Hashable {
    let chapter: ChapterLink
    /// 「1249」「1-1」「3-上」；解不出数字为 nil。
    let numberLabel: String?
    /// 去掉编号与分隔符后剩下的话名；空串表示纯编号。
    let name: String
    let ordinal: Int

    var id: String {
        return self.chapter.url
    }

    /// 编号柱显示什么：解出数字写数字，解不出写显示顺序的序号「#12」。
    var columnLabel: String {
        return self.numberLabel ?? "#\(self.ordinal)"
    }

    /// 行标题：解出数字且话名非空显示话名，否则显示原标题。
    var rowTitle: String {
        if self.numberLabel != nil, self.name.isEmpty == false {
            return self.name
        }
        return self.chapter.title
    }
}

/// 分段芯片：按显示顺序每 50 章一段，`id` 是段首章节 URL，点了滚到那一行。
struct ComicChapterSegment: Identifiable, Hashable {
    let id: String
    let title: String
    let chapterURLs: Set<String>
}

/// 章节标题解析（第七节）：只影响显示，不改顺序、不进存储。
enum ComicChapterTitleParser {
    struct ParsedTitle: Hashable {
        let numberLabel: String?
        let name: String
    }

    static let segmentSize: Int = 50
    static let segmentThreshold: Int = 60

    /// 开头可跳过的非数字前缀（sfacg 的「VIP」、「Chapter 」「Ch.」），再「第N话 / N話 / 纯数字 N」，
    /// 紧跟的「(n)」「（n）」「上 / 中 / 下」「前半 / 后半」是分节。
    /// 中文注释：`NSRegularExpression` 编译后不可变且 Sendable，进程内只编译一次（2026-10-10 复审 B-9：
    /// 之前每次 `parse` 都重编译，库页瓷砖的计算属性每次访问一次、中文数字一支每个标题一次）。
    /// 编译失败用可选值兜底、不强制解包（`BCA-ARCH-005`），此时所有标题都解不出数字（退到序号与原标题）。
    private static let pattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^\s*[^\d第]{0,8}?\s*(?:第\s*)?(\d+)\s*(?:话|話|章|回|集|卷|节|節|页|頁)?\s*(?:[(（]\s*(\d+)\s*[)）]|(上|中|下|前半|后半|後半|前编|前編|后编|後編|前篇|后篇|後篇))?"#,
        options: []
    )

    private static let leadingSeparators: CharacterSet = {
        var set: CharacterSet = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: ":：·・-–—_.|｜")
        return set
    }()

    static func parse(_ title: String) -> ParsedTitle {
        return Self.parse([title])[0]
    }

    /// 整个目录一起解析。
    static func parse(_ titles: [String]) -> [ParsedTitle] {
        return titles.map { Self.parse($0, pattern: Self.pattern) }
    }

    /// 中文注释：「第八百六十二章 普罗万修」这类中文数字编号（笔趣阁、SF 桌面版整本都是）：`第` + 中文数字 + 单位；
    /// 书籍详情页那轮加的，漫画一起受益（`docs/design/Book-Detail-Page-Redesign-Design.md` 第八节）。
    private static let chinesePattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^\s*第\s*([零〇一二三四五六七八九十百千万萬两兩]+)\s*(?:章|话|話|回|集|卷|节|節|页|頁)?"#,
        options: []
    )

    private static func parse(_ title: String, pattern: NSRegularExpression?) -> ParsedTitle {
        let trimmed: String = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let range: NSRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let pattern: NSRegularExpression = pattern,
              let match: NSTextCheckingResult = pattern.firstMatch(in: trimmed, options: [], range: range),
              let numberRange: Range<String.Index> = Range(match.range(at: 1), in: trimmed),
              let number: Int = Int(trimmed[numberRange]) else {
            return Self.parseChineseNumeral(trimmed)
        }
        var label: String = String(number)
        if let partRange: Range<String.Index> = Range(match.range(at: 2), in: trimmed), let part: Int = Int(trimmed[partRange]) {
            label += "-\(part)"
        } else if let wordRange: Range<String.Index> = Range(match.range(at: 3), in: trimmed) {
            label += "-\(trimmed[wordRange])"
        }
        guard let matchedRange: Range<String.Index> = Range(match.range, in: trimmed) else {
            return ParsedTitle(numberLabel: label, name: "")
        }
        let remainder: String = String(trimmed[matchedRange.upperBound...])
            .trimmingCharacters(in: Self.leadingSeparators)
        return ParsedTitle(numberLabel: label, name: remainder)
    }

    private static func parseChineseNumeral(_ trimmed: String) -> ParsedTitle {
        let range: NSRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let pattern: NSRegularExpression = Self.chinesePattern,
              let match: NSTextCheckingResult = pattern.firstMatch(in: trimmed, options: [], range: range),
              let numberRange: Range<String.Index> = Range(match.range(at: 1), in: trimmed),
              let number: Int = Self.chineseNumber(String(trimmed[numberRange])),
              let matchedRange: Range<String.Index> = Range(match.range, in: trimmed) else {
            return ParsedTitle(numberLabel: nil, name: trimmed)
        }
        let remainder: String = String(trimmed[matchedRange.upperBound...])
            .trimmingCharacters(in: Self.leadingSeparators)
        return ParsedTitle(numberLabel: String(number), name: remainder)
    }

    /// 中文数字转整数：「八百六十二」→ 862、「十二」→ 12、「一千零一」→ 1001；「二零一」这种逐位写法也认。
    static func chineseNumber(_ text: String) -> Int? {
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "兩": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let units: [Character: Int] = ["十": 10, "百": 100, "千": 1000, "万": 10000, "萬": 10000]
        guard text.isEmpty == false else {
            return nil
        }
        if text.allSatisfy({ digits[$0] != nil }) && text.count > 1 && text.contains(where: { $0 == "零" || $0 == "〇" }) {
            // 逐位写法：「二零一」
            return text.reduce(0) { $0 * 10 + digits[$1]! }
        }
        var total: Int = 0
        var section: Int = 0
        var current: Int = 0
        for character in text {
            if let digit: Int = digits[character] {
                current = digit
            } else if let unit: Int = units[character] {
                if unit == 10000 {
                    section += current == 0 && section == 0 ? 0 : current
                    total += (section == 0 ? 1 : section) * unit
                    section = 0
                    current = 0
                } else {
                    section += (current == 0 ? 1 : current) * unit
                    current = 0
                }
            } else {
                return nil
            }
        }
        let value: Int = total + section + current
        return value > 0 ? value : nil
    }

    /// 纯编号目录：所有章节的话名都为空（允许少于 10% 的例外，如「番外」「预告」）。
    static func isPureNumberCatalog(_ parsed: [ParsedTitle]) -> Bool {
        guard parsed.isEmpty == false else {
            return false
        }
        let exceptions: Int = parsed.filter { $0.numberLabel == nil || $0.name.isEmpty == false }.count
        return exceptions * 10 < parsed.count
    }
}

/// 中文注释：ComicDetailViewModel 持有漫画详情页状态；ReaderViewModel 只负责具体章节阅读。
@MainActor
@Observable
final class ComicDetailViewModel {
    private(set) var metadata: SourceDetailMetadata?
    private(set) var chapters: [ChapterLink] = []
    /// 本作品读过的全部章节，最近的在前（第六、七节）。
    private(set) var chapterHistories: [ComicChapterHistory] = []
    /// 章节变了或翻转顺序时重算的派生状态：目录解析结果、显示顺序、版式、分段；上千章的目录不在每次渲染时重算。
    private(set) var displayEntries: [ComicChapterEntry] = []
    private(set) var segments: [ComicChapterSegment] = []
    private(set) var usesGrid: Bool = false
    /// Core 给的顺序是不是正序：按首尾两章解出的话数推断；解不出时为 nil，退到规则声明的方向。
    /// めちゃコミック的规则没声明 `sort`，页面顺序是正序，只按规则会把「第 1 话」认成最后一章（2026-10-08 模拟器实测）。
    private(set) var coreOrderIsAscending: Bool?
    private var readChapterKeys: Set<String> = []
    private(set) var isLoading: Bool = false
    private(set) var didLoad: Bool = false
    private(set) var isFavorite: Bool = false
    private(set) var sourceLoginPrompt: ComicDetailSourceLoginPrompt?
    private(set) var requestedSourceLogin: LibrarySourceLoginState?
    /// 目录的显示顺序是否相对 Core 给的顺序翻转；不改进阅读器的导航顺序。
    private(set) var isDisplayOrderFlipped: Bool = false
    /// 当前选中的分段（段首章节 URL）。
    private(set) var selectedSegmentID: String?
    /// 点分段芯片后要滚到的那一行；视图滚完后清掉。
    private(set) var pendingScrollChapterURL: String?
    var accessMessage: String?
    var errorMessage: String?

    let item: ContentItem
    let source: Source

    private let loadComicDetailUseCase: LoadComicDetailUseCase
    private let persistenceCoordinator: ReadingActivityPersistenceCoordinator
    private let resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase
    private let sourceCredentialStore: (any SourceCredentialStoring)?
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let toggleFavoriteUseCase: ToggleFavoriteUseCase?
    /// 中文注释：收藏读写走 actor，不在主线程跑 GRDB（复审 B-3）。
    private let favoritePersistence: FavoriteStatePersistenceCoordinator?
    private let fallbackUserID: String
    private let now: () -> Date
    private var pendingRestrictedChapterURL: String?
    /// 点芯片滚动期间不让行的 onAppear 反过来改选中段。
    private var isProgrammaticScrolling: Bool = false

    init(
        item: ContentItem,
        source: Source,
        loadComicDetailUseCase: LoadComicDetailUseCase,
        persistenceCoordinator: ReadingActivityPersistenceCoordinator,
        resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase,
        sourceCredentialStore: (any SourceCredentialStoring)? = nil,
        activeAppUser: (any ActiveAppUserProviding)? = nil,
        toggleFavoriteUseCase: ToggleFavoriteUseCase? = nil,
        userID: String = AppUser.localDefaultID,
        now: @escaping () -> Date = Date.init
    ) {
        self.item = item
        self.source = source
        self.loadComicDetailUseCase = loadComicDetailUseCase
        self.persistenceCoordinator = persistenceCoordinator
        self.resolveReaderSourcePresentationUseCase = resolveReaderSourcePresentationUseCase
        self.sourceCredentialStore = sourceCredentialStore
        self.activeAppUser = activeAppUser
        self.toggleFavoriteUseCase = toggleFavoriteUseCase
        self.favoritePersistence = toggleFavoriteUseCase.map(FavoriteStatePersistenceCoordinator.init(useCase:))
        self.fallbackUserID = userID
        self.now = now

        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftNavigation] Init ComicDetailViewModel " +
            "itemId=\(item.id) title=\(item.title) " +
            "detailURL=\(item.detailURL) sourceId=\(source.id)"
        )
        #endif
    }

    // MARK: - 头部取值（第五节）

    /// 列表项的标题优先——它是用户点进来时看到的那个名字；detail `title` 常是带站名前后缀的页面标题。
    var displayTitle: String {
        return self.nonEmpty(self.item.title) ?? self.nonEmpty(self.metadata?.title) ?? self.item.title
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

    var languageText: String? {
        return self.nonEmpty(self.metadata?.language)
    }

    var tags: [String] {
        return self.metadata?.tags.compactMap { self.nonEmpty($0) } ?? []
    }

    /// 更新行「更新至第94话 · 2026-10-01」：列表 `latestText` + detail `updatedAt`，有哪个写哪个；都没有为 nil。
    var updateLineText: String? {
        let parts: [String] = [self.nonEmpty(self.item.latestText), self.nonEmpty(self.metadata?.updatedAt)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var sourceHostText: String {
        return CatalogDisplayText.displayHost(CatalogDisplayText.addressParts(of: self.source.baseURL).host)
    }

    /// 简介块下方的属性小字：「发布 · 2021-03」「许可 · …」「编号 · …」「共 N 张」再加 `attributes` 的「label · value」。
    var attributeLines: [String] {
        guard let metadata: SourceDetailMetadata = self.metadata else {
            return []
        }
        var lines: [String] = []
        if let value: String = self.nonEmpty(metadata.publishedAt) {
            lines.append(NSLocalizedString("comic_detail_attr_published", comment: "") + " · " + value)
        }
        if let value: String = self.nonEmpty(metadata.license) {
            lines.append(NSLocalizedString("comic_detail_attr_license", comment: "") + " · " + value)
        }
        if let value: String = self.nonEmpty(metadata.idCode) {
            lines.append(NSLocalizedString("comic_detail_attr_id", comment: "") + " · " + value)
        }
        if let totalImages: Int = metadata.totalImages {
            lines.append(String(format: NSLocalizedString("comic_detail_attr_images", comment: ""), totalImages))
        }
        for attribute: SourceDetailAttribute in metadata.attributes {
            guard let value: String = self.nonEmpty(attribute.value) else {
                continue
            }
            if let label: String = self.nonEmpty(attribute.label) {
                lines.append(label + " · " + value)
            } else {
                lines.append(value)
            }
        }
        return lines
    }

    var relatedLinks: [ComicDetailRelatedLink] {
        guard let metadata: SourceDetailMetadata = self.metadata else {
            return []
        }
        var links: [ComicDetailRelatedLink] = []
        if let photoAlbumURL: URL = metadata.photoAlbumURL {
            links.append(ComicDetailRelatedLink(title: NSLocalizedString("comic_detail_link_photo_album", comment: ""), url: photoAlbumURL))
        }
        if let secondLevelPageURL: URL = metadata.secondLevelPageURL,
           secondLevelPageURL != metadata.photoAlbumURL {
            links.append(ComicDetailRelatedLink(title: NSLocalizedString("comic_detail_link_related_page", comment: ""), url: secondLevelPageURL))
        }
        return links
    }

    var hasSynopsisSection: Bool {
        return self.descriptionText != nil || self.attributeLines.isEmpty == false || self.relatedLinks.isEmpty == false
    }

    var detailCoverRequestConfig: RequestConfig? {
        return self.resolveReaderSourcePresentationUseCase.detailCoverRequestConfig(for: self.source)
    }

    // MARK: - 目录（第七节）

    /// 规则声明的章节顺序方向（Core 已按它排好），阅读器的上一话 / 下一话按它走。
    var chapterNavigationOrder: ChapterNavigationOrder {
        let resolvedRule: ResolvedComicSiteRuleV2? = ComicSiteRuleV2Validator()
            .validate(rule: self.source.rule)
            .resolvedRule
        let detailRule: ComicDetailRuleV2? = resolvedRule.flatMap { graph in
            graph.primaryDetailEntry.map { entry in
                graph.detailRule(for: entry)
            }
        }
        let chapterSort: ChapterSort? = detailRule?.chapterAPI?.sort ?? detailRule?.chapterRule?.sort
        return chapterSort == .ascending ? .ascending : .descending
    }

    /// 「第 1 话」是哪一头：先按解出的话数推断，解不出按规则排序方向取。
    var startingChapter: ChapterLink? {
        let ascending: Bool = self.coreOrderIsAscending ?? (self.chapterNavigationOrder == .ascending)
        return ascending ? self.chapters.first : self.chapters.last
    }

    /// 章节或显示顺序变了之后重算目录的派生状态。
    private func rebuildChapterDerivedState() {
        let parsed: [ComicChapterTitleParser.ParsedTitle] = ComicChapterTitleParser.parse(self.chapters.map(\.title))
        self.usesGrid = ComicChapterTitleParser.isPureNumberCatalog(parsed)
        self.coreOrderIsAscending = Self.inferAscending(parsed)
        var ordered: [(chapter: ChapterLink, parsed: ComicChapterTitleParser.ParsedTitle)] = Array(zip(self.chapters, parsed))
        if self.isDisplayOrderFlipped {
            ordered.reverse()
        }
        let entries: [ComicChapterEntry] = ordered.enumerated().map { index, pair in
            ComicChapterEntry(
                chapter: pair.chapter,
                numberLabel: pair.parsed.numberLabel,
                name: pair.parsed.name,
                ordinal: index + 1
            )
        }
        self.displayEntries = entries
        self.segments = Self.makeSegments(entries)
        if let selected: String = self.selectedSegmentID, self.segments.contains(where: { $0.id == selected }) == false {
            self.selectedSegmentID = self.segments.first?.id
        } else if self.selectedSegmentID == nil {
            self.selectedSegmentID = self.segments.first?.id
        }
    }

    /// 首尾两章的话数都解得出且不相等时才下结论。
    private static func inferAscending(_ parsed: [ComicChapterTitleParser.ParsedTitle]) -> Bool? {
        guard parsed.count >= 2,
              let first: Int = Self.leadingNumber(parsed.first?.numberLabel),
              let last: Int = Self.leadingNumber(parsed.last?.numberLabel),
              first != last else {
            return nil
        }
        return first < last
    }

    private static func leadingNumber(_ label: String?) -> Int? {
        guard let label: String = label else {
            return nil
        }
        return Int(label.prefix { $0.isNumber })
    }

    /// ≥ 60 章时按显示顺序每 50 章一段；芯片文字是段首与段尾的编号（解不出编号用序号）。
    private static func makeSegments(_ entries: [ComicChapterEntry]) -> [ComicChapterSegment] {
        guard entries.count >= ComicChapterTitleParser.segmentThreshold else {
            return []
        }
        return stride(from: 0, to: entries.count, by: ComicChapterTitleParser.segmentSize).map { start in
            let end: Int = min(start + ComicChapterTitleParser.segmentSize, entries.count)
            let slice: ArraySlice<ComicChapterEntry> = entries[start..<end]
            let first: ComicChapterEntry = slice.first!
            let last: ComicChapterEntry = slice.last!
            let firstLabel: String = first.numberLabel ?? String(first.ordinal)
            let lastLabel: String = last.numberLabel ?? String(last.ordinal)
            return ComicChapterSegment(
                id: first.id,
                title: slice.count == 1 ? firstLabel : "\(firstLabel)–\(lastLabel)",
                chapterURLs: Set(slice.map(\.id))
            )
        }
    }

    /// 正序 / 倒序的当前文案：Core 给的顺序按规则方向算，翻转后反过来。
    var isDisplayDescending: Bool {
        let baseDescending: Bool = self.coreOrderIsAscending.map { $0 == false } ?? (self.chapterNavigationOrder == .descending)
        return self.isDisplayOrderFlipped ? !baseDescending : baseDescending
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

    /// 视图滚到段首之后调用；之后行的出现才再驱动芯片选中。
    func didFinishProgrammaticScroll() {
        self.pendingScrollChapterURL = nil
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.isProgrammaticScrolling = false
        }
    }

    /// 行或格子出现在屏上：当前滚到哪一段哪个芯片选中。
    func chapterDidAppear(_ entry: ComicChapterEntry) {
        guard self.isProgrammaticScrolling == false, self.segments.isEmpty == false else {
            return
        }
        guard let segment: ComicChapterSegment = self.segments.first(where: { $0.chapterURLs.contains(entry.id) }),
              segment.id != self.selectedSegmentID else {
            return
        }
        self.selectedSegmentID = segment.id
    }

    // MARK: - 已读与继续阅读（第六、七节）

    private static func readChapterKeys(of histories: [ComicChapterHistory]) -> Set<String> {
        var keys: Set<String> = []
        for history: ComicChapterHistory in histories {
            keys.insert(history.chapterKey)
            if let url: URL = history.chapterURL {
                keys.insert(url.absoluteString)
            }
        }
        return keys
    }

    func isRead(_ entry: ComicChapterEntry) -> Bool {
        return self.readChapterKeys.contains(entry.chapter.url)
    }

    /// 目录里读过的章数（只数还在目录里的）。
    var readCount: Int {
        return self.chapters.filter { self.readChapterKeys.contains($0.url) }.count
    }

    var latestReadingHistory: ComicChapterHistory? {
        return self.chapterHistories.max { $0.visitedAt < $1.visitedAt }
    }

    /// 历史对上的那一章：先按阅读页地址，再按章节名；都对不上为 nil（此时用历史记录直接开阅读器）。
    var continueChapter: ChapterLink? {
        guard let history: ComicChapterHistory = self.latestReadingHistory else {
            return nil
        }
        if let byURL: ChapterLink = self.chapters.first(where: { $0.url == history.chapterURL?.absoluteString || $0.url == history.chapterKey }) {
            return byURL
        }
        guard let title: String = self.nonEmpty(history.chapterTitle) else {
            return nil
        }
        return self.chapters.first { $0.title == title }
    }

    func isCurrent(_ entry: ComicChapterEntry) -> Bool {
        return self.continueChapter?.url == entry.chapter.url
    }

    /// 继续阅读要去哪：有历史用历史记录（与历史页点行同一条路），没有用起始章。
    var continueDestination: ComicReaderDestination? {
        if let history: ComicChapterHistory = self.latestReadingHistory {
            return .history(history)
        }
        if let startingChapter: ChapterLink = self.startingChapter {
            return .chapter(startingChapter)
        }
        return nil
    }

    var continueCardTitle: String? {
        guard let history: ComicChapterHistory = self.latestReadingHistory else {
            return nil
        }
        return self.continueChapter?.title ?? self.nonEmpty(history.chapterTitle)
    }

    /// 「第 13 页 · 昨天 21:40」，有页数时「13 / 45 页 · 昨天 21:40」。
    var continueCardSubtitle: String? {
        guard let history: ComicChapterHistory = self.latestReadingHistory else {
            return nil
        }
        var parts: [String] = []
        if let progress: String = Self.pageProgressText(pageIndex: history.lastPageIndex, pageCount: history.pageCount) {
            parts.append(progress)
        }
        parts.append(Self.relativeDateFormatter.string(from: history.visitedAt))
        return parts.joined(separator: " · ")
    }

    /// 0 … 1 的阅读进度；没有页数为 nil（不画进度条）。
    var continueProgress: Double? {
        guard let history: ComicChapterHistory = self.latestReadingHistory,
              let pageIndex: Int = history.lastPageIndex,
              let pageCount: Int = history.pageCount, pageCount > 0 else {
            return nil
        }
        return min(1, max(0, Double(pageIndex + 1) / Double(pageCount)))
    }

    /// 目录里上次读到那一章右侧的「第 13 页」/「13 / 45」。
    var currentChapterProgressText: String? {
        guard let history: ComicChapterHistory = self.latestReadingHistory else {
            return nil
        }
        if let pageIndex: Int = history.lastPageIndex, let pageCount: Int = history.pageCount, pageCount > 0 {
            return "\(pageIndex + 1) / \(pageCount)"
        }
        return Self.pageProgressText(pageIndex: history.lastPageIndex, pageCount: nil)
    }

    var continueThumbnailURLString: String? {
        return self.latestReadingHistory?.lastPageImageURL?.absoluteString ?? self.coverURLString
    }

    var continueThumbnailRefererURLString: String? {
        return self.latestReadingHistory?.lastReaderPageURL?.absoluteString ?? self.item.detailURL
    }

    /// 没有历史时的按钮：「从第 1 话开始读」；起始章解不出数字「开始读 · 章节名」；只有一章「开始阅读」。
    var startButtonTitle: String {
        guard self.chapters.count > 1, let starting: ChapterLink = self.startingChapter else {
            return NSLocalizedString("comic_detail_start_reading", comment: "")
        }
        if ComicChapterTitleParser.parse(starting.title).numberLabel != nil {
            return NSLocalizedString("comic_detail_start_from_first", comment: "")
        }
        return String(format: NSLocalizedString("comic_detail_start_with", comment: ""), starting.title)
    }

    static func pageProgressText(pageIndex: Int?, pageCount: Int?) -> String? {
        guard let pageIndex: Int = pageIndex, pageIndex >= 0 else {
            return nil
        }
        if let pageCount: Int = pageCount, pageCount > 0 {
            return String(format: NSLocalizedString("comic_detail_page_of_total", comment: ""), pageIndex + 1, pageCount)
        }
        return String(format: NSLocalizedString("history_progress_page", comment: ""), pageIndex + 1)
    }

    private static let relativeDateFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    // MARK: - 收藏（第五节）

    func reloadFavoriteState() async {
        guard let persistence: FavoriteStatePersistenceCoordinator = self.favoritePersistence else {
            return
        }
        do {
            self.isFavorite = try await persistence.isFavorite(itemID: self.item.id, sourceID: self.source.id)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: "comic-detail-favorite-error")
        }
    }

    func toggleFavorite() async {
        guard let persistence: FavoriteStatePersistenceCoordinator = self.favoritePersistence else {
            return
        }
        do {
            let wasFavorite: Bool = self.isFavorite
            self.isFavorite = try await persistence.toggle(item: self.item, source: self.source, favoritedAt: self.now())
            AppAnalytics.shared.logBookmarkChanged(isFavorite: wasFavorite == false, source: self.source)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: "comic-detail-favorite-error")
        }
    }

    // MARK: - 加载

    func loadIfNeeded() async {
        guard self.didLoad == false, self.isLoading == false else {
            return
        }
        await self.load()
    }

    func reload() async {
        await self.load()
    }

    /// 中文注释：详情页只拦截规则明确标记为 restricted 的章节；unknown 继续沿用既有阅读流程。
    func prepareToOpen(_ chapter: ChapterLink) -> Bool {
        self.accessMessage = nil
        self.sourceLoginPrompt = nil
        guard chapter.isRestricted == true else {
            return true
        }

        guard let sourceCredentialStore,
              let loginState = LibrarySourceLoginStateResolver(
                credentialStore: sourceCredentialStore
              ).resolve(source: self.source) else {
            self.accessMessage = NSLocalizedString("comic_detail_access_no_login_page", comment: "受限且来源没有登录页")
            return false
        }

        guard loginState.status == .guest else {
            self.accessMessage = self.restrictedMessage(isPaid: chapter.isPaid)
            return false
        }

        self.pendingRestrictedChapterURL = chapter.url
        self.sourceLoginPrompt = ComicDetailSourceLoginPrompt(
            state: loginState,
            isPaid: chapter.isPaid
        )
        return false
    }

    func requestSourceLogin(state: LibrarySourceLoginState) {
        self.sourceLoginPrompt = nil
        self.requestedSourceLogin = state
    }

    func hideSourceLoginPrompt() {
        self.sourceLoginPrompt = nil
    }

    func dismissSourceLoginPrompt() {
        self.sourceLoginPrompt = nil
        self.pendingRestrictedChapterURL = nil
    }

    func dismissAccessMessage() {
        self.accessMessage = nil
    }

    func dismissRequestedSourceLogin() {
        self.requestedSourceLogin = nil
        self.pendingRestrictedChapterURL = nil
    }

    /// 受限章节的登录提示文案（页内横幅，第八节；文案沿用原来的提示框）。
    func loginPromptMessage(isPaid: Bool?) -> String {
        if isPaid == true {
            return NSLocalizedString("comic_detail_login_prompt_paid", comment: "付费章受限，登录看看")
        }
        return NSLocalizedString("comic_detail_login_prompt", comment: "受限，登录看看")
    }

    /// 中文注释：登录后必须刷新详情 API 并重新读取源站逐章状态，不能假设登录必然解锁。
    func completeRequestedSourceLogin(credential: SourceCredential) async -> ChapterLink? {
        guard credential.sourceID == self.requestedSourceLogin?.sourceID,
              let sourceCredentialStore else {
            return nil
        }

        sourceCredentialStore.save(credential)
        self.requestedSourceLogin = nil
        let pendingURL = self.pendingRestrictedChapterURL
        self.pendingRestrictedChapterURL = nil
        await self.load()

        guard let pendingURL,
              let refreshedChapter = self.chapters.first(where: { $0.url == pendingURL }) else {
            self.accessMessage = NSLocalizedString("comic_detail_access_chapter_unavailable", comment: "刷新后这一章没了")
            return nil
        }
        guard refreshedChapter.isRestricted == false else {
            if refreshedChapter.isRestricted == true {
                self.accessMessage = self.restrictedMessage(isPaid: refreshedChapter.isPaid)
            } else {
                self.accessMessage = NSLocalizedString("comic_detail_access_status_unknown", comment: "登录后读不到访问状态")
            }
            return nil
        }
        return refreshedChapter
    }

    private func load() async {
        CrashDiagnostics.shared.setRuleStage(.detail)
        self.isLoading = true
        self.errorMessage = nil
        await self.reloadChapterHistories()
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
                    isRestricted: chapter.isRestricted,
                    isPaid: chapter.isPaid,
                    navigationChapterURLs: chapter.navigationChapterURLs.map(\.absoluteString),
                    navigationChapterTitles: chapter.navigationChapterTitles,
                    navigationOrder: chapter.navigationOrder == .ascending ? .ascending : .descending
                )
            }
            self.didLoad = true
            self.rebuildChapterDerivedState()

            #if DEBUG
            AppDebugLog.write(
                "[BrowseCraftNavigation] Loaded comic detail " +
                "itemId=\(self.item.id) title=\(self.displayTitle) " +
                "chapters=\(self.chapters.count) hasMetadata=\(self.metadata != nil) " +
                "usesGrid=\(self.usesGrid) segments=\(self.segments.count) read=\(self.readCount)"
            )
            #endif
        } catch is CancellationError {
            return
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: "comic-detail-error")
            AppAnalytics.shared.logDiagnosticFailure(kind: RuleExecutionErrorClassifier.diagnosticFailureKind(for: error), stage: .detail, errorCode: "comic-detail-error")
            CrashDiagnostics.shared.record(
                error: error,
                category: .parser,
                errorCode: "comic-detail-error",
                event: "comic-detail-error"
            )
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    /// 中文注释：进页、下拉、阅读器返回后都重读一次本作品的全部章节历史，不必重复请求详情和章节列表。
    func reloadChapterHistories() async {
        let userID: String = self.currentUserID
        let sourceID: String = self.source.id
        let comicItemID: String = self.item.id
        do {
            let transfers: [ComicChapterHistoryTransfer] = try await self.persistenceCoordinator.loadComicHistories(
                userID: userID,
                sourceID: sourceID,
                comicItemID: comicItemID
            )
            self.chapterHistories = transfers.map(\.value)
            self.readChapterKeys = Self.readChapterKeys(of: self.chapterHistories)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: "comic-detail-history-error")
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value: String = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }
        return value
    }

    private func restrictedMessage(isPaid: Bool?) -> String {
        if isPaid == true {
            return NSLocalizedString("comic_detail_access_denied_paid", comment: "已登录仍看不了付费章")
        }
        return NSLocalizedString("comic_detail_access_denied", comment: "已登录仍看不了这一章")
    }

    private var currentUserID: String {
        return self.activeAppUser?.currentUserID.uuidString ?? self.fallbackUserID
    }
}
