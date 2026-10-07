import BrowseCraftDomain
import SwiftUI

// 中文注释：LibraryView 根据当前 SourceRuntimeKind 选择视频、漫画或书籍展示层。
// 外壳（眉行与大标题、搜索与账号按钮、贴顶分类条、「上次看到」瓷砖、状态页、切换来源遮罩）三种类型共用，
// 按 `docs/design/Library-Video-Page-Redesign-Design.md` 第三、五、六、七节画；视频网格在 `VideoContentGridView`。

/// 中文注释：LibraryView 只负责展示 Library 状态，数据加载与切源逻辑在 LibraryViewModel。
struct LibraryView: View {
    @Bindable var viewModel: LibraryViewModel
    let contentViewModelFactory: LibraryContentViewModelFactory
    /// 中文注释：本地书架不走 Source 分流轴；入口已藏（docs/design/Local-Book-Import-Design.md 第八节），这两个参数留给站点抓取路接线时使用。
    var bookShelfViewModel: BookShelfViewModel? = nil
    var makeBookReaderViewModel: (@MainActor (LocalBook) -> BookReaderViewModel)? = nil
    @State private var selectedComicDestination: LibraryComicDestination?
    @State private var selectedSiteBookDestination: LibrarySiteBookDestination?
    /// 中文注释：「上次看到」瓷砖长按「打开作品」：用历史里的作品身份进影视详情（选集）。
    @State private var continueWatchingDetailItem: ContentItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                // 中文注释：标题在内容里、随内容滚走；分类条是 pinned 分区头，标题滚走后留在顶部。
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    self.header
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        // 中文注释：标题要压在分类条向上延伸的底色之上（见下面分区头的 background）。
                        .zIndex(2)

