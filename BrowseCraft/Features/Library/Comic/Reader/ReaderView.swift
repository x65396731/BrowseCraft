import BrowseCraftDomain
import SwiftUI

// 中文注释：ReaderView 只负责具体章节阅读；漫画作品信息和章节目录位于 Library/Comic/Detail。
/// 中文注释：漫画阅读器页：按章节逐页加载图片，底部上拉进下一话、顶部下拉回上一话，带阅读进度记录与受限章节的登录墙。
/// 换话的合同见 docs/design/Comic-Reader-Chapter-Swipe-Design.md。
struct ReaderView: View {
    @State private var viewModel: ReaderViewModel
    @State private var pullTracker: ReaderPullTracker = ReaderPullTracker()
    @State private var didApplyRestorePage: Bool = false
    @State private var didOpenContentSuccessfully: Bool = false
    /// 中文注释：`reader_opened` 的入口，首次加载前写进 ViewModel。
    private let entry: ReaderOpenEntry

    init(
        item: ContentItem,
        source: Source,
        selectedChapter: ChapterLink? = nil,
        entry: ReaderOpenEntry = .chapterList,
        factory: LibraryContentViewModelFactory
    ) {
        self._viewModel = State(
            wrappedValue: factory.makeReader(item, source, selectedChapter)
        )
        self.entry = entry
    }

