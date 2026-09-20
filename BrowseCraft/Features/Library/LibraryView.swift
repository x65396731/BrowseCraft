import BrowseCraftDomain
import SwiftUI

// 中文注释：LibraryView 根据当前 SourceRuntimeKind 选择视频、漫画或书籍展示层。

/// 中文注释：LibraryView 只负责展示 Library 状态，数据加载与切源逻辑在 LibraryViewModel。
struct LibraryView: View {
    @Bindable var viewModel: LibraryViewModel
    let contentViewModelFactory: LibraryContentViewModelFactory
    /// 中文注释：本地书架不走 Source 分流轴；入口已藏（docs/design/Local-Book-Import-Design.md 第八节），这两个参数留给站点抓取路接线时使用。
    var bookShelfViewModel: BookShelfViewModel? = nil
    var makeBookReaderViewModel: (@MainActor (LocalBook) -> BookReaderViewModel)? = nil
    @State private var selectedComicDestination: LibraryComicDestination?
    @State private var selectedSiteBookDestination: LibrarySiteBookDestination?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LibraryListTabBar(
                    source: self.viewModel.selectedSource,
                    tabs: self.viewModel.listTabStates,
                    isInteractionDisabled: self.isInteractionLocked,
                    selectAction: { tabID in
                        await self.viewModel.selectListTab(id: tabID)
                    }
                )

