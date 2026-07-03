import SwiftUI

// 中文注释：LibraryView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：LibraryView 是 struct，负责本模块中的对应职责。
struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let chapterListViewModelFactory: (ContentItem, Source) -> ChapterListViewModel
    let readerViewModelFactory: (ContentItem, Source, ChapterLink?) -> ReaderViewModel
    @State private var didLoadInitialData: Bool = false

    private let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 150), spacing: 14)
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                self.listTabBar

                ScrollView {
                    LazyVGrid(columns: self.gridColumns, spacing: 16) {
                        ForEach(self.viewModel.items, id: \.id) { item in
                            if let source: Source = self.viewModel.source(for: item.sourceId) {
                                ContentCardView(
                                    item: item,
                                    sourceName: source.name,
                                    primaryActionTitle: self.primaryActionTitle(for: source),
                                    primaryActionSystemImage: self.primaryActionSystemImage(for: source),
                                    isFavorite: self.viewModel.favoriteItemIDs.contains(item.id),
                                    favoriteAction: {
                                        self.viewModel.toggleFavorite(item: item)
                                    },
                                    readAction: {
                                        self.viewModel.recordOpened(item: item)
                                    },
                                    readerDestination: self.readerDestination(
                                        for: item,
                                        source: source
                                    ),
                                    imageRequestConfig: source.rule.request(for: self.viewModel.selectedListTab)
                                )
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .disabled(self.viewModel.isRefreshing)
            .overlay(
                Group {
                    if self.viewModel.isRefreshing {
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
                if self.didLoadInitialData == false {
                    self.didLoadInitialData = true
                    self.viewModel.load()
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
                ForEach(self.viewModel.listTabs) { tab in
                    Button(
                        action: {
                            Task {
                                await self.viewModel.selectListTab(tab)
                            }
                        },
                        label: {
                            VStack(spacing: 6) {
                                Text(tab.title)
                                    .font(.headline)
                                    .foregroundColor(
                                        self.viewModel.selectedListTabID == tab.id
                                        ? .primary
                                        : .secondary
                                    )
                                    .lineLimit(1)

                                Capsule()
                                    .fill(
                                        self.viewModel.selectedListTabID == tab.id
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
        if self.shouldOpenReaderDirectly(for: source) {
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

    private func primaryActionTitle(for source: Source) -> String {
        if self.shouldOpenReaderDirectly(for: source) {
            return "Read"
        }

        return "Chapters"
    }

    private func primaryActionSystemImage(for source: Source) -> String {
        if self.shouldOpenReaderDirectly(for: source) {
            return "book"
        }

        return "list.bullet"
    }

    private func shouldOpenReaderDirectly(for source: Source) -> Bool {
        return RuleResolver().resolve(source.rule).treatsDetailURLAsChapter
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