    /// 中文注释：用章节历史打开；默认按历史页点行算，库页「上次读到」瓷砖传 `.continueTile`。
    init(
        history: ComicChapterHistory,
        source: Source,
        entry: ReaderOpenEntry = .history,
        factory: LibraryContentViewModelFactory
    ) {
        self._viewModel = State(
            wrappedValue: factory.makeHistoryReader(history, source)
        )
        self.entry = entry
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                self.chapterScrollView
                    // 中文注释：每一话一个独立的滚动视图：换话时新建，天然从第一页顶端开始，不需要程序滚动。
                    .id(self.viewModel.chapter?.chapterURL ?? "")
            }
            .overlay {
                ReaderPullHintsOverlay(tracker: self.pullTracker) { edge, isArmed in
                    return self.pullHintContent(for: edge, isArmed: isArmed)
                }
            }
            .overlay(alignment: .top) {
                self.switchWaitingBand(for: .top)
            }
            .overlay(alignment: .bottom) {
                self.switchWaitingBand(for: .bottom)
            }
            // 中文注释：失败提示挂在内层、登录提示挂在外层，都用带 actions / message 的写法：
            // 旧的 `Alert` 写法在推入页里弹不出来（库页根视图也挂着一个旧写法的弹框），模拟器实测。
            .alert(Text("Reader"), isPresented: self.errorAlertBinding) {
                Button("OK") {
                    self.viewModel.errorMessage = nil
                }
            } message: {
                Text(self.viewModel.errorMessage ?? "")
            }
            .onPreferenceChange(ReaderPageVisibilityPreferenceKey.self) { visiblePage in
                guard let visiblePage: ReaderPageVisibility else {
                    return
                }
                self.viewModel.updateVisiblePage(
                    index: visiblePage.pageIndex,
                    imageURLString: visiblePage.pageURLString
                )
            }
            .onChange(of: self.viewModel.chapterAwaitingDisplay?.chapterURL) { _, _ in
                self.showLoadedChapterIfIdle()
            }
            .onChange(of: self.viewModel.chapterSwitchDirection) { _, direction in
                // 中文注释：读屏用户看不到贴边浮层，开始换话时读出「正在打开…」。
                guard let direction: ReaderChapterNavigationDirection else {
                    return
                }
                AccessibilityNotification.Announcement(self.waitingText(direction: direction)).post()
            }
            .onChange(of: self.viewModel.chapter?.chapterURL) { _, _ in
                // 中文注释：换上了新的滚动视图，旧视图的拉动状态（包括「按着」）一并清掉。
                self.pullTracker.reset()
                self.pullTracker.phase = .idle
            }
            .onDisappear {
                self.viewModel.saveCurrentChapterProgress(reason: "reader-disappear")
                self.viewModel.reportReaderClosedIfNeeded()
                // 中文注释：登录页、激励广告盖住阅读器也会触发消失，那时不是离开，不取消。
                if self.viewModel.requestedSourceLogin == nil,
                   self.viewModel.shouldPlayAd == false {
                    self.viewModel.cancelChapterSwitch()
                }
            }
            .background(CatalogPalette.plainBackground)
            .navigationTitle(self.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            // 中文注释：阅读时藏起底栏，与 BookReaderView 一致；返回详情页后系统自动恢复。
            .toolbar(.hidden, for: .tabBar)
            .analyticsScreen(.comicReader)
            .onAppear {
                CrashDiagnostics.shared.setSource(self.viewModel.diagnosticSource)
                CrashDiagnostics.shared.setRuleStage(.reader)
            }
            .task {
                self.viewModel.openEntry = self.entry
                await self.viewModel.load()
                guard Task.isCancelled == false else {
                    return
                }
                self.didOpenContentSuccessfully = self.hasReadableChapter
                await self.restoreInitialPageIfNeeded(proxy: proxy)
            }
        }
        .alert(
            Text("Login Required"),
            isPresented: self.sourceLoginPromptPresented,
            presenting: self.viewModel.sourceLoginPrompt
        ) { prompt in
            Button("Log In") {
                self.viewModel.requestSourceLogin(state: prompt.state)
            }
            Button("Not Now", role: .cancel) {
                self.viewModel.dismissSourceLoginPrompt()
            }
        } message: { _ in
            Text("This chapter requires a source account. Signing in may not grant access if purchase or VIP membership is also required.")
        }
        .fullScreenCover(item: self.requestedSourceLoginBinding) { loginState in
            SourceLoginView(
                state: loginState,
                entry: .reader,
                source: self.viewModel.diagnosticSource,
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
        .handlesRewardedAdPlayback(
            shouldPlayAd: self.viewModel.shouldPlayAd,
            trigger: .comic,
            markHandled: { outcome in
                self.viewModel.markAdPlaybackHandled(outcome: outcome)
            }
        )
        .requestsAppReviewAfterSuccessfulContentOpen(
            when: self.didOpenContentSuccessfully && self.viewModel.shouldPlayAd == false
        )
    }

    private var hasReadableChapter: Bool {
        guard let chapter: ReaderChapter = self.viewModel.chapter else {
            return false
        }

        return chapter.pageResources.isEmpty == false
    }

    @ViewBuilder
    private var readerContent: some View {
        if self.viewModel.isLoading && self.viewModel.chapter == nil {
            ProgressView()
                .padding(.top, 80)
        } else if let chapter: ReaderChapter = self.viewModel.chapter,
                  chapter.pageResources.isEmpty == false {
            self.readerPages(for: chapter)
        } else if self.viewModel.isLoading {
            ProgressView()
                .padding(.top, 80)
        } else {
            // 中文注释：本话没有页面或加载失败：顶部下拉是重试本话（守住「重试用下拉」），底部上拉仍进下一话。
            ContentUnavailableView {
                Label(NSLocalizedString("reader_no_pages_title", comment: ""), systemImage: "photo.on.rectangle.angled")
            } description: {
                Text(NSLocalizedString("reader_no_pages_message", comment: ""))
            } actions: {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 20, weight: .semibold))
                    Text(NSLocalizedString("video_detail_pull_retry", comment: ""))
                        .font(.footnote)
                }
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 260)
            // 中文注释：撑满一屏，从说明下方的空白处拉也能触发上拉 / 下拉。
            .containerRelativeFrame(.vertical, alignment: .top)
        }
    }

    private var sourceLoginPromptPresented: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.viewModel.sourceLoginPrompt != nil
            },
            set: { newValue in
                if newValue == false {
                    self.viewModel.hideSourceLoginPrompt()
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

    @ViewBuilder
    private func readerPages(for chapter: ReaderChapter) -> some View {
        ForEach(
            chapter.pageResources.indices,
            id: \.self
        ) { pageIndex in
            let resource: ReaderPageResource = chapter.pageResources[pageIndex]
            let pageURLString: String = resource.displayURLString
            ReaderPageImageView(
                resource: resource,
                pageNumber: pageIndex + 1,
                refererURLString: chapter.chapterURL,
                requestConfig: self.viewModel.readerImageRequestConfig,
                additionalHeaders: chapter.pageImageHeaders[pageURLString] ?? [:],
                loadProtectedImage: { reference, targetPixelWidth in
                    try await self.viewModel.loadProtectedImage(
                        reference: reference,
                        targetPixelWidth: targetPixelWidth
                    )
                }
            )
            .id(pageIndex)
            // 中文注释：读屏用户做不了上拉 / 下拉，在每一页上给「下一话」「上一话」两个操作，能换时才出现。
            .accessibilityActions {
                self.chapterSwitchAccessibilityActions
            }
            .background(
                ReaderPageVisibilityReporter(
                    pageIndex: pageIndex,
                    pageURLString: pageURLString
                )
            )
        }
    }

    /// 中文注释：只有从历史进入恢复上次页码时才主动滚一次：在新视图布局完成后执行，用户已经碰了屏幕就放弃。
    @MainActor
    private func restoreInitialPageIfNeeded(proxy: ScrollViewProxy) async {
        guard self.didApplyRestorePage == false,
              let pageIndex: Int = self.viewModel.pendingRestorePageIndex,
              let pageCount: Int = self.readerPageCount(self.viewModel.chapter),
              pageIndex >= 0,
              pageIndex < pageCount else {
            return
        }

        self.didApplyRestorePage = true
        try? await Task.sleep(nanoseconds: 120_000_000)
        defer {
            self.viewModel.markRestorePageApplied()
        }
        guard self.pullTracker.phase == .idle else {
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(pageIndex, anchor: .top)
        }
    }

    // MARK: - 换话手势

    private var chapterScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                self.readerContent
            }
        }
        // 中文注释：内容不满一屏（没有页面）时也要能拉出顶端与底端。
        .scrollBounceBehavior(.always, axes: .vertical)
        .onScrollGeometryChange(for: ReaderOverscroll.self) { geometry in
            return ReaderOverscroll(geometry: geometry)
        } action: { _, newValue in
            self.pullTracker.overscroll = newValue
            self.updateArmedEdge()
        }
        .onScrollPhaseChange { oldPhase, newPhase in
            self.handleScrollPhaseChange(from: oldPhase, to: newPhase)
        }
    }

    private enum PullAction {
        case switchChapter(ReaderChapterNavigationDirection)
        case retry
    }

    /// 中文注释：首次加载中、重试中、换话进行中两个手势都不响应。
    private var isPullEnabled: Bool {
        return self.viewModel.chapterSwitchDirection == nil && self.viewModel.isLoading == false
    }

    @ViewBuilder
    private var chapterSwitchAccessibilityActions: some View {
        if case .switchChapter = self.pullAction(for: .bottom) {
            Button(NSLocalizedString("reader_swipe_action_next", comment: "读屏操作：进入下一话")) {
                self.viewModel.startChapterSwitch(.next)
            }
        }
        if self.hasReadableChapter, case .switchChapter = self.pullAction(for: .top) {
            Button(NSLocalizedString("reader_swipe_action_previous", comment: "读屏操作：回到上一话")) {
                self.viewModel.startChapterSwitch(.previous)
            }
        }
    }

    private func pullAction(for edge: ReaderPullEdge) -> PullAction? {
        guard self.isPullEnabled else {
            return nil
        }

        if edge == .top, self.hasReadableChapter == false {
            return .retry
        }

        guard case .available = self.viewModel.chapterSwitchAvailability(edge.direction) else {
            return nil
        }

        return .switchChapter(edge.direction)
    }

    /// 中文注释：只在手指按着时判断是否拉过触发距离；惯性滑到头的回弹不算。
    private func updateArmedEdge() {
        guard self.pullTracker.phase == .interacting else {
            return
        }

        let armedEdge: ReaderPullEdge? = [ReaderPullEdge.top, ReaderPullEdge.bottom].first { edge in
            return self.pullTracker.overscroll.distance(edge) >= ReaderPullTracker.triggerDistance
                && self.pullAction(for: edge) != nil
        }
        if armedEdge != self.pullTracker.armedEdge {
            self.pullTracker.armedEdge = armedEdge
        }
    }

    /// 中文注释：松手只记下要换的那一边，等滚动回到静止（回弹停稳）才发起；挂起的新一话也在静止时换上。
    private func handleScrollPhaseChange(from oldPhase: ScrollPhase, to newPhase: ScrollPhase) {
        self.pullTracker.phase = newPhase
        if oldPhase == .interacting, newPhase != .interacting {
            self.pullTracker.releasedEdge = self.pullTracker.armedEdge
            self.pullTracker.armedEdge = nil
        }

        guard newPhase == .idle else {
            return
        }

        if let releasedEdge: ReaderPullEdge = self.pullTracker.releasedEdge {
            self.pullTracker.releasedEdge = nil
            self.performPull(releasedEdge)
        }
        self.showLoadedChapterIfIdle()
    }

    private func performPull(_ edge: ReaderPullEdge) {
        switch self.pullAction(for: edge) {
        case .switchChapter(let direction):
            self.viewModel.startChapterSwitch(direction)
        case .retry:
            Task {
                await self.viewModel.retryCurrentChapter()
            }
        case nil:
            return
        }
    }

    /// 中文注释：新一话取到后等滚动静止再换上，避免用户正在滑时手指下的页面突然换掉。
    private func showLoadedChapterIfIdle() {
        guard self.pullTracker.phase == .idle,
              self.viewModel.chapterAwaitingDisplay != nil else {
            return
        }

        self.pullTracker.reset()
        self.viewModel.showLoadedChapter()
    }

    private func pullHintContent(for edge: ReaderPullEdge, isArmed: Bool) -> ReaderPullHintContent? {
        guard self.isPullEnabled,
              self.viewModel.chapter != nil else {
            return nil
        }

        // 中文注释：没有页面时页内已经写着「下拉重试」，顶部不再叠一行。
        if edge == .top, self.hasReadableChapter == false {
            return nil
        }

        let direction: ReaderChapterNavigationDirection = edge.direction
        switch self.viewModel.chapterSwitchAvailability(direction) {
        case .available(let title):
            if isArmed {
                let key: String = direction == .next ? "reader_swipe_next_release" : "reader_swipe_previous_release"
                return ReaderPullHintContent(text: NSLocalizedString(key, comment: ""), showsChevron: true)
            }
            return ReaderPullHintContent(text: Self.pullText(direction: direction, title: title), showsChevron: true)
        case .boundary:
            let key: String = direction == .next ? "reader_swipe_last_chapter" : "reader_swipe_first_chapter"
            return ReaderPullHintContent(text: NSLocalizedString(key, comment: ""), showsChevron: false)
        case .unavailable:
            return ReaderPullHintContent(
                text: NSLocalizedString("reader_swipe_unavailable", comment: ""),
                showsChevron: false
            )
        }
    }

    private static func pullText(direction: ReaderChapterNavigationDirection, title: String?) -> String {
        switch (direction, title) {
        case (.next, let title?):
            return String(format: NSLocalizedString("reader_swipe_next_hint", comment: "上拉中，%@ 为下一话话名"), title)
        case (.next, nil):
            return NSLocalizedString("reader_swipe_next_hint_plain", comment: "")
        case (.previous, let title?):
            return String(format: NSLocalizedString("reader_swipe_previous_hint", comment: "下拉中，%@ 为上一话话名"), title)
        case (.previous, nil):
            return NSLocalizedString("reader_swipe_previous_hint_plain", comment: "")
        }
    }

    @ViewBuilder
    private func switchWaitingBand(for edge: ReaderPullEdge) -> some View {
        if let direction: ReaderChapterNavigationDirection = self.viewModel.chapterSwitchDirection,
           direction == edge.direction {
            ReaderChapterSwitchWaitingBand(edge: edge, text: self.waitingText(direction: direction))
        }
    }

    private func waitingText(direction: ReaderChapterNavigationDirection) -> String {
        if case .available(let title?) = self.viewModel.chapterSwitchAvailability(direction) {
            return String(format: NSLocalizedString("reader_swipe_opening", comment: "换话中，%@ 为目标话名"), title)
        }

        let key: String = direction == .next ? "reader_swipe_opening_next" : "reader_swipe_opening_previous"
        return NSLocalizedString(key, comment: "")
    }

    private var navigationTitle: String {
        if let chapterTitle: String = self.viewModel.chapter?.chapterTitle {
            return chapterTitle
        }

        return self.viewModel.item.latestText ?? self.viewModel.item.title
    }

    private func readerPageCount(_ chapter: ReaderChapter?) -> Int? {
        guard let chapter: ReaderChapter else {
            return nil
        }

        return chapter.pageResources.count
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
}