                ScrollView {
                    self.libraryBody
                        .animation(
                            .easeInOut(duration: 0.2),
                            value: self.viewModel.bodyState
                        )
                }
                // 中文注释：内容不满屏时 ScrollView 默认也回弹，空态和失败态因此同样能下拉。
                // 这里把它显式钉成 `.always`：下拉是这两种状态唯一的重载入口（导航栏刷新按钮已在
                // 9d22cb2 删掉），谁要是改成 `.basedOnSize`，不满屏就不回弹，入口会静默失效。
                .scrollBounceBehavior(.always)
                // 中文注释：顶部拉动刷新当前 tab 的第 1 页。切 tab 不再自动重取之后
                // （取过就一直沿用，不设过期时间），这是用户要新内容的唯一入口。
                // 与底部的触底加载下一页互不相干：那条路走 `loadNextPageIfNeeded`，这条走 replace。
                .refreshable {
                    await self.viewModel.refreshSelectedListTab()
                }
            }
            .disabled(self.isInteractionLocked)
            // 中文注释：只剩切源要遮罩，而且只在旧列表还留在屏上时才有（见 LibraryViewModel.bodyState）。
            // 刷新有系统的下拉刷新控件、翻页有底部分页状态条，都不再另外盖一层。
            .overlay {
                if case .switchingSource(let sourceName) = self.viewModel.bodyState {
                    self.switchingSourceOverlay(sourceName: sourceName)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if self.viewModel.shouldShowPaginationStatus {
                    LibraryPaginationStatusView(
                        statusText: self.viewModel.paginationStatusText
                    )
                }
            }
            .navigationTitle(self.libraryNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: self.$selectedComicDestination) { destination in
                self.comicDestination(
                    for: destination.item,
                    source: destination.source
                )
                .id(destination.id)
            }
            .navigationDestination(for: LibraryBookRoute.self) { route in
                self.bookDestination(for: route)
            }
            .navigationDestination(item: self.$selectedSiteBookDestination) { destination in
                BookSiteDetailView(
                    viewModel: self.contentViewModelFactory.makeBookSiteDetail(destination.item, destination.source),
                    makeReaderViewModel: self.contentViewModelFactory.makeBookSiteReader
                )
                .id(destination.id)
            }
            // 中文注释：本地书架入口按用户 2026-09-14 裁决不对用户暴露（docs/design/Local-Book-Import-Design.md 第八节）；
            // LibraryBookRoute 与阅读器保留给站点抓取路复用，RootView 不再装配 bookShelfViewModel。
            .toolbar {
                // 中文注释：搜索与登录共用左上角一个入口：任一可用就显示菜单，两个都没有就不占位。
                if let loginState: LibrarySourceLoginState = self.viewModel.selectedSourceLoginState,
                   self.viewModel.selectedSourceSupportsSearch == false,
                   loginState.status != .authenticated {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            self.viewModel.requestSelectedSourceLogin()
                        } label: {
                            Image(systemName: self.accountSystemImage(for: loginState.status))
                        }
                        .disabled(self.isInteractionLocked)
                        .accessibilityLabel(self.accountAccessibilityLabel(for: loginState.status))
                    }
                } else if self.viewModel.selectedSourceLoginState != nil
                    || self.viewModel.selectedSourceSupportsSearch {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Menu {
                            if self.viewModel.selectedSourceSupportsSearch {
                                Button {
                                    self.viewModel.presentSearch()
                                } label: {
                                    Label("Search", systemImage: "magnifyingglass")
                                }
                            }
                            if let loginState: LibrarySourceLoginState = self.viewModel.selectedSourceLoginState {
                                Button {
                                    self.viewModel.requestSelectedSourceLogin()
                                } label: {
                                    Label("Open Login Page", systemImage: "person.crop.circle")
                                }
                                if loginState.status == .authenticated {
                                    Button(role: .destructive) {
                                        Task {
                                            await SourceLoginSessionCleaner().clear(state: loginState)
                                            self.viewModel.removeSelectedSourceCredential()
                                            await self.viewModel.refreshSelectedListTab()
                                        }
                                    } label: {
                                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                                    }
                                }
                            }
                        } label: {
                            if let loginState: LibrarySourceLoginState = self.viewModel.selectedSourceLoginState {
                                Image(systemName: self.accountSystemImage(for: loginState.status))
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                        .disabled(self.isInteractionLocked)
                        .accessibilityLabel(
                            self.viewModel.selectedSourceLoginState.map { loginState in
                                self.accountAccessibilityLabel(for: loginState.status)
                            } ?? "Search"
                        )
                    }
                }
            }
            .fullScreenCover(item: self.requestedSourceLoginBinding) { loginState in
                SourceLoginView(
                    state: loginState,
                    cancelAction: {
                        self.viewModel.dismissRequestedSourceLogin()
                    },
                    completeAction: { credential in
                        self.viewModel.completeRequestedSourceLogin(credential: credential)
                        Task {
                            await self.viewModel.refreshSelectedListTab()
                        }
                    }
                )
            }
            .sheet(isPresented: self.searchPresentationBinding) {
                LibrarySearchView(
                    viewModel: self.viewModel,
                    contentViewModelFactory: self.contentViewModelFactory
                )
            }
            .onAppear {
                CrashDiagnostics.shared.setScreen(.library)
                AppAnalytics.shared.logScreenView(.library)
            }
            .task {
                _ = await self.viewModel.loadIfNeeded()
            }
            .alert(isPresented: self.errorAlertBinding) {
                Alert(
                    title: Text("Library"),
                    message: Text(self.viewModel.errorMessage ?? ""),
                    dismissButton: .default(
                        Text("OK"),
                        action: {
                            self.viewModel.errorMessage = nil
                        }
                    )
                )
            }
        }
    }

    private func accountSystemImage(for status: LibrarySourceLoginStatus) -> String {
        switch status {
        case .guest:
            return "person.crop.circle"
        case .authenticated:
            return "person.crop.circle.fill"
        }
    }

    private func accountAccessibilityLabel(for status: LibrarySourceLoginStatus) -> String {
        switch status {
        case .guest:
            return "Guest account"
        case .authenticated:
            return "Signed in account"
        }
    }

    private var isInteractionLocked: Bool {
        // 中文注释：只有切源期间锁交互——那一刻屏上是上一个站点的数据。首屏加载和翻页都不锁：
        // tab 条要保持可点（切走时 `refreshToken` 会把在途结果作废），更要紧的是 `.disabled`
        // 会连 `.refreshable` 一起关掉，而下拉是空态和失败态唯一的重载入口。
        if case .switchingSource = self.viewModel.bodyState {
            return true
        }

        return false
    }

    /// 中文注释：正文按 `bodyState` 一次只出一种版面，不再有第二条 if 链去叠第二块占位。
    @ViewBuilder
    private var libraryBody: some View {
        switch self.viewModel.bodyState {
        case .loadingFirstPage:
            LibrarySkeletonGridView()

        case .empty:
            LibraryPlaceholderView(
                systemImage: "square.grid.2x2",
                title: NSLocalizedString("library_body_empty_title", comment: "库列表空态标题"),
                message: NSLocalizedString("library_body_empty_message", comment: "库列表空态说明"),
                pullHint: NSLocalizedString("library_body_pull_hint", comment: "空态下拉刷新提示")
            )

        case .failed(let message):
            LibraryPlaceholderView(
                systemImage: "exclamationmark.triangle",
                title: NSLocalizedString("library_body_failed_title", comment: "库列表失败态标题"),
                message: message,
                pullHint: NSLocalizedString("library_body_retry_pull_hint", comment: "失败态下拉重试提示")
            )

        case .content, .switchingSource:
            // 中文注释：切源时正文照旧渲染旧列表，由上面那层遮罩盖住。
            self.libraryContent
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        VStack(spacing: 0) {
            // 中文注释：有内容时 tab 报的错走横幅；一条都没有时错误本身就是版面（`.failed`），
            // 不会再和空态各占一块。
            if let selectedListTabErrorMessage: String = self.viewModel.selectedListTabErrorMessage {
                LibraryTabErrorBanner(message: selectedListTabErrorMessage)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            LibraryContentView(
                items: self.viewModel.items,
                selectedSource: self.viewModel.selectedSource,
                favoriteItemIDs: self.viewModel.favoriteItemIDs,
                sourceForID: self.viewModel.source(for:),
                toggleFavorite: { item in
                    Task {
                        await self.viewModel.toggleFavorite(item: item)
                    }
                },
                openComic: self.openComicDestination(item:source:),
                primaryActionTitle: self.viewModel.primaryActionTitle(for:),
                imageRequestConfig: self.viewModel.imageRequestConfig(for:),
                nextPage: self.viewModel.nextListPage,
                loadNextPage: {
                    Task {
                        await self.viewModel.loadNextPageIfNeeded()
                    }
                },
                contentViewModelFactory: self.contentViewModelFactory
            )
        }
    }

    private var libraryNavigationTitle: String {
        return self.viewModel.selectedSource?.name ?? "Library"
    }

    /// 中文注释：source 切换期间遮盖旧列表，避免用户在半切换状态下操作上一站点的数据。
    /// 这是全屏里唯一保留的遮罩：它挡的是旧数据，不是用来表示"正在加载"。
    private func switchingSourceOverlay(sourceName: String) -> some View {
        ZStack {
            Color(.systemBackground)
                .opacity(0.82)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)

                Text(NSLocalizedString("library_switching_source_title", comment: "切换来源标题"))
                    .font(.headline)

                Text(
                    String(
                        format: NSLocalizedString("library_switching_source_message", comment: "切换来源说明"),
                        sourceName
                    )
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 260)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func openComicDestination(item: ContentItem, source: Source) {
        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftNavigation] Select Library comic destination " +
            "itemId=\(item.id) " +
            "sourceId=\(source.id) " +
            "title=\(item.title) " +
            "detailURL=\(item.detailURL)"
        )
        #endif

        // 中文注释：读书 kind 的列表复用漫画网格；点开走站点书详情，不走漫画详情 / 阅读器。
        if source.configuration.kind == .book {
            self.selectedSiteBookDestination = LibrarySiteBookDestination(item: item, source: source)
            return
        }
        self.selectedComicDestination = LibraryComicDestination(item: item, source: source)
    }

    /// 中文注释：本地书的两级目的地都在这里解析（书架 → 某本书），见 LibraryBookRoute 的注释。
    @ViewBuilder
    private func bookDestination(for route: LibraryBookRoute) -> some View {
        switch route {
        case .shelf:
            if let bookShelfViewModel: BookShelfViewModel = self.bookShelfViewModel {
                BookShelfView(viewModel: bookShelfViewModel)
            }
        case .book(let book):
            switch book.format {
            case .epub:
                if let makeBookReaderViewModel: @MainActor (LocalBook) -> BookReaderViewModel = self.makeBookReaderViewModel {
                    BookReaderView(viewModel: makeBookReaderViewModel(book))
                        .id(book.id)
                }
            case .audiobook:
                // 中文注释：有声书播放器在后续批次接入（docs/design/Local-Book-Import-Design.md 第四节）。
                EmptyStateView(
                    systemImage: "headphones",
                    title: NSLocalizedString("Audiobook", comment: "有声书"),
                    message: NSLocalizedString("Audiobook player is coming in a later batch.", comment: "有声书播放器待接入")
                )
                .navigationTitle(book.title)
            }
        }
    }

    @ViewBuilder
    private func comicDestination(for item: ContentItem, source: Source) -> some View {
        if self.viewModel.shouldOpenReaderDirectly(for: source) {
            ReaderView(
                item: item,
                source: source,
                factory: self.contentViewModelFactory
            )
        } else {
            ComicDetailView(
                item: item,
                source: source,
                factory: self.contentViewModelFactory
            )
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.viewModel.errorMessage != nil
            },
            set: { newValue in
                if newValue == false {
                    self.viewModel.errorMessage = nil
                }
            }
        )
    }

    private var searchPresentationBinding: Binding<Bool> {
        return Binding<Bool>(
            get: { self.viewModel.isPresentingSearch },
            set: { isPresented in
                if isPresented == false {
                    self.viewModel.dismissSearch()
                }
            }
        )
    }

    private var requestedSourceLoginBinding: Binding<LibrarySourceLoginState?> {
        return Binding<LibrarySourceLoginState?>(
            get: {
                return self.viewModel.requestedSourceLogin
            },
            set: { newValue in
                if newValue == nil {
                    self.viewModel.dismissRequestedSourceLogin()
                }
            }
        )
    }
}

private struct LibraryPaginationStatusView: View {
    let statusText: String

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            Text(self.statusText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.72))
                )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.clear)
    }
}
