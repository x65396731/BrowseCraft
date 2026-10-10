import BrowseCraftDomain
import SwiftUI

// 中文注释：漫画详情与章节页（`docs/design/Comic-Detail-Page-Redesign-Design.md`）：
// 漫画类型色淡底头部（封面 + 标题 / 作者 / 徽章 / 更新行 / 来源行）→ 标签条 → 继续阅读（卡片或按钮）→ 简介
// → 贴顶的章节分区头（计数、已读、正序 / 倒序、分段芯片）→ 三列网格或行列表。每一块都是有数据才出。
// 只有章节选择后才创建 Reader。
struct ComicDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ComicDetailViewModel
    @State private var selectedReaderDestination: ComicReaderDestination?
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var chapterHeaderHeight: CGFloat = 0

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
                            selectChapter: self.openChapter
                        )
                    } header: {
                        ComicDetailChapterHeader(viewModel: self.viewModel, style: self.style)
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
            if let destination: ComicReaderDestination = self.selectedReaderDestination {
                self.readerDestination(for: destination)
            }
        }
        .fullScreenCover(item: self.requestedSourceLoginBinding) { loginState in
            SourceLoginView(
                state: loginState,
                cancelAction: {
                    self.viewModel.dismissRequestedSourceLogin()
                },
                completeAction: { credential in
                    Task {
                        if let chapter = await self.viewModel.completeRequestedSourceLogin(credential: credential) {
                            self.openChapter(chapter)
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
            }
        )
    }

    // MARK: - 绑定

    private var readerDestinationPresentedBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.selectedReaderDestination != nil
            },
            set: { newValue in
                if newValue == false {
                    self.selectedReaderDestination = nil
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
            self.openChapter(chapter)
        case .history:
            self.selectedReaderDestination = destination
        }
    }

    private func openChapter(_ chapter: ChapterLink) {
        guard self.viewModel.prepareToOpen(chapter) else {
            return
        }
        var selectedChapter: ChapterLink = chapter
        selectedChapter.navigationChapterURLs = self.viewModel.chapters.map(\.url)
        selectedChapter.navigationChapterTitles = self.viewModel.chapters.map(\.title)
        selectedChapter.navigationOrder = self.viewModel.chapterNavigationOrder
        self.selectedReaderDestination = .chapter(selectedChapter)

        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftNavigation] Select comic detail chapter " +
            "itemId=\(self.viewModel.item.id) chapterTitle=\(chapter.title) chapterURL=\(chapter.url)"
        )
        #endif
    }

    @ViewBuilder
    private func readerDestination(for destination: ComicReaderDestination) -> some View {
        switch destination {
        case .chapter(let chapter):
            ReaderView(
                item: self.viewModel.item,
                source: self.viewModel.source,
                selectedChapter: chapter,
                factory: self.contentViewModelFactory
            )
            .id(self.readerDestinationID(for: destination))
        case .history(let history):
            ReaderView(
                history: history,
                source: self.viewModel.source,
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
        CrashDiagnostics.shared.setScreen(.sourceDetail)
        AppAnalytics.shared.logScreenView(.sourceDetail)
        CrashDiagnostics.shared.setSource(self.viewModel.source)
        CrashDiagnostics.shared.setRuleStage(.detail)
    }
}
