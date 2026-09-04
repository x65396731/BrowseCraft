import BrowseCraftDomain
import SwiftUI

// 中文注释：LibraryView 根据当前 SourceRuntimeKind 选择 RSS、视频或漫画展示层。

/// 中文注释：LibraryView 只负责展示 Library 状态，数据加载与切源逻辑在 LibraryViewModel。
struct LibraryView: View {
    @Bindable var viewModel: LibraryViewModel
    let contentViewModelFactory: LibraryContentViewModelFactory
    @State private var selectedComicDestination: LibraryComicDestination?

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
                    self.libraryContent
                }
            }
            .disabled(self.isInteractionLocked)
            .overlay(
                Group {
                    if self.viewModel.isRefreshing &&
                        self.shouldShowLoadingView == false {
                        self.loadingOverlay
                    } else if self.viewModel.isLoadingNextPage {
                        self.loadingInteractionBlocker
                    } else if self.viewModel.items.isEmpty {
                        EmptyStateView(
                            systemImage: self.emptyStateSystemImage,
                            title: self.emptyStateTitle,
                            message: self.emptyStateMessage
                        )
                    }
                }
            )
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
                            .disabled(self.isInteractionLocked)
                            .accessibilityLabel(self.accountAccessibilityLabel(for: loginState.status))
                        } else {
                            Button {
                                self.viewModel.requestSelectedSourceLogin()
                            } label: {
                                Image(systemName: self.accountSystemImage(for: loginState.status))
                            }
                            .disabled(self.isInteractionLocked)
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
                        self.isInteractionLocked
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

    private var shouldShowLoadingView: Bool {
        return self.viewModel.isShowingSourceLoading
    }

    private var isInteractionLocked: Bool {
        return self.viewModel.isRefreshing || self.viewModel.isLoadingNextPage
    }

    @ViewBuilder
    private var libraryContent: some View {
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
                toggleFavorite: { item in
                    Task {
                        await self.viewModel.toggleFavorite(item: item)
                    }
                },
                openComic: self.openComicDestination(item:source:),
                primaryActionTitle: self.viewModel.primaryActionTitle(for:),
                imageRequestConfig: self.viewModel.imageRequestConfig(for:),
                videoNextPage: self.viewModel.nextListPage,
                videoLoadNextPage: {
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

    private var loadingInteractionBlocker: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
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

        self.selectedComicDestination = LibraryComicDestination(item: item, source: source)
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
