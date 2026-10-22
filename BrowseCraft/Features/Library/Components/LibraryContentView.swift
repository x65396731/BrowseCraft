import BrowseCraftCore
import BrowseCraftDomain
import SwiftUI

struct LibraryContentView: View {
    let items: [ContentItem]
    let selectedSource: Source?
    let favoriteItemIDs: Set<String>
    let sourceForID: (String) -> Source?
    /// 中文注释：书脊列表在宽屏（iPad / 横屏）变两列时页边距 40，窄屏 20（`docs/design/Library-Book-Page-Redesign-Design.md` 第五节）。
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let toggleFavorite: (ContentItem) -> Void
    let openComic: (ContentItem, Source) -> Void
    let imageRequestConfig: (Source) -> RequestConfig?
    /// 中文注释：列表下一页由 ViewModel 按 Runtime 报出的 `pagination.nextPage` 给出；三种类型共用。
    let nextPage: Int?
    let loadNextPage: () -> Void
    let contentViewModelFactory: LibraryContentViewModelFactory
    /// 中文注释：分页脚（`docs/design/Library-Video-Page-Redesign-Design.md` 第三节）：网格下方一行小字代替此前悬浮在底栏上的胶囊；
    /// nil 时不画（规则不支持分页、搜索结果）。
    var paginationStatusText: String? = nil
    /// 中文注释：翻页失败时的原因，分页脚第二行小字；nil 即没失败。
    var paginationFailureDetail: String? = nil
    var isLoadingNextPage: Bool = false
    /// 中文注释：翻页失败时分页脚上的「报告问题」（Problem-Report-Design.md 第三节）；nil 时不出链接。
    var reportPaginationFailure: (() -> Void)? = nil
    /// 中文注释：漫画封面左下的「读到 4-2」（`docs/design/Library-Comic-Page-Redesign-Design.md` 第五节）；没读过为 nil。
    var comicProgressBadgeText: (ContentItem) -> String? = { _ in nil }
    /// 中文注释：漫画长按菜单「继续读 · 4-2」的编号；nil 时不出这一项。搜索页不接阅读器入口，留默认。
    var comicContinueChapterLabel: (ContentItem) -> String? = { _ in nil }
    var continueComicReading: (ContentItem) -> Void = { _ in }
    /// 中文注释：书籍行（`docs/design/Library-Book-Page-Redesign-Design.md` 第五节）：整站有声、第三行「读到 · 章节名」、
    /// 长按「继续读 / 继续听」的整句与回调；搜索页不接阅读器入口，留默认。
    var isAudiobookSource: Bool = false
    var bookReadToText: (ContentItem) -> String? = { _ in nil }
    var bookContinueMenuTitle: (ContentItem) -> String? = { _ in nil }
    var continueBookReading: (ContentItem) -> Void = { _ in }
    /// 中文注释：点开条目进详情时 `content_opened` 的入口：库页 `.library`，搜索页 `.search`。
    var contentOpenEntry: ContentOpenEntry = .library

