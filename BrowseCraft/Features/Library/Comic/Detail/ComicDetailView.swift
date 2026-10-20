import BrowseCraftDomain
import BrowseCraftLog
import SwiftUI

// 中文注释：漫画详情与章节页（`docs/design/Comic-Detail-Page-Redesign-Design.md`）：
// 漫画类型色淡底头部（封面 + 标题 / 作者 / 徽章 / 更新行 / 来源行）→ 标签条 → 继续阅读（卡片或按钮）→ 简介
// → 贴顶的章节分区头（计数、已读、正序 / 倒序、分段芯片）→ 三列网格或行列表。每一块都是有数据才出。
// 只有章节选择后才创建 Reader。
struct ComicDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ComicDetailViewModel
    /// 中文注释：阅读器目标与埋点入口放在同一个值里。分开两个 @State 时，同一次更新里写入的入口
    /// 在 navigationDestination 构造阅读器时还读不到新值（模拟器走查 `reader_opened` 报错入口）。
    @State private var selectedReaderRoute: ComicReaderRoute?
    /// 中文注释：本次打开阅读器的埋点入口（开始阅读 / 继续卡片 / 章节列表），随目的地一起定。
    @State private var readerOpenEntry: ReaderOpenEntry = .chapterList
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var chapterHeaderHeight: CGFloat = 0
    /// 中文注释：报告问题面板（Problem-Report-Design.md 第三、四节）；发送用例未注入时不出入口。
    @Environment(\.problemReportSubmitter) private var problemReportSubmitter: SubmitProblemReportUseCase?
    @State private var problemReportContext: ProblemReportContext?

    let contentViewModelFactory: LibraryContentViewModelFactory

    init(
        item: ContentItem,
        source: Source,
        factory: LibraryContentViewModelFactory
    ) {
        self._viewModel = State(
            wrappedValue: factory.makeComicDetail(item, source)
        )
        self.contentViewModelFactory = factory
    }

    private var style: CatalogKindStyle {
        return CatalogKindStyle.of(CatalogSourceKind.comic)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                // 中文注释：头部与继续阅读随内容滚走；章节分区头是 pinned 分区头，滚到顶时留在顶部（第四节）。
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ComicDetailHeaderSection(
                        viewModel: self.viewModel,
                        style: self.style,
                        openReaderDestination: self.openReaderDestination
                    )
                    .zIndex(2)

                    Section {
                        ComicDetailChapterSection(
                            viewModel: self.viewModel,
                            style: self.style,
                            selectChapter: { chapter in
                                self.openChapter(chapter, entry: .chapterList)
                            },
                            reportFailure: self.reportFailure
                        )
                    } header: {
                        ComicDetailChapterHeader(viewModel: self.viewModel, style: self.style, reportFailure: self.reportFailure)
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.height
                            } action: { height in
                                self.chapterHeaderHeight = height
                            }
                            .detailPinnedHeaderBackground()
                            .zIndex(1)
                    }
                }
                .padding(.bottom, 32)
            }
            .scrollBounceBehavior(.always)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                self.scrollViewportHeight = height
            }
            .onChange(of: self.viewModel.pendingScrollChapterURL) { _, chapterURL in
                guard let chapterURL: String = chapterURL else {
                    return
                }
                withAnimation(.easeInOut(duration: 0.25)) {
                    scrollProxy.scrollTo(chapterURL, anchor: self.segmentScrollAnchor)
                }
                self.viewModel.didFinishProgrammaticScroll()
            }
        }
        .background(CatalogPalette.pageBackground)
        // 中文注释：返回与收藏固定在安全区顶、不随内容滚走（第五节）；做成安全区 inset 而不是 overlay，
        // 贴顶的章节分区头才会停在按钮下面而不是被按钮盖住（2026-10-08 模拟器实测）。
        .safeAreaInset(edge: .top, spacing: 0) {
            self.topButtons
        }
        .navigationTitle(self.viewModel.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(isPresented: self.readerDestinationPresentedBinding) {
            if let route: ComicReaderRoute = self.selectedReaderRoute {
                self.readerDestination(for: route.destination, entry: route.entry)
            }
        }
        .fullScreenCover(item: self.requestedSourceLoginBinding) { loginState in
            SourceLoginView(
                state: loginState,
                entry: .detail,
                source: self.viewModel.source,
                cancelAction: {
                    self.viewModel.dismissRequestedSourceLogin()
                },
                completeAction: { credential in
                    Task {
                        if let chapter = await self.viewModel.completeRequestedSourceLogin(credential: credential) {
                            self.openChapter(chapter, entry: self.readerOpenEntry)
                        }
                    }
                }
            )
        }
        .task {
            // 中文注释：收藏与历史是本地读取，先于网络详情到位。
            await self.viewModel.reloadFavoriteState()
            await self.viewModel.loadIfNeeded()
        }
        .refreshable {
            await self.viewModel.reload()
        }
        .sheet(item: self.$problemReportContext) { context in
            ProblemReportSheet(context: context) {
                self.problemReportContext = nil
            }
        }
        .analyticsScreen(.comicDetail)
        .onAppear(perform: self.recordAppearance)
    }

    /// 中文注释：分段芯片滚动的落点让出贴顶分区头的高度（与站点书详情 `BookSiteDetailView.segmentScrollAnchor` 同一做法），
    /// 段首不被分区头盖住；尺寸还没量到时退回 `.top`。
    private var segmentScrollAnchor: UnitPoint {
        guard self.scrollViewportHeight > 0, self.chapterHeaderHeight > 0 else {
            return .top
        }
        return UnitPoint(x: 0.5, y: min(0.8, (self.chapterHeaderHeight + 4) / self.scrollViewportHeight))
    }

    // MARK: - 固定的返回与收藏

    private var topButtons: some View {
        DetailTopButtons(
            isFavorite: self.viewModel.isFavorite,
            showsFavorite: true,
            accent: self.style.accent,
            backAction: {
                self.dismiss()
            },
            favoriteAction: {
                Task {
                    await self.viewModel.toggleFavorite()
                }
            },
            reportAction: self.problemReportSubmitter == nil ? nil : {
                self.problemReportContext = self.viewModel.problemReportContext(entry: .pageMenu, failureMessage: nil)
            }
        )
    }

    /// 中文注释：失败态入口（横幅与空目录占位）；没有发送用例时为 nil，组件不出链接。
    private var reportFailure: ((String) -> Void)? {
        guard self.problemReportSubmitter != nil else {
            return nil
        }
        return { message in
            self.problemReportContext = self.viewModel.problemReportContext(entry: .failureState, failureMessage: message)
        }
    }

    // MARK: - 绑定

    private var readerDestinationPresentedBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.selectedReaderRoute != nil
            },
            set: { newValue in
                if newValue == false {
                    self.selectedReaderRoute = nil
                    // 中文注释：阅读器返回后重读历史，继续卡片与已读 / 上次读到标记跟着换（第六节）。
                    self.reloadHistoriesAfterReader()
                }
            }
        )
    }

    private var requestedSourceLoginBinding: Binding<LibrarySourceLoginState?> {
        return Binding<LibrarySourceLoginState?>(
            get: { self.viewModel.requestedSourceLogin },
            set: { loginState in
                if loginState == nil {
                    self.viewModel.dismissRequestedSourceLogin()
                }
            }
        )
    }

    // MARK: - 打开阅读器

    private func openReaderDestination(_ destination: ComicReaderDestination) {
        switch destination {
        case .chapter(let chapter):
            self.openChapter(chapter, entry: .detailStart)
        case .history:
            self.readerOpenEntry = .detailContinue
            self.selectedReaderRoute = ComicReaderRoute(destination: destination, entry: .detailContinue)
        }
    }

    private func openChapter(_ chapter: ChapterLink, entry: ReaderOpenEntry) {
        // 中文注释：先记入口：章节要登录时，登录完成后的重开沿用这个入口。
        self.readerOpenEntry = entry
        guard self.viewModel.prepareToOpen(chapter) else {
            return
        }
        var selectedChapter: ChapterLink = chapter
        selectedChapter.navigationChapterURLs = self.viewModel.chapters.map(\.url)
        selectedChapter.navigationChapterTitles = self.viewModel.chapters.map(\.title)
        selectedChapter.navigationOrder = self.viewModel.readerNavigationOrder
        self.selectedReaderRoute = ComicReaderRoute(destination: .chapter(selectedChapter), entry: entry)

        #if DEBUG
        AppLog.debug(.app, "navigation-select-comic-detail-chapter", [
            "itemId": .text("\(self.viewModel.item.id)"),
            "chapterTitle": .text("\(chapter.title)"),
            "chapterURL": .text("\(chapter.url)")
        ])
        #endif
    }

    @ViewBuilder
    private func readerDestination(for destination: ComicReaderDestination, entry: ReaderOpenEntry) -> some View {
        switch destination {
        case .chapter(let chapter):
            ReaderView(
                item: self.viewModel.item,
                source: self.viewModel.source,
                selectedChapter: chapter,
                entry: entry,
                factory: self.contentViewModelFactory
            )
            .id(self.readerDestinationID(for: destination))
        case .history(let history):
            ReaderView(
                history: history,
                source: self.viewModel.source,
                entry: entry,
                factory: self.contentViewModelFactory
            )
            .id(self.readerDestinationID(for: destination))
        }
    }

    private func readerDestinationID(for destination: ComicReaderDestination) -> String {
        switch destination {
        case .chapter(let chapter):
            return [
                "chapter",
                self.viewModel.source.id,
                self.viewModel.item.id,
                self.viewModel.item.detailURL,
                chapter.url
            ].joined(separator: "|")
        case .history(let history):
            return [
                "history",
                history.id,
                String(history.visitedAt.timeIntervalSinceReferenceDate)
            ].joined(separator: "|")
        }
    }

    /// 中文注释：阅读器是在消失时异步落历史的，详情页回到屏上那一刻可能还没写完（模拟器实测拿到的是旧进度）；
    /// 立刻读一次，稍后再读一次兜底。
    private func reloadHistoriesAfterReader() {
        Task {
            await self.viewModel.reloadChapterHistories()
            try? await Task.sleep(for: .milliseconds(800))
            await self.viewModel.reloadChapterHistories()
        }
    }

    private func recordAppearance() {
        if self.viewModel.didLoad {
            self.reloadHistoriesAfterReader()
        }
        CrashDiagnostics.shared.setSource(self.viewModel.source)
        CrashDiagnostics.shared.setRuleStage(.detail)
    }
}

/// 中文注释：漫画阅读器的跳转目标连同埋点入口。
private struct ComicReaderRoute: Hashable {
    let destination: ComicReaderDestination
    let entry: ReaderOpenEntry
}
