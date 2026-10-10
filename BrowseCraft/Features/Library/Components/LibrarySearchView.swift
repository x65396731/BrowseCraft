import BrowseCraftDomain
import SwiftUI

/// 中文注释：来源内搜索页（`docs/design/Search-Page-Redesign-Design.md`）。库页左上搜索圆按钮以 sheet 弹出，三种类型共用。
/// 外壳自绘：眉行「类型 · 来源名」+「搜索」+ 圆形关闭、卡片底搜索框（聚焦类型色描边）、结果眉行、四种状态；
/// 结果网格复用分类页同一套（按来源 kind 分流），点开条目走同一条详情链，收藏与历史也和分类页得到的条目完全一样。
///
/// 2026-09-13 真机逮到：这里此前写死 `VideoContentGridView`，漫画来源的搜索结果被当成影视条目，
/// 点开章节走 `VideoDetailViewModel` → 「Selected source does not expose video playback runtime」。
/// 分类页从来没有这个问题，因为它经 `LibraryContentView` 按 kind 分流到 `ComicLibraryCardView`
/// 与 `ComicDetailView` / `ReaderView`。搜索页现在走同一条。
struct LibrarySearchView: View {
    @Bindable var viewModel: LibraryViewModel
    let contentViewModelFactory: LibraryContentViewModelFactory
    @FocusState private var isKeywordFocused: Bool
    @State private var selectedComicDestination: LibraryComicDestination?
    @State private var selectedSiteBookDestination: LibrarySiteBookDestination?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                self.header
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                self.searchField
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                ScrollView {
                    self.results
                        .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(CatalogPalette.pageBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                // 中文注释：合同第七节——重新打开时有结果就不弹键盘，没有结果才聚焦；
                // 失败横幅在时也不聚焦，键盘会盖住横幅上的「重试」「登录」（2026-10-10 裁定）。
                if self.viewModel.searchResults.isEmpty,
                   self.viewModel.isSearching == false,
                   self.viewModel.searchErrorMessage == nil {
                    self.isKeywordFocused = true
                }
            }
            .navigationDestination(item: self.$selectedComicDestination) { destination in
                self.comicDestination(for: destination.item, source: destination.source)
            }
            .navigationDestination(item: self.$selectedSiteBookDestination) { destination in
                BookSiteDetailView(
                    viewModel: self.contentViewModelFactory.makeBookSiteDetail(destination.item, destination.source),
                    makeReaderViewModel: self.contentViewModelFactory.makeBookSiteReader
                )
                .id(destination.id)
            }
            // 中文注释：登录页挂在 sheet 自己身上——库页的 fullScreenCover 被这张 sheet 盖着，弹不出来。
            .fullScreenCover(item: self.requestedSourceLoginBinding) { loginState in
                SourceLoginView(
                    state: loginState,
                    cancelAction: {
                        self.viewModel.dismissRequestedSourceLogin()
                    },
                    completeAction: { credential in
                        self.viewModel.completeRequestedSourceLogin(credential: credential)
                    }
                )
            }
        }
    }

    // MARK: - 顶行

    private var kindStyle: CatalogKindStyle {
        guard let source: Source = self.viewModel.selectedSource else {
            return CatalogKindStyle.of(CatalogSourceKind.video)
        }
        return CatalogKindStyle.of(source)
    }

    private var sourceName: String {
        return self.viewModel.selectedSource?.name ?? ""
    }

    /// 眉行写「类型 · 来源名」：库页大标题已经是来源名，这里没有大标题位给它（合同第五节）。
    private var eyebrowText: String {
        let title: String = self.viewModel.isAudiobookSource
            ? NSLocalizedString("library_kind_audiobook", comment: "")
            : self.kindStyle.title
        let name: String = self.sourceName
        return name.isEmpty ? title : "\(title) · \(name)"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: self.viewModel.isAudiobookSource ? "headphones" : self.kindStyle.symbolName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(self.kindStyle.accent)
                    .accessibilityHidden(true)
                Text(self.eyebrowText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: 12) {
                Text(NSLocalizedString("Search", comment: ""))
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                self.closeButton
            }
        }
    }

    /// 40pt 圆、卡片底色、headline 图标；热区补到 44（与库页同一个）。
    private var closeButton: some View {
        Button {
            self.viewModel.dismissSearch()
        } label: {
            Image(systemName: "xmark")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(CatalogPalette.cardBackground, in: Circle())
                .shadow(color: CatalogPalette.shadow, radius: 3, y: 1)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("library_search_close", comment: ""))
    }

    // MARK: - 搜索框

    private var placeholderText: String {
        return String(format: NSLocalizedString("library_search_placeholder", comment: ""), self.sourceName)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(self.placeholderText, text: self.$viewModel.searchKeyword)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(self.$isKeywordFocused)
                .onSubmit {
                    // 中文注释：提交后收键盘（合同第五节）；空白关键词由 ViewModel 挡住、不发请求。
                    self.isKeywordFocused = false
                    Task {
                        await self.viewModel.performSearch()
                    }
                }

            if self.viewModel.searchKeyword.isEmpty == false {
                Button {
                    self.viewModel.clearSearch()
                    self.isKeywordFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("library_search_clear", comment: ""))
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, self.viewModel.searchKeyword.isEmpty ? 12 : 0)
        .frame(height: 48)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(self.kindStyle.accent, lineWidth: self.isKeywordFocused ? 1.5 : 0)
        }
    }

    // MARK: - 结果区

    /// 中文注释：与 `LibraryView.comicDestination(for:source:)` 同一分流——只有单章来源直接进阅读器。
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

    private var skeletonLayout: LibrarySkeletonGridView.Layout {
        switch self.viewModel.selectedSource?.configuration.kind {
        case .comic:
            return .comicWall
        case .book:
            return .bookList
        default:
            return .posterWall
        }
    }

    @ViewBuilder
    private var results: some View {
        if self.viewModel.isSearching {
            VStack(alignment: .leading, spacing: 0) {
                self.resultEyebrow(String(format: NSLocalizedString("library_search_searching", comment: ""), self.viewModel.submittedSearchKeyword))
                LibrarySkeletonGridView(layout: self.skeletonLayout)
            }
        } else if let message: String = self.viewModel.searchErrorMessage {
            self.failureBanner(message: message)
        } else if let source: Source = self.viewModel.selectedSource,
                  self.viewModel.searchResults.isEmpty == false {
            VStack(alignment: .leading, spacing: 0) {
                self.resultEyebrow(
                    String(
                        format: NSLocalizedString("library_search_result_count", comment: ""),
                        self.viewModel.submittedSearchKeyword,
                        self.viewModel.searchResults.count
                    )
                )
                LibraryContentView(
                    items: self.viewModel.searchResults,
                    selectedSource: source,
                    favoriteItemIDs: self.viewModel.favoriteItemIDs,
                    sourceForID: self.viewModel.source(for:),
                    toggleFavorite: { item in
                        Task {
                            await self.viewModel.toggleFavorite(item: item)
                        }
                    },
                    openComic: { item, source in
                        #if DEBUG
                        AppDebugLog.write(
                            "[BrowseCraftNavigation] Select Search comic destination " +
                            "itemId=\(item.id) sourceId=\(source.id) title=\(item.title) detailURL=\(item.detailURL)"
                        )
                        #endif
                        // 中文注释：与 `LibraryView.openComicDestination` 同一分流——读书 kind 的搜索结果进站点书详情（2026-09-15 book 搜索接线）。
                        if source.configuration.kind == .book {
                            self.selectedSiteBookDestination = LibrarySiteBookDestination(item: item, source: source)
                            return
                        }
                        self.selectedComicDestination = LibraryComicDestination(item: item, source: source)
                    },
                    primaryActionTitle: self.viewModel.primaryActionTitle(for:),
                    imageRequestConfig: self.viewModel.imageRequestConfig(for:),
                    // 中文注释：搜索结果页的分页由 `searchRules[].pagination` 声明；Runtime 报出下一页才挂触底哨兵。
                    // 当前线上搜索规则都不带分页，所以看不见，但不留死路（合同第六节）。
                    nextPage: self.viewModel.searchNextPage,
                    loadNextPage: {
                        Task {
                            await self.viewModel.loadNextSearchPage()
                        }
                    },
                    contentViewModelFactory: self.contentViewModelFactory,
                    paginationStatusText: self.viewModel.searchPaginationStatusText,
                    isLoadingNextPage: self.viewModel.isLoadingNextSearchPage,
                    // 中文注释：搜索结果与库页同一张卡片、同一行，只读信息照库页给（2026-10-10 裁定）：
                    // 漫画封面上的「读到 4-2」角标、整站有声的耳机与「听」措辞。长按「继续读」仍不接——搜索页不接阅读器。
                    comicProgressBadgeText: self.viewModel.comicProgressBadgeText(for:),
                    isAudiobookSource: self.viewModel.isAudiobookSource
                )
            }
        } else if self.viewModel.hasSearched {
            self.emptyState(
                title: String(format: NSLocalizedString("library_search_no_results", comment: ""), self.viewModel.submittedSearchKeyword),
                message: NSLocalizedString("Try another keyword.", comment: "换个关键词")
            )
        } else {
            self.emptyState(
                title: self.placeholderText,
                message: NSLocalizedString("library_search_idle_message", comment: "搜索提示")
            )
        }
    }

    private func resultEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)
    }

    /// 未搜索与无结果：插画 + 两行字，顶对齐在键盘之上（合同第七节）。不用 `LibraryPlaceholderView`，本页没有下拉刷新。
    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 12) {
            EmptyStateIconView(systemImage: "magnifyingglass", illustration: "EmptyStateSearch", height: 150)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// 失败：共享横幅的失败态 + 「重试」；登录墙且来源有登录页时多一个「登录」（与书详情同一个 `LibraryStateBanner`）。
    private func failureBanner(message: String) -> some View {
        LibraryStateBanner(
            kind: .failure,
            message: message,
            loginAction: self.viewModel.searchFailureNeedsLogin && self.viewModel.selectedSourceLoginState != nil
                ? { self.viewModel.requestSelectedSourceLogin() }
                : nil,
            retryAction: {
                Task {
                    await self.viewModel.retrySearch()
                }
            }
        )
        .padding(.horizontal, 20)
        .padding(.top, 16)
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
