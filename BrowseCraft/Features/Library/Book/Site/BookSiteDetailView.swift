import BrowseCraftDomain
import SwiftUI

// 中文注释：站点书详情页（`docs/design/Book-Detail-Page-Redesign-Design.md`）：页面底色头部（小封面 + 书名 / 作者 / 来源 · 分类 / 章数）
// → 继续卡片或开始按钮 → 简介（有才出）→ 贴顶的章节分区头（章数、正序 / 倒序、分段芯片）→ 编号柱行列表的目录。
// 文字书与有声书同一张页，有声只换措辞与图标。章节用本视图自己的 navigationDestination(item:) 推入阅读器（与 ComicDetailView 同款），
// 不能用 NavigationLink(value:) 走栈根的 LibraryBookRoute：两种推入混用时栈序会变成「库 → 阅读器 → 详情」
//（2026-09-14 模拟器实测，见 docs/design/Book-Kind-Wiring-Design.md 第十二节）。

struct BookSiteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: BookSiteDetailViewModel
    @State private var selectedChapter: SiteBookChapterSelection?
    /// 中文注释：点分段芯片滚到段首时，段首要落在贴顶分区头下面而不是被它盖住（2026-10-09 模拟器实测：点「101–150」停在 103）。
    /// 记下滚动区可见高度与分区头高度，换算成 `scrollTo` 的锚点。
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var chapterHeaderHeight: CGFloat = 0
    private let makeReaderViewModel: @MainActor (SiteBookChapterSelection) -> BookReaderViewModel

    init(
        viewModel: BookSiteDetailViewModel,
        makeReaderViewModel: @escaping @MainActor (SiteBookChapterSelection) -> BookReaderViewModel
    ) {
        self._viewModel = State(wrappedValue: viewModel)
        self.makeReaderViewModel = makeReaderViewModel
    }

    private var style: CatalogKindStyle {
        return CatalogKindStyle.of(CatalogSourceKind.book)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    BookSiteDetailHeaderSection(
                        viewModel: self.viewModel,
                        style: self.style,
                        openSelection: self.open(_:)
                    )
                    .zIndex(2)

                    Section {
                        BookSiteDetailChapterSection(
                            viewModel: self.viewModel,
                            style: self.style,
                            selectChapter: { chapter in
                                self.open(self.viewModel.selection(for: chapter))
                            }
                        )
                    } header: {
                        BookSiteDetailChapterHeader(viewModel: self.viewModel, style: self.style)
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
        // 中文注释：返回与收藏固定在安全区顶、不随内容滚走；做成安全区 inset 而不是 overlay，贴顶的分区头才会停在按钮下面。
        .safeAreaInset(edge: .top, spacing: 0) {
            self.topButtons
        }
        .navigationTitle(self.viewModel.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            CrashDiagnostics.shared.setScreen(.bookDetail)
            AppAnalytics.shared.logScreenView(.bookDetail)
            // 中文注释：收藏是本地读取，先于网络详情到位。
            await self.viewModel.reloadFavoriteState()
            await self.viewModel.loadIfNeeded()
        }
        .navigationDestination(item: self.$selectedChapter) { selection in
            BookReaderView(viewModel: self.makeReaderViewModel(selection))
                .id(selection)
        }
        .fullScreenCover(item: self.requestedSourceLoginBinding) { loginState in
            SourceLoginView(
                state: loginState,
                cancelAction: {
                    self.viewModel.dismissRequestedSourceLogin()
                },
                completeAction: { credential in
                    Task {
                        await self.viewModel.completeRequestedSourceLogin(credential: credential)
                    }
                }
            )
        }
    }

    /// 锚点 y = 分区头高度 / 可见高度：`scrollTo` 让行上同一比例的点对齐到可见区同一比例处，
    /// 行高（48）远小于可见高度，段首就停在分区头正下方。量不到时退回 `.top`。
    private var segmentScrollAnchor: UnitPoint {
        guard self.scrollViewportHeight > 0, self.chapterHeaderHeight > 0 else {
            return .top
        }
        return UnitPoint(x: 0.5, y: min(0.8, (self.chapterHeaderHeight + 4) / self.scrollViewportHeight))
    }

    private func open(_ selection: SiteBookChapterSelection) {
        self.selectedChapter = selection
    }

    // MARK: - 固定的返回与收藏

    private var topButtons: some View {
        DetailTopButtons(
            isFavorite: self.viewModel.isFavorite,
            showsFavorite: self.viewModel.canToggleFavorite,
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

    private var requestedSourceLoginBinding: Binding<LibrarySourceLoginState?> {
        return Binding<LibrarySourceLoginState?>(
            get: { self.viewModel.requestedSourceLogin },
            set: { newValue in
                if newValue == nil {
                    self.viewModel.dismissRequestedSourceLogin()
                }
            }
        )
    }
}
