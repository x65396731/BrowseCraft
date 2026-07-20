import SwiftUI

// 中文注释：LibraryView 根据当前 SourceRuntimeKind 选择 RSS、视频或漫画展示层。

/// 中文注释：LibraryView 只负责展示 Library 状态，数据加载与切源逻辑在 LibraryViewModel。
struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let contentViewModelFactory: LibraryContentViewModelFactory
    @State private var didLoadInitialData: Bool = false
    @State private var selectedComicDestination: LibraryComicDestination?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LibraryListTabBar(
                    source: self.viewModel.selectedSource,
                    tabs: self.viewModel.listTabStates,
                    isInteractionDisabled: self.viewModel.isRefreshing || self.viewModel.isValidatingTabs,
                    isValidating: self.viewModel.isValidatingTabs,
                    selectAction: { tabID in
                        await self.viewModel.selectListTab(id: tabID)
                    }
                )

                ScrollView {
                    if self.shouldShowLoadingView {
                        LibraryLoadingView(
                            title: self.viewModel.loadingTitle,
                            message: self.viewModel.loadingMessage
                        )
                    } else {
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
                            toggleFavorite: self.viewModel.toggleFavorite(item:),
                            openComic: self.openComicDestination(item:source:),
                            primaryActionTitle: self.viewModel.primaryActionTitle(for:),
                            imageRequestConfig: self.viewModel.imageRequestConfig(for:),
                            rssContentDetailViewModelFactory: self.contentViewModelFactory.makeRSSDetail,
                            videoDetailViewModelFactory: self.contentViewModelFactory.makeVideoDetail
                        )
                    }
                }
            }
            .allowsHitTesting(self.viewModel.isRefreshing == false)
            .overlay(
                Group {
                    if self.viewModel.isRefreshing && self.shouldShowLoadingView == false {
                        self.loadingOverlay
                    } else if self.viewModel.items.isEmpty {
                        EmptyStateView(
                            systemImage: self.emptyStateSystemImage,
                            title: self.emptyStateTitle,
                            message: self.emptyStateMessage
                        )
                    }
                }
            )
            .navigationTitle(self.libraryNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: self.$selectedComicDestination) { destination in
                self.comicDestination(
                    for: destination.item,
                    source: destination.source
                )
                .id(destination.id)
            }
            .toolbar {
                if let loginState: LibrarySourceLoginState = self.viewModel.selectedSourceLoginState {
                    ToolbarItem(placement: .navigationBarLeading) {
                        if loginState.status == .authenticated {
                            Menu {
                                Button("Open Login Page") {
                                    self.viewModel.requestSelectedSourceLogin()
                                }

                                Button("Log Out", role: .destructive) {
                                    Task {
                                        await SourceLoginSessionCleaner().clear(state: loginState)
                                        self.viewModel.removeSelectedSourceCredential()
                                        await self.viewModel.refreshSelectedListTab()
                                    }
                                }
                            } label: {
                                Image(systemName: self.accountSystemImage(for: loginState.status))
                            }
                            .disabled(self.viewModel.isRefreshing || self.viewModel.isValidatingTabs)
                            .accessibilityLabel(self.accountAccessibilityLabel(for: loginState.status))
                        } else {
                            Button {
                                self.viewModel.requestSelectedSourceLogin()
                            } label: {
                                Image(systemName: self.accountSystemImage(for: loginState.status))
                            }
                            .disabled(self.viewModel.isRefreshing || self.viewModel.isValidatingTabs)
                            .accessibilityLabel(self.accountAccessibilityLabel(for: loginState.status))
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(
                        action: {
                            Task {
                                await self.viewModel.refreshSelectedListTab()
                            }
                        },
                        label: {
                            if self.viewModel.isRefreshing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    )
                    .disabled(
                        self.viewModel.selectedSource == nil ||
                        self.viewModel.isRefreshing ||
                        self.viewModel.isValidatingTabs
                    )
                    .accessibilityLabel("Refresh Selected Tab")
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
            .onAppear {
                CrashDiagnostics.shared.setScreen(.library)
                AppAnalytics.shared.logScreenView(.library)
                if self.didLoadInitialData == false {
                    self.didLoadInitialData = true
                    Task {
                        await self.viewModel.load()
                    }
                }
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

    private var shouldShowLoadingView: Bool {
        return self.viewModel.isShowingSourceLoading
    }

    private var libraryNavigationTitle: String {
        return self.viewModel.selectedSource?.name ?? "Library"
    }

    private var emptyStateSystemImage: String {
        return self.viewModel.selectedListTabErrorMessage == nil
            ? "square.grid.2x2"
            : "exclamationmark.triangle"
    }

    private var emptyStateTitle: String {
        return self.viewModel.selectedListTabErrorMessage == nil
            ? "No Items"
            : "Tab Failed"
    }

    private var emptyStateMessage: String {
        return self.viewModel.selectedListTabErrorMessage
            ?? "Refresh the selected tab to fill your library."
    }

    private var loadingOverlay: some View {
        ZStack {
            Color(.systemBackground)
                .opacity(0.82)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)

                // 中文注释：source 切换期间遮盖旧列表，避免用户在半切换状态下操作上一站点的数据。
                Text("Loading Source")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func openComicDestination(item: ContentItem, source: Source) {
        #if DEBUG
        print(
            "[BrowseCraftNavigation] Select Library comic destination " +
            "itemId=\(item.id) " +
            "sourceId=\(source.id) " +
            "title=\(item.title) " +
            "detailURL=\(item.detailURL)"
        )
        #endif

        self.selectedComicDestination = LibraryComicDestination(item: item, source: source)
    }

    @ViewBuilder
    private func comicDestination(for item: ContentItem, source: Source) -> some View {
        if self.viewModel.shouldOpenReaderDirectly(for: source) {
            ReaderView(
                viewModel: self.contentViewModelFactory.makeReader(item, source, nil)
            )
        } else {
            ComicDetailView(
                viewModel: self.contentViewModelFactory.makeComicDetail(item, source),
                readerViewModelFactory: self.contentViewModelFactory.makeReader,
                historyReaderViewModelFactory: self.contentViewModelFactory.makeHistoryReader
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
