import SwiftUI

// 中文注释：LibraryView 根据当前 SourceRuntimeKind 选择 RSS、视频或漫画展示层。

/// 中文注释：LibraryView 只负责展示 Library 状态，数据加载与切源逻辑在 LibraryViewModel。
struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let chapterListViewModelFactory: (ContentItem, Source) -> ChapterListViewModel
    let readerViewModelFactory: (ContentItem, Source, ChapterLink?) -> ReaderViewModel
    let rssContentDetailViewModelFactory: (ContentItem, Source) -> RSSContentDetailViewModel
    let videoDetailViewModelFactory: (ContentItem, Source) -> VideoDetailViewModel
    @State private var didLoadInitialData: Bool = false

    private let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 150), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                self.listTabBar

                ScrollView {
                    if self.shouldShowLoadingView {
                        LibraryLoadingView(
                            title: self.viewModel.loadingTitle,
                            message: self.viewModel.loadingMessage
                        )
                    } else {
                        self.libraryContent
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
                            systemImage: "square.grid.2x2",
                            title: "No Items",
                            message: "Refresh the selected tab to fill your library."
                        )
                    }
                }
            )
            .navigationTitle("Library")
            .toolbar {
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
                    .disabled(self.viewModel.selectedSource == nil || self.viewModel.isRefreshing)
                    .accessibilityLabel("Refresh Selected Tab")
                }
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

    private var shouldShowLoadingView: Bool {
        return self.viewModel.isShowingSourceLoading
    }

    @ViewBuilder
    private var libraryContent: some View {
        if let selectedSource: Source = self.viewModel.selectedSource,
           selectedSource.configuration.kind == .rss {
            RSSContentListView(
                items: self.viewModel.items,
                source: selectedSource,
                favoriteItemIDs: self.viewModel.favoriteItemIDs,
                favoriteAction: { item in
                    self.viewModel.toggleFavorite(item: item)
                },
                readAction: { _ in },
                detailViewModelFactory: { item, source in
                    return self.rssContentDetailViewModelFactory(item, source)
                }
            )
        } else if let selectedSource: Source = self.viewModel.selectedSource,
                  selectedSource.configuration.kind == .video {
            VideoContentGridView(
                items: self.viewModel.items,
                source: selectedSource,
                favoriteItemIDs: self.viewModel.favoriteItemIDs,
                favoriteAction: { item in
                    self.viewModel.toggleFavorite(item: item)
                },
                detailViewModelFactory: self.videoDetailViewModelFactory,
                imageRequestConfig: self.viewModel.imageRequestConfig(for: selectedSource)
            )
        } else {
            LazyVGrid(columns: self.gridColumns, spacing: 16) {
                ForEach(self.viewModel.items, id: \.id) { item in
                    if let source: Source = self.viewModel.source(for: item.sourceId) {
                        ComicLibraryCardView(
                            item: item,
                            sourceName: source.name,
                            primaryActionTitle: self.viewModel.primaryActionTitle(for: source),
                            primaryActionSystemImage: self.viewModel.primaryActionSystemImage(for: source),
                            isFavorite: self.viewModel.favoriteItemIDs.contains(item.id),
                            favoriteAction: {
                                self.viewModel.toggleFavorite(item: item)
                            },
                            readAction: {},
                            readerDestination: self.readerDestination(
                                for: item,
                                source: source
                            ),
                            imageRequestConfig: self.viewModel.imageRequestConfig(for: source)
                        )
                    }
                }
            }
            .padding(16)
        }
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

    private var listTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(self.viewModel.listTabStates) { tab in
                    Button(
                        action: {
                            Task {
                                await self.viewModel.selectListTab(id: tab.id)
                            }
                        },
                        label: {
                            VStack(spacing: 6) {
                                Text(tab.title)
                                    .font(.headline)
                                    .foregroundColor(
                                        tab.isSelected
                                        ? .primary
                                        : .secondary
                                    )
                                    .lineLimit(1)

                                Capsule()
                                    .fill(
                                        tab.isSelected
                                        ? Color.primary
                                        : Color.clear
                                    )
                                    .frame(height: 3)
                            }
                            .frame(minWidth: 52)
                            .padding(.vertical, 10)
                        }
                    )
                    .buttonStyle(.plain)
                    .disabled(self.viewModel.isRefreshing)
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func readerDestination(for item: ContentItem, source: Source) -> some View {
        if self.viewModel.shouldOpenReaderDirectly(for: source) {
            ReaderView(
                viewModel: self.readerViewModelFactory(item, source, nil)
            )
        } else {
            ChapterListView(
                viewModel: self.chapterListViewModelFactory(item, source),
                readerViewModelFactory: self.readerViewModelFactory
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
}

private struct LibraryLoadingView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text(self.title)
                .font(.headline)

            Text(self.message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 48)
    }
}
