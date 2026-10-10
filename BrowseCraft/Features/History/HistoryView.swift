import BrowseCraftCore
import BrowseCraftDomain
import SwiftUI

// 中文注释：HistoryView 是历史页（`docs/design/History-Page-Redesign-Design.md`）：
// 自绘大标题 + 类型筛选，最近一条放大成继续卡片，其余按访问日期分组成封面卡片行；
// 点行接着看，左滑或长按删除这部作品的记录，删除后可撤销。

@MainActor
struct HistoryView: View {
    @Bindable var viewModel: HistoryViewModel
    let contentViewModelFactory: LibraryContentViewModelFactory
    /// 宿主切到库标签（空状态「去库里逛逛」）。
    let openLibrary: () -> Void
    /// 宿主切到该来源并打开库（长按菜单「在库中查看来源」）。
    let openSourceInLibrary: (Source) -> Void
    /// 宿主打开来源页的启用来源窗口（点已暂停来源的历史）。
    let requestSourceActivation: (Source) -> Void

    @State private var path: [ReadingHistoryEntry] = []

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
                .overlay(alignment: .bottom) {
                    if let entry: ReadingHistoryEntry = self.viewModel.undoableEntry {
                        ContentUndoBanner(
                            message: String(format: NSLocalizedString("history_undo_message", comment: ""), entry.title),
                            actionTitle: NSLocalizedString("favorites_undo_action", comment: ""),
                            undoAction: {
                                Task {
                                    await self.viewModel.undoDelete()
                                }
                            }
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: self.viewModel.undoableEntry?.id)
                .onAppear {
                    CrashDiagnostics.shared.setScreen(.history)
                    AppAnalytics.shared.logScreenView(.history)
                    Task {
                        await self.viewModel.load()
                    }
                }
                .onDisappear {
                    self.viewModel.dismissUndo()
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
            self.header(showsCount: true)
                .contentListPageRow(top: 8)

            CatalogSegmentedPicker(
                selection: self.$viewModel.kindFilter,
                segments: self.filterSegments
            )
            .contentListPageRow(top: 16)

            if let continueEntry: ReadingHistoryEntry = self.viewModel.continueEntry {
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
                self.open(entry)
            }
        )
        .contextMenu {
            self.menu(for: entry, state: state)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            // 中文注释：删除不弹确认（可撤销）；不用 destructive 角色，行的移除由数据变化驱动。
            Button {
                self.delete(entry)
            } label: {
                Label(NSLocalizedString("history_delete", comment: ""), systemImage: "trash")
            }
            .tint(CatalogPalette.destructive)
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

    private func header(showsCount: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            Text("History")
                .font(.largeTitle.weight(.heavy))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if showsCount {
                Text(String(format: NSLocalizedString("history_count", comment: ""), self.viewModel.count(for: .all)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }
        }
    }

    // MARK: - 没有历史

    private var emptyContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                self.header(showsCount: false)
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