                    Section {
                        if self.viewModel.continueWatchingHistory != nil {
                            self.continueWatchingTile
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                        }

                        self.libraryBody
                            .animation(
                                .easeInOut(duration: 0.2),
                                value: self.viewModel.bodyState
                            )
                    } header: {
                        LibraryListTabBar(
                            source: self.viewModel.selectedSource,
                            tabs: self.viewModel.listTabStates,
                            isInteractionDisabled: self.isInteractionLocked,
                            selectAction: { tabID in
                                await self.viewModel.selectListTab(id: tabID)
                            }
                        )
                        // 中文注释：贴顶时分区头停在安全区顶边，状态栏与芯片之间那一截会露出从下面滚过的海报
                        // （2026-10-08 模拟器截图）。底色向上多铺一段把它盖住；静止时这段藏在标题后面——标题 zIndex 更高，
                        // 两者又都是页面底色，看不出来。
                        .background(alignment: .top) {
                            CatalogPalette.pageBackground
                                .frame(height: 160)
                                .offset(y: -160)
                        }
                        .zIndex(1)
                    }
                }
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
            .background(CatalogPalette.pageBackground)
            .disabled(self.isInteractionLocked)
            // 中文注释：只剩切源要遮罩，而且只在旧列表还留在屏上时才有（见 LibraryViewModel.bodyState）。
            // 刷新有系统的下拉刷新控件、翻页有网格底部的分页脚，都不再另外盖一层。
            .overlay {
                if case .switchingSource(let sourceName) = self.viewModel.bodyState {
                    self.switchingSourceOverlay(sourceName: sourceName)
                }
            }
            // 中文注释：标题与两个圆形按钮按设计稿自己画在内容里，系统导航栏只在推入详情时出现；
            // 标题仍要设，作为推入页返回按钮的文字。
            .toolbar(.hidden, for: .navigationBar)
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
            .navigationDestination(item: self.$continueWatchingDetailItem) { item in
                if let source: Source = self.viewModel.selectedSource {
                    VideoDetailView(
                        item: item,
                        source: source,
                        factory: self.contentViewModelFactory
                    )
                    .id(item.id)
                }
            }
            // 中文注释：本地书架入口按用户 2026-09-14 裁决不对用户暴露（docs/design/Local-Book-Import-Design.md 第八节）；
            // LibraryBookRoute 与阅读器保留给站点抓取路复用，RootView 不再装配 bookShelfViewModel。
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
            // 中文注释：「上次看到」瓷砖直接开全屏播放器，与历史页点行同一条路径；看完回来重读一次，瓷砖跟着更新。
            .fullScreenCover(
                item: self.$viewModel.videoPlaybackRoute,
                onDismiss: {
                    self.viewModel.refreshContinueWatching()
                }
            ) { route in
                VideoPlayerHostView(viewModel: route.viewModel)
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
                // 中文注释：从详情 / 播放回到库页、从别的标签切回来，都重读一次本地历史——读取便宜，不等网络。
                self.viewModel.refreshContinueWatching()
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

    // MARK: - 顶部

    /// 眉行「▶ 视频 · 主机名」+ 大标题（来源名）+ 右侧搜索、账号两个圆形按钮，各自只在可用时出现。
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let source: Source = self.viewModel.selectedSource {
                let style: CatalogKindStyle = CatalogKindStyle.of(source)
                HStack(spacing: 5) {
                    Image(systemName: style.symbolName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(style.accent)
                        .accessibilityHidden(true)
                    Text(self.eyebrowText(style: style))
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: 12) {
                Text(self.libraryNavigationTitle)
                    .font(.largeTitle.weight(.heavy))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if self.viewModel.selectedSourceSupportsSearch {
                        self.circleButton(
                            systemImage: "magnifyingglass",
                            label: NSLocalizedString("Search", comment: ""),
                            action: {
                                self.viewModel.presentSearch()
                            }
                        )
                    }
                    if let loginState: LibrarySourceLoginState = self.viewModel.selectedSourceLoginState {
                        self.accountButton(loginState: loginState)
                    }
                }
                .padding(.bottom, 2)
            }
        }
    }

    private func eyebrowText(style: CatalogKindStyle) -> String {
        guard let host: String = self.viewModel.selectedSourceHostText, host.isEmpty == false else {
            return style.title
        }
        return "\(style.title) · \(host)"
    }

    /// 40pt 圆、卡片底色、headline 图标；热区补到 44。
    private func circleButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(CatalogPalette.cardBackground, in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(self.isInteractionLocked)
        .accessibilityLabel(label)
    }

    /// 账号按钮：点了打开登录页；登录后图标实心，长按可退出登录。
    private func accountButton(loginState: LibrarySourceLoginState) -> some View {
        self.circleButton(
            systemImage: self.accountSystemImage(for: loginState.status),
            label: self.accountAccessibilityLabel(for: loginState.status),
            action: {
                self.viewModel.requestSelectedSourceLogin()
            }
        )
        .contextMenu {
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

    // MARK: - 「上次看到」瓷砖

    /// 与历史页继续卡片同一个视图；底行只写时刻，整张瓷砖 = 直接进播放器，长按「继续看」「打开作品」。
    @ViewBuilder
    private var continueWatchingTile: some View {
        if let history: VideoWatchHistory = self.viewModel.continueWatchingHistory,
           let source: Source = self.viewModel.selectedSource {
            HistoryContinueTileView(
                entry: ReadingHistoryEntry(videoHistory: history),
                progressText: self.viewModel.continueWatchingProgressText,
                playbackProgress: self.viewModel.continueWatchingProgress,
                sourceName: source.name,
                sourceState: .available,
                coverURL: history.coverURL?.absoluteString,
                refererURL: (history.detailURL ?? history.playPageURL).absoluteString,
                imageRequestConfig: self.viewModel.imageRequestConfig(for: source),
                metaTextOverride: self.viewModel.continueWatchingTimeText,
                action: {
                    self.viewModel.openContinueWatching()
                }
            )
            .contextMenu {
                Button {
                    self.viewModel.openContinueWatching()
                } label: {
                    Label(NSLocalizedString("history_menu_continue_watching", comment: ""), systemImage: "play.fill")
                }
                if let detailURL: URL = history.detailURL {
                    Button {
                        self.continueWatchingDetailItem = Self.detailItem(for: history, source: source, detailURL: detailURL)
                    } label: {
                        Label(NSLocalizedString("library_tile_open_work", comment: ""), systemImage: "list.bullet.rectangle")
                    }
                }
            }
        }
    }

    /// 中文注释：从历史重建作品身份进详情：`id` 按列表解析器的同一形状拼（`sourceID.video.v2.<idCode 或详情地址>`），
    /// 这样详情页里的收藏状态能对上库页网格里的同一部作品。
    private static func detailItem(for history: VideoWatchHistory, source: Source, detailURL: URL) -> ContentItem {
        let stableID: String = history.vodID.isEmpty ? detailURL.absoluteString : history.vodID
        return ContentItem(
            id: "\(source.id).video.v2.\(stableID)",
            idCode: history.vodID.isEmpty ? nil : history.vodID,
            sourceId: source.id,
            title: history.videoTitle,
            detailURL: detailURL.absoluteString,
            coverURL: history.coverURL?.absoluteString,
            type: .video
        )
    }

    // MARK: - 正文

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
                pullHint: NSLocalizedString("library_body_pull_hint", comment: "空态下拉刷新提示"),
                // 中文注释：视频库自己的空状态插画（举遥控器对着空白银幕）；此前借用搜索页的放大镜。
                illustration: "EmptyStateLibraryVideo"
            )

        case .failed(let message):
            LibraryPlaceholderView(
                systemImage: "exclamationmark.triangle",
                title: NSLocalizedString("library_body_failed_title", comment: "库列表失败态标题"),
                message: message,
                pullHint: NSLocalizedString("library_body_retry_pull_hint", comment: "失败态下拉重试提示"),
                illustration: "EmptyStateOffline"
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
                    .padding(.horizontal, 20)
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
                contentViewModelFactory: self.contentViewModelFactory,
                paginationStatusText: self.viewModel.shouldShowPaginationStatus
                    ? self.viewModel.paginationStatusText
                    : nil,
                isLoadingNextPage: self.viewModel.isLoadingNextPage
            )
        }
    }

    private var libraryNavigationTitle: String {
        return self.viewModel.selectedSource?.name ?? "Library"
    }

    /// 中文注释：source 切换期间遮盖旧列表，避免用户在半切换状态下操作上一站点的数据。
    /// 这是全屏里唯一保留的遮罩：它挡的是旧数据，不是用来表示"正在加载"。卡片与云同步页、网址输入页同一张状态卡。
    private func switchingSourceOverlay(sourceName: String) -> some View {
        ZStack {
            CatalogPalette.pageBackground
                .opacity(0.82)
                .ignoresSafeArea()

            StatusCardView(
                systemImage: "arrow.triangle.2.circlepath",
                title: NSLocalizedString("library_switching_source_title", comment: "切换来源标题"),
                message: String(
                    format: NSLocalizedString("library_switching_source_message", comment: "切换来源说明"),
                    sourceName
                ),
                isInProgress: true
            )
            .frame(maxWidth: 280)
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
