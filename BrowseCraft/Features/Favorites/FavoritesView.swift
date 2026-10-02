import BrowseCraftCore
import BrowseCraftDomain
import SwiftUI

// 中文注释：FavoritesView 是独立收藏页（`docs/design/Favorites-Page-Redesign-Design.md`）：
// 自绘大标题 + 类型筛选，下面是按收藏日期分组的封面卡片行；点行进详情，左滑或长按取消收藏，取消后可撤销。

@MainActor
struct FavoritesView: View {
    @Bindable var viewModel: FavoritesViewModel
    @Bindable var cloudSyncViewModel: CloudSyncSettingsViewModel
    let contentViewModelFactory: LibraryContentViewModelFactory
    /// 宿主切到库标签（空状态「去库里逛逛」）。
    let openLibrary: () -> Void
    /// 宿主切到该来源并打开库（长按菜单「在库中查看来源」）。
    let openSourceInLibrary: (Source) -> Void
    /// 宿主打开来源页的启用来源窗口（点已暂停来源的收藏）。
    let requestSourceActivation: (Source) -> Void

    @State private var path: [FavoriteDestination] = []

    var body: some View {
        NavigationStack(path: self.$path) {
            self.content
                .background(CatalogPalette.pageBackground)
                // 中文注释：标题按设计稿画在内容里，系统导航栏只在推入详情时出现；标题仍要设，作为详情页返回按钮的文字。
                .toolbar(.hidden, for: .navigationBar)
                .navigationTitle("Favorites")
                .navigationDestination(for: FavoriteDestination.self) { destination in
                    self.destination(for: destination.item, source: destination.source)
                }
                .overlay(alignment: .bottom) {
                    if let item: FavoriteContentItem = self.viewModel.undoableItem {
                        ContentUndoBanner(
                            message: String(format: NSLocalizedString("favorites_undo_message", comment: ""), item.title),
                            actionTitle: NSLocalizedString("favorites_undo_action", comment: ""),
                            undoAction: {
                                Task {
                                    await self.viewModel.undoUnfavorite()
                                }
                            }
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: self.viewModel.undoableItem?.identity)
                .onAppear {
                    CrashDiagnostics.shared.setScreen(.favorite)
                    AppAnalytics.shared.logScreenView(.favorite)
                    Task {
                        await self.viewModel.load()
                    }
                }
                .onDisappear {
                    self.viewModel.dismissUndo()
                }
                .onChange(of: self.cloudSyncViewModel.contentRevision) { _, _ in
                    Task {
                        await self.viewModel.load()
                    }
                }
                .alert(isPresented: self.errorAlertBinding) {
                    Alert(
                        title: Text("Favorites"),
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
        if self.viewModel.favoriteItems.isEmpty &&
            self.cloudSyncViewModel.initialRestoreState.shouldReplaceEmptyState {
            self.restoreContent
        } else if self.viewModel.favoriteItems.isEmpty {
            self.emptyContent
        } else {
            self.favoriteList
        }
    }

    // MARK: - 列表

    private var favoriteList: some View {
        let groups: [FavoritesViewModel.DayGroup] = self.viewModel.dayGroups
        // 中文注释：用 List 是为了左滑取消收藏；行底色与分隔线关掉，卡片在行内容里自己画。
        return List {
            self.header(showsCount: true)
                .contentListPageRow(top: 8)

            CatalogSegmentedPicker(
                selection: self.$viewModel.kindFilter,
                segments: self.filterSegments
            )
            .contentListPageRow(top: 16)

            if groups.isEmpty {
                self.kindEmptyState
                    .contentListPageRow(top: 72)
            } else {
                ForEach(groups) { group in
                    Text(CatalogDayTitle.text(for: group.day))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                        .contentListPageRow(top: 20, bottom: 8, horizontal: 24)

                    ForEach(Array(group.items.enumerated()), id: \.element.identity) { index, item in
                        self.row(item, isFirst: index == 0, isLast: index == group.items.count - 1)
                    }
                }
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

    private func row(_ item: FavoriteContentItem, isFirst: Bool, isLast: Bool) -> some View {
        let state: FavoritesViewModel.SourceState = self.viewModel.sourceState(for: item)
        return FavoriteEntryRowView(
            item: item,
            sourceName: self.viewModel.sourceName(for: item),
            sourceState: state,
            imageRequestConfig: self.viewModel.imageRequestConfig(for: item),
            isFirst: isFirst,
            isLast: isLast,
            action: {
                self.open(item)
            }
        )
        .contextMenu {
            self.menu(for: item, state: state)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            // 中文注释：取消收藏不弹确认（可撤销）；不用 destructive 角色，行的移除由数据变化驱动。
            Button {
                self.unfavorite(item)
            } label: {
                Label(NSLocalizedString("favorites_unfavorite", comment: ""), systemImage: "heart.slash")
            }
            .tint(CatalogPalette.destructive)
        }
        .contentListPageRow()
    }

    @ViewBuilder
    private func menu(for item: FavoriteContentItem, state: FavoritesViewModel.SourceState) -> some View {
        if state != .unknown {
            Button {
                self.open(item)
            } label: {
                Label(NSLocalizedString("favorites_menu_open", comment: ""), systemImage: "arrow.up.right")
            }
        }
        if (state == .available || state == .paused), let source: Source = self.viewModel.source(for: item) {
            Button {
                self.openSourceInLibrary(source)
            } label: {
                Label(NSLocalizedString("favorites_menu_open_source", comment: ""), systemImage: "square.grid.2x2")
            }
        }
        Divider()
        Button(role: .destructive) {
            self.unfavorite(item)
        } label: {
            Label(NSLocalizedString("favorites_unfavorite", comment: ""), systemImage: "heart.slash")
        }
    }

    private var filterSegments: [CatalogSegmentedPicker<FavoritesViewModel.KindFilter>.Segment] {
        return [
            CatalogSegmentedPicker<FavoritesViewModel.KindFilter>.Segment(
                value: .all,
                title: NSLocalizedString("favorites_filter_all", comment: ""),
                count: self.viewModel.count(for: .all)
            ),
            CatalogSegmentedPicker<FavoritesViewModel.KindFilter>.Segment(
                value: .video,
                title: CatalogKindStyle.of(CatalogSourceKind.video).title,
                count: self.viewModel.count(for: .video)
            ),
            CatalogSegmentedPicker<FavoritesViewModel.KindFilter>.Segment(
                value: .comic,
                title: CatalogKindStyle.of(CatalogSourceKind.comic).title,
                count: self.viewModel.count(for: .comic)
            ),
            CatalogSegmentedPicker<FavoritesViewModel.KindFilter>.Segment(
                value: .book,
                title: CatalogKindStyle.of(CatalogSourceKind.book).title,
                count: self.viewModel.count(for: .book)
            )
        ]
    }

    /// 某个类型没有收藏：小空状态，不用插画。
    private var kindEmptyState: some View {
        let kind: CatalogSourceKind
        switch self.viewModel.kindFilter {
        case .video, .all:
            kind = .video
        case .comic:
            kind = .comic
        case .book:
            kind = .book
        }
        let style: CatalogKindStyle = CatalogKindStyle.of(kind)
        return VStack(spacing: 8) {
            Image(systemName: style.symbolName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(style.accent)
                .frame(width: 56, height: 56)
                .background(CatalogPalette.fillBackground, in: Circle())
                .accessibilityHidden(true)
            Text(String(format: NSLocalizedString("favorites_kind_empty_title", comment: ""), style.title))
                .font(.headline)
            Text(NSLocalizedString("favorites_kind_empty_message", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    private func header(showsCount: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            Text("Favorites")
                .font(.largeTitle.weight(.heavy))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if showsCount {
                Text(String(format: NSLocalizedString("favorites_count", comment: ""), self.viewModel.count(for: .all)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }
        }
    }

    // MARK: - 没有收藏

    private var emptyContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                self.header(showsCount: false)
                    .padding(.top, 8)

                VStack(spacing: 10) {
                    EmptyStateIconView(systemImage: "heart", illustration: "EmptyStateFavorites")
                    Text(NSLocalizedString("favorites_empty_title", comment: ""))
                        .font(.title2.weight(.heavy))
                        .multilineTextAlignment(.center)
                    Text(NSLocalizedString("favorites_empty_message", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.top, 34)

                SourcesEntryCardView(
                    title: NSLocalizedString("favorites_empty_browse_title", comment: ""),
                    message: NSLocalizedString("favorites_empty_browse_message", comment: ""),
                    systemImage: "square.grid.2x2.fill",
                    iconForeground: .white,
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

    // MARK: - iCloud 首次恢复

    /// 与来源页同一张恢复卡片；失败时下拉重试，其余时候下拉重新读本地收藏。
    private var restoreContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                self.header(showsCount: false)
                    .padding(.top, 8)
                CloudSyncInitialRestoreView(state: self.cloudSyncViewModel.initialRestoreState)
                VStack(spacing: 10) {
                    ForEach([0.6, 0.4], id: \.self) { opacity in
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(CatalogPalette.cardBackground)
                            .frame(height: 102)
                            .opacity(opacity)
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .refreshable {
            if case .failed = self.cloudSyncViewModel.initialRestoreState {
                await self.cloudSyncViewModel.retryInitialRestoreIfFailed()
            } else {
                await self.viewModel.load()
            }
        }
    }

    // MARK: - 动作

    private func open(_ item: FavoriteContentItem) {
        switch self.viewModel.sourceState(for: item) {
        case .available, .deleted:
            guard let source: Source = self.viewModel.source(for: item) else {
                return
            }
            self.path.append(FavoriteDestination(item: item, source: source))
        case .paused:
            if let source: Source = self.viewModel.source(for: item) {
                self.requestSourceActivation(source)
            }
        case .unknown:
            return
        }
    }

    private func unfavorite(_ item: FavoriteContentItem) {
        Task {
            await self.viewModel.unfavorite(item)
        }
    }

    @ViewBuilder
    private func destination(for item: FavoriteContentItem, source: Source) -> some View {
        let contentItem: ContentItem = item.contentItem()
        switch item.kind {
        case .book:
            // 中文注释：与 Library 点开站点书同一个详情页（RSS 下线前书籍收藏被记成 rss、点开进的是 RSS 详情）。
            BookSiteDetailView(
                viewModel: self.contentViewModelFactory.makeBookSiteDetail(contentItem, source),
                makeReaderViewModel: self.contentViewModelFactory.makeBookSiteReader
            )
        case .comic:
            ComicDetailView(
                item: contentItem,
                source: source,
                factory: self.contentViewModelFactory
            )
        case .videoNative, .videoWeb:
            VideoDetailView(
                item: contentItem,
                source: source,
                factory: self.contentViewModelFactory
            )
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding<Bool>(
            get: {
                self.viewModel.errorMessage != nil
            },
            set: { newValue in
                if newValue == false {
                    self.viewModel.errorMessage = nil
                }
            }
        )
    }
}

private struct FavoriteDestination: Hashable {
    let item: FavoriteContentItem
    let source: Source
}

/// 收藏卡片行：封面（左下角类型徽标）+ 作品名 / 来源名 / 最新状态 + ›。同一天的行拼成一张圆角 18 的卡片。
private struct FavoriteEntryRowView: View {
    let item: FavoriteContentItem
    let sourceName: String
    let sourceState: FavoritesViewModel.SourceState
    let imageRequestConfig: RequestConfig?
    let isFirst: Bool
    let isLast: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 12) {
                self.cover
                VStack(alignment: .leading, spacing: 3) {
                    Text(self.item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    self.sourceLine
                        .font(.caption)
                        .lineLimit(1)
                    if let latestText: String = self.item.latestText, latestText.isEmpty == false {
                        Text(latestText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if self.sourceState != .unknown {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .opacity(self.isDimmed ? 0.5 : 1)
            .contentCardGroupRow(isFirst: self.isFirst, isLast: self.isLast)
        }
        .buttonStyle(.plain)
    }

    private var isDimmed: Bool {
        return self.sourceState == .deleted || self.sourceState == .unknown
    }

    private var cover: some View {
        return ContentCoverView(
            urlString: self.item.coverURL,
            refererURLString: self.item.detailURL,
            requestConfig: self.imageRequestConfig,
            kind: FavoritesViewModel.catalogKind(of: self.item)
        )
    }

    @ViewBuilder
    private var sourceLine: some View {
        switch self.sourceState {
        case .available, .unknown:
            Text(self.sourceName)
                .foregroundStyle(.secondary)
        case .paused:
            Text(self.sourceName).foregroundStyle(.secondary)
                + Text(NSLocalizedString("favorites_source_paused_suffix", comment: "")).foregroundStyle(CatalogPalette.warning)
        case .deleted:
            Text(self.sourceName + NSLocalizedString("favorites_source_deleted_suffix", comment: ""))
                .foregroundStyle(.secondary)
        }
    }
}
