import BrowseCraftCore
import BrowseCraftDomain
import SwiftUI

// 中文注释：HistoryView 是历史页（`docs/design/History-Page-Redesign-Design.md`）：
// 自绘大标题 + 类型筛选，最近一条放大成继续卡片，其余按访问日期分组成封面卡片行；
// 点行接着看，左滑或长按删除这部作品的记录（没有撤销），标题行「选择」进入选择模式批量删除。

@MainActor
struct HistoryView: View {
    @Bindable var viewModel: HistoryViewModel
    /// 收藏与历史锁定（`docs/design/Content-Lock-Design.md`）：锁着时整页（含推入的阅读器）盖上锁定态。
    let contentLockStore: ContentLockStore
    let contentViewModelFactory: LibraryContentViewModelFactory
    /// 宿主切到库标签（空状态「去库里逛逛」）。
    let openLibrary: () -> Void
    /// 宿主切到该来源并打开库（长按菜单「在库中查看来源」）。
    let openSourceInLibrary: (Source) -> Void
    /// 宿主打开来源页的启用来源窗口（点已暂停来源的历史）。
    let requestSourceActivation: (Source) -> Void

    @State private var path: [ReadingHistoryEntry] = []
    @State private var isConfirmingBatchDelete: Bool = false

    var body: some View {
        NavigationStack(path: self.$path) {
            self.content
                .background(CatalogPalette.pageBackground)
                // 中文注释：标题按设计稿画在内容里，系统导航栏只在推入阅读器时出现；标题仍要设，作为返回按钮的文字。
                .toolbar(.hidden, for: .navigationBar)
                .navigationTitle("History")
                .navigationDestination(for: ReadingHistoryEntry.self) { entry in
                    self.destination(for: entry)
                }
                // 中文注释：选择模式下底栏换成操作栏（设计文档 2.6）；挂在栈里的根页上，推入的阅读器不受影响。
                .toolbar(self.viewModel.isSelecting ? .hidden : .automatic, for: .tabBar)
                .safeAreaInset(edge: .bottom) {
                    if self.viewModel.isSelecting {
                        self.selectionBar
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                    }
                }
                .onAppear {
                    CrashDiagnostics.shared.setScreen(.history)
                    AppAnalytics.shared.logScreenView(.history)
                    Task {
                        await self.viewModel.load()
                    }
                }
                .onDisappear {
                    // 中文注释：切走标签就退出选择模式，不保留勾选。
                    self.viewModel.endSelection()
                }
                .fullScreenCover(item: self.$viewModel.videoPlaybackRoute) { route in
                    VideoPlayerHostView(viewModel: route.viewModel)
                }
                .alert(isPresented: self.errorAlertBinding) {
                    Alert(
                        title: Text("History"),
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
        .accessibilityHidden(self.contentLockStore.isContentHidden)
        .overlay {
            if self.contentLockStore.isContentHidden {
                ContentLockedView(
                    store: self.contentLockStore,
                    pageTitle: "History",
                    title: NSLocalizedString("content_lock_history_title", comment: "历史已锁定"),
                    message: NSLocalizedString("content_lock_history_message", comment: "锁定态说明")
                )
            }
        }
        .onChange(of: self.contentLockStore.isContentHidden) { _, isHidden in
            // 中文注释：被锁定时退出选择模式，不保留勾选。
            if isHidden {
                self.viewModel.endSelection()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if self.viewModel.readingHistoryEntries.isEmpty {
            self.emptyContent
        } else {
            self.historyList
        }
    }

    // MARK: - 列表

    private var historyList: some View {
        let groups: [HistoryViewModel.DayGroup] = self.viewModel.dayGroups
        // 中文注释：用 List 是为了左滑删除；行底色与分隔线关掉，卡片在行内容里自己画。
        return List {
            self.listHeader
                .contentListPageRow(top: 8)

            // 中文注释：选择模式下筛选变淡、不可切换，「全选」只作用于当前筛选。
            CatalogSegmentedPicker(
                selection: self.$viewModel.kindFilter,
                segments: self.filterSegments
            )
            .disabled(self.viewModel.isSelecting)
            .opacity(self.viewModel.isSelecting ? 0.4 : 1)
            .contentListPageRow(top: 16)

            if self.viewModel.isSelecting {
                // 中文注释：选择模式下继续卡片收回列表，作为它那一天的第一行，和其他行一样可选（设计文档 2.6）。
                ForEach(self.viewModel.selectionDayGroups) { group in
                    Text(CatalogDayTitle.text(for: group.day))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                        .contentListPageRow(top: 20, bottom: 8, horizontal: 24)

                    ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                        self.row(entry, isFirst: index == 0, isLast: index == group.entries.count - 1)
                    }
                }
            } else if let continueEntry: ReadingHistoryEntry = self.viewModel.continueEntry {
                self.continueTile(continueEntry)
                    .contentListPageRow(top: 16)

                ForEach(groups) { group in
                    Text(CatalogDayTitle.text(for: group.day))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                        .contentListPageRow(top: 20, bottom: 8, horizontal: 24)

                    ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                        self.row(entry, isFirst: index == 0, isLast: index == group.entries.count - 1)
                    }
                }
            } else {
                self.kindEmptyState
                    .contentListPageRow(top: 72)
            }

            Color.clear
                .frame(height: 24)
                .contentListPageRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .refreshable {
            await self.viewModel.load()
        }
        .alert(
            String(format: NSLocalizedString("history_batch_confirm_title", comment: "删除 N 条记录？"), self.viewModel.selectedCount),
            isPresented: self.$isConfirmingBatchDelete
        ) {
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("history_delete", comment: ""), role: .destructive) {
                Task {
                    await self.viewModel.deleteSelected()
                }
            }
        } message: {
            Text(NSLocalizedString("history_batch_confirm_message", comment: "批量删除的说明"))
        }
    }

    private func continueTile(_ entry: ReadingHistoryEntry) -> some View {
        let state: HistoryViewModel.SourceState = self.viewModel.sourceState(for: entry)
        // 中文注释：继续卡片不支持左滑；长按菜单与列表行相同。
        return HistoryContinueTileView(
            entry: entry,
            progressText: self.viewModel.progressText(for: entry),
            playbackProgress: self.viewModel.playbackProgress(for: entry),
            sourceName: self.viewModel.sourceName(for: entry),
            sourceState: state,
            coverURL: self.viewModel.coverURL(for: entry),
            refererURL: self.viewModel.refererURL(for: entry),
            imageRequestConfig: self.viewModel.imageRequestConfig(for: entry),
            action: {
                self.open(entry)
            }
        )
        .contextMenu {
            self.menu(for: entry, state: state)
        }
    }

    private func row(_ entry: ReadingHistoryEntry, isFirst: Bool, isLast: Bool) -> some View {
        let state: HistoryViewModel.SourceState = self.viewModel.sourceState(for: entry)
        return HistoryEntryRowView(
            entry: entry,
            progressText: self.viewModel.progressText(for: entry),
            playbackProgress: self.viewModel.playbackProgress(for: entry),
            sourceName: self.viewModel.sourceName(for: entry),
            sourceState: state,
            coverURL: self.viewModel.coverURL(for: entry),
            refererURL: self.viewModel.refererURL(for: entry),
            imageRequestConfig: self.viewModel.imageRequestConfig(for: entry),
            isFirst: isFirst,
            isLast: isLast,
            action: {
                if self.viewModel.isSelecting {
                    self.viewModel.toggleSelection(entry)
                } else {
                    self.open(entry)
                }
            },
            selection: self.viewModel.isSelecting ? self.viewModel.isSelected(entry) : nil
        )
        .contextMenu {
            if self.viewModel.isSelecting == false {
                self.menu(for: entry, state: state)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // 中文注释：没有撤销，所以不支持一滑到底，滑开后再点按钮才删除；不弹确认。选择模式下不能左滑。
            // 不用 destructive 角色，行的移除由数据变化驱动。
            if self.viewModel.isSelecting == false {
                Button {
                    self.delete(entry)
                } label: {
                    Label(NSLocalizedString("history_delete", comment: ""), systemImage: "trash")
                }
                .tint(CatalogPalette.destructive)
            }
        }
        .contentListPageRow()
    }

    @ViewBuilder
    private func menu(for entry: ReadingHistoryEntry, state: HistoryViewModel.SourceState) -> some View {
        if state != .unknown {
            Button {
                self.open(entry)
            } label: {
                if HistoryViewModel.catalogKind(of: entry) == .video {
                    Label(NSLocalizedString("history_menu_continue_watching", comment: ""), systemImage: "play.fill")
                } else {
                    Label(NSLocalizedString("history_menu_continue_reading", comment: ""), systemImage: "play.fill")
                }
            }
        }
        if state == .available || state == .paused, let source: Source = self.viewModel.source(for: entry) {
            Button {
                self.openSourceInLibrary(source)
            } label: {
                Label(NSLocalizedString("favorites_menu_open_source", comment: ""), systemImage: "square.grid.2x2")
            }
        }
        Button {
            self.viewModel.beginSelection(preselecting: entry)
        } label: {
            Label(NSLocalizedString("content_selection_select_multiple", comment: "选择多项"), systemImage: "checkmark.circle")
        }
        Divider()
        Button(role: .destructive) {
            self.delete(entry)
        } label: {
            Label(NSLocalizedString("history_menu_delete", comment: ""), systemImage: "trash")
        }
    }

    private var filterSegments: [CatalogSegmentedPicker<HistoryViewModel.KindFilter>.Segment] {
        return [
            CatalogSegmentedPicker<HistoryViewModel.KindFilter>.Segment(
                value: .all,
                title: NSLocalizedString("favorites_filter_all", comment: ""),
                count: self.viewModel.count(for: .all)
            ),
            CatalogSegmentedPicker<HistoryViewModel.KindFilter>.Segment(
                value: .video,
                title: CatalogKindStyle.of(CatalogSourceKind.video).title,
                count: self.viewModel.count(for: .video)
            ),
            CatalogSegmentedPicker<HistoryViewModel.KindFilter>.Segment(
                value: .comic,
                title: CatalogKindStyle.of(CatalogSourceKind.comic).title,
                count: self.viewModel.count(for: .comic)
            ),
            CatalogSegmentedPicker<HistoryViewModel.KindFilter>.Segment(
                value: .book,
                title: CatalogKindStyle.of(CatalogSourceKind.book).title,
                count: self.viewModel.count(for: .book)
            )
        ]
    }

    /// 某个类型没有历史：小空状态，不用插画。
    private var kindEmptyState: some View {
        let kind: CatalogSourceKind
        let title: String
        switch self.viewModel.kindFilter {
        case .video, .all:
            kind = .video
            title = NSLocalizedString("history_kind_empty_title_video", comment: "")
        case .comic:
            kind = .comic
            title = NSLocalizedString("history_kind_empty_title_comic", comment: "")
        case .book:
            kind = .book
            title = NSLocalizedString("history_kind_empty_title_book", comment: "")
        }
        let style: CatalogKindStyle = CatalogKindStyle.of(kind)
        return VStack(spacing: 8) {
            Image(systemName: style.symbolName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(style.accent)
                .frame(width: 56, height: 56)
                .background(CatalogPalette.fillBackground, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(NSLocalizedString("history_kind_empty_message", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    /// 有历史时的标题行：右侧「选择」（当前筛选为空时变灰）；选择模式下标题换成「已选择 N 条」、右侧「完成」。
    private var listHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Group {
                if self.viewModel.isSelecting {
                    Text(String(format: NSLocalizedString("history_selection_title", comment: "已选择 N 条"), self.viewModel.selectedCount))
                } else {
                    Text("History")
                }
            }
            .font(.largeTitle.weight(.heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if self.viewModel.isSelecting {
                ContentHeaderButton(
                    title: NSLocalizedString("content_selection_done", comment: "完成"),
                    style: .prominent,
                    action: {
                        self.viewModel.endSelection()
                    }
                )
            } else {
                ContentHeaderButton(
                    title: NSLocalizedString("content_selection_select", comment: "选择"),
                    action: {
                        self.viewModel.beginSelection()
                    }
                )
                .disabled(self.viewModel.filteredEntries.isEmpty)
            }
        }
    }

    /// 没有历史时的标题行：只有大标题。
    private var titleHeader: some View {
        HStack {
            Text("History")
                .font(.largeTitle.weight(.heavy))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
    }

    /// 选择模式的操作栏：全选 / 全不选、已选数量、红色「删除记录」（点了先弹确认框）。
    private var selectionBar: some View {
        ContentSelectionBar(
            selectAllTitle: self.viewModel.isAllVisibleSelected
                ? NSLocalizedString("content_selection_deselect_all", comment: "全不选")
                : NSLocalizedString("content_selection_select_all", comment: "全选"),
            countText: String(format: NSLocalizedString("history_selection_count", comment: "已选 N 条"), self.viewModel.selectedCount),
            actionTitle: NSLocalizedString("history_menu_delete", comment: ""),
            actionSystemImage: "trash",
            isActionEnabled: self.viewModel.selectedCount > 0,
            selectAllAction: {
                self.viewModel.toggleSelectAll()
            },
            action: {
                self.isConfirmingBatchDelete = true
            }
        )
    }

    // MARK: - 没有历史

    private var emptyContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                self.titleHeader
                    .padding(.top, 8)

                VStack(spacing: 10) {
                    EmptyStateIconView(systemImage: "clock", illustration: "EmptyStateHistory")
                    Text(NSLocalizedString("history_empty_title", comment: ""))
                        .font(.title2.weight(.heavy))
                        .multilineTextAlignment(.center)
                    Text(NSLocalizedString("history_empty_message", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.top, 34)

                SourcesEntryCardView(
                    title: NSLocalizedString("favorites_empty_browse_title", comment: ""),
                    message: NSLocalizedString("history_empty_browse_message", comment: ""),
                    systemImage: "square.grid.2x2.fill",
                    iconForeground: CatalogPalette.onAction,
                    iconBackground: CatalogPalette.addAction,
                    action: self.openLibrary
                )
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        .refreshable {
            await self.viewModel.load()
        }
    }

    // MARK: - 动作

    private func open(_ entry: ReadingHistoryEntry) {
        switch self.viewModel.sourceState(for: entry) {
        case .available, .deleted, .temporary:
            if entry.kind == .video, let history: VideoWatchHistory = entry.videoHistory {
                self.viewModel.openVideoHistory(history)
            } else {
                self.path.append(entry)
            }
        case .paused:
            if let source: Source = self.viewModel.source(for: entry) {
                self.requestSourceActivation(source)
            }
        case .unknown:
            return
        }
    }

    private func delete(_ entry: ReadingHistoryEntry) {
        Task {
            await self.viewModel.delete(entry)
        }
    }

    @ViewBuilder
    private func destination(for entry: ReadingHistoryEntry) -> some View {
        switch entry.kind {
        case .comic:
            if let history: ComicChapterHistory = entry.comicHistory,
               let source: Source = self.viewModel.source(for: history),
               history.lastReaderPageURL != nil || history.chapterURL != nil {
                ReaderView(
                    history: history,
                    source: source,
                    factory: self.contentViewModelFactory
                )
            } else {
                HistoryUnavailableView(message: NSLocalizedString("Missing comic source or chapter URL.", comment: ""))
            }
        case .video:
            HistoryUnavailableView(message: NSLocalizedString("Video history opens with the full-screen player.", comment: ""))
        case .book:
            // 中文注释：与 Library 里点开章节进的是同一个阅读器；不带章节，按续读位置接着读。
            if let history: BookReadingHistory = entry.bookHistory,
               let source: Source = self.viewModel.source(for: history) {
                BookReaderView(
                    viewModel: self.contentViewModelFactory.makeBookSiteReader(
                        SiteBookChapterSelection(history: history, source: source)
                    )
                )
            } else {
                HistoryUnavailableView(message: NSLocalizedString("Missing book source.", comment: ""))
            }
        case .temporary:
            if let history: TemporaryResourceHistory = entry.temporaryHistory {
                TemporaryHistoryDetailView(history: history)
            } else {
                HistoryUnavailableView(message: NSLocalizedString("Missing temporary history.", comment: ""))
            }
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
}