    /// 中文注释：漫画三列、列距 12；iPad 与横屏按最小宽 104 自适应成更多列。
    private let comicGridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 104), spacing: 12)
    ]

    /// 中文注释：书脊列表单列；iPad 与横屏按最小宽 340 自适应成两列，行构造不变。
    private let bookListColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 340), spacing: 24)
    ]

    @ViewBuilder
    var body: some View {
        if let selectedSource: Source = self.selectedSource,
           selectedSource.configuration.kind == .video {
            VideoContentGridView(
                items: self.items,
                source: selectedSource,
                favoriteItemIDs: self.favoriteItemIDs,
                favoriteAction: self.toggleFavorite,
                nextPage: self.nextPage,
                loadNextPage: self.loadNextPage,
                contentViewModelFactory: self.contentViewModelFactory,
                contentOpenEntry: self.contentOpenEntry,
                imageRequestConfig: self.imageRequestConfig(selectedSource),
                paginationStatusText: self.paginationStatusText,
                paginationFailureDetail: self.paginationFailureDetail,
                reportPaginationFailure: self.reportPaginationFailure,
                isLoadingNextPage: self.isLoadingNextPage
            )
        } else if let selectedSource: Source = self.selectedSource,
                  selectedSource.configuration.kind == .book {
            self.bookList
        } else {
            self.comicGrid
        }
    }

    /// 漫画封面墙：三列、列距 12、行距 18、页边距 20（第四、五节）。
    private var comicGrid: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: self.comicGridColumns, spacing: 18) {
                ForEach(self.items, id: \.id) { item in
                    if let source: Source = self.sourceForID(item.sourceId) {
                        ComicLibraryCardView(
                            item: item,
                            isFavorite: self.favoriteItemIDs.contains(item.id),
                            progressBadgeText: self.comicProgressBadgeText(item),
                            continueChapterLabel: self.comicContinueChapterLabel(item),
                            imageRequestConfig: self.imageRequestConfig(source),
                            openAction: {
                                self.openItem(item, source: source)
                            },
                            favoriteAction: {
                                self.toggleFavorite(item)
                            },
                            continueReadingAction: {
                                self.continueComicReading(item)
                            }
                        )
                        // 中文注释：新手引导库页那一步的聚光目标：只有第一张封面登记（Onboarding-Design.md 第四节）。
                        .spotlightTarget(.libraryFirstCover, isActive: item.id == self.items.first?.id)
                    }
                }

                self.paginationSentinel(prefix: "comic")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            self.paginationFooter
        }
    }

    /// 书脊列表：一行一本，行间分隔线从文字左缘起（缩进 72），最后一行没有（第四、五节）。
    private var bookList: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: self.bookListColumns, spacing: 0) {
                ForEach(Array(self.items.enumerated()), id: \.element.id) { index, item in
                    if let source: Source = self.sourceForID(item.sourceId) {
                        VStack(spacing: 0) {
                            BookLibraryRowView(
                                item: item,
                                isFavorite: self.favoriteItemIDs.contains(item.id),
                                isAudiobook: self.isAudiobookSource,
                                readToText: self.bookReadToText(item),
                                continueMenuTitle: self.bookContinueMenuTitle(item),
                                imageRequestConfig: self.imageRequestConfig(source),
                                openAction: {
                                    self.openItem(item, source: source)
                                },
                                favoriteAction: {
                                    self.toggleFavorite(item)
                                },
                                continueReadingAction: {
                                    self.continueBookReading(item)
                                }
                            )
                            // 中文注释：新手引导库页那一步的聚光目标：只有第一行登记。
                            .spotlightTarget(.libraryFirstCover, isActive: index == 0)
                            if index < self.items.count - 1 {
                                Divider()
                                    .padding(.leading, 72)
                            }
                        }
                    }
                }

                self.paginationSentinel(prefix: "book")
            }
            .padding(.horizontal, self.horizontalSizeClass == .regular ? 40 : 20)
            .padding(.top, 12)

            self.paginationFooter
        }
    }

    /// 中文注释：漫画 / 书的条目点开：先记 `content_opened`，再交给外层分流到详情。
    private func openItem(_ item: ContentItem, source: Source) {
        let kind: AnalyticsContentKind = source.configuration.kind == .book && self.isAudiobookSource
            ? .audiobook
            : AnalyticsContentKind(source: source)
        AppAnalytics.shared.logContentOpened(source: source, kind: kind, entry: self.contentOpenEntry)
        self.openComic(item, source)
    }

    /// 中文注释：触底哨兵与影视网格同形——只有 ViewModel 报出下一页时才挂上，
    /// 出现在视口即请求下一页；`id` 绑定页码，翻页后哨兵换新才会再次触发。
    @ViewBuilder
    private func paginationSentinel(prefix: String) -> some View {
        if let nextPage: Int = self.nextPage,
           let selectedSource: Source = self.selectedSource {
            Color.clear
                .frame(height: 1)
                .id("\(prefix)-pagination-\(selectedSource.id)-\(nextPage)")
                .onAppear {
                    self.loadNextPage()
                }
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if let paginationStatusText: String = self.paginationStatusText {
            LibraryPaginationFooterView(
                statusText: paginationStatusText,
                failureDetail: self.paginationFailureDetail,
                isLoading: self.isLoadingNextPage,
                reportAction: self.reportPaginationFailure
            )
        }
    }
}

/// 分页脚：网格下方一行居中小字——加载中转圈 +「第 2 页 · 正在加载下一页」、还有下一页、已加载到底；
/// 翻页失败时这一行换警示色「第 N 页 · 加载失败，再滑到底重试」，下面一行小字写原因（2026-10-10 裁定：不弹框、不出横幅，重试仍是触底手势）。
struct LibraryPaginationFooterView: View {
    let statusText: String
    var failureDetail: String? = nil
    let isLoading: Bool
    /// 中文注释：翻页失败时失败文案后的「报告问题」小字链接（Problem-Report-Design.md 第三节）；只在有失败原因时出现。
    var reportAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 2) {
            self.statusContent
            if self.failureDetail != nil, let reportAction: () -> Void = self.reportAction {
                ProblemReportLink(action: reportAction)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var statusContent: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                if self.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(self.statusText)
                    .font(.footnote)
                    .foregroundStyle(self.failureDetail == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(CatalogPalette.warning))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            if let failureDetail: String = self.failureDetail {
                Text(failureDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
