import SwiftUI

// 中文注释：LibraryView 根据当前 SourceRuntimeKind 选择 Feed 列表或漫画网格展示。

/// 中文注释：LibraryView 只负责展示 Library 状态，数据加载与切源逻辑在 LibraryViewModel。
struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let chapterListViewModelFactory: (ContentItem, Source) -> ChapterListViewModel
    let readerViewModelFactory: (ContentItem, Source, ChapterLink?) -> ReaderViewModel
    let feedContentDetailViewModelFactory: (ContentItem, Source) -> FeedContentDetailViewModel
    @State private var didLoadInitialData: Bool = false

    private let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 150), spacing: 14)
    ]

    var body: some View {
        NavigationView {
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
            FeedContentListView(
                items: self.viewModel.items,
                source: selectedSource,
                favoriteItemIDs: self.viewModel.favoriteItemIDs,
                favoriteAction: { item in
                    self.viewModel.toggleFavorite(item: item)
                },
                readAction: { _ in },
                detailViewModelFactory: { item, source in
                    return self.feedContentDetailViewModelFactory(item, source)
                }
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

private struct FeedContentListView: View {
    let items: [ContentItem]
    let source: Source
    let favoriteItemIDs: Set<String>
    let favoriteAction: (ContentItem) -> Void
    let readAction: (ContentItem) -> Void
    let detailViewModelFactory: (ContentItem, Source) -> FeedContentDetailViewModel

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(self.items, id: \.id) { item in
                NavigationLink(
                    destination: FeedContentDetailView(
                        viewModel: self.detailViewModelFactory(item, self.source)
                    ),
                    label: {
                        FeedContentRowView(
                            item: item,
                            sourceName: self.source.name,
                            isFavorite: self.favoriteItemIDs.contains(item.id),
                            favoriteAction: {
                                self.favoriteAction(item)
                            }
                        )
                    }
                )
                .buttonStyle(.plain)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        #if DEBUG
                        print(
                            "[BrowseCraftNavigation] Tap RSS article " +
                            "itemId=\(item.id) " +
                            "title=\(item.title) " +
                            "detailURL=\(item.detailURL)"
                        )
                        #endif

                        self.readAction(item)
                    }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct FeedContentRowView: View {
    let item: ContentItem
    let sourceName: String
    let isFavorite: Bool
    let favoriteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(self.item.title)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Label(
                            title: {
                                Text("Feed")
                            },
                            icon: {
                                Image(systemName: "doc.text")
                            }
                        )

                        Text(self.sourceName)

                        if let updatedAt: Date = self.item.updatedAt {
                            Text(FeedContentDateFormatter.string(from: updatedAt))
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }

                Button(
                    action: {
                        self.favoriteAction()
                    },
                    label: {
                        Image(systemName: self.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(self.isFavorite ? .yellow : .secondary)
                            .frame(width: 32, height: 32)
                    }
                )
                .buttonStyle(.plain)
                .accessibilityLabel(self.isFavorite ? "Remove Favorite" : "Add Favorite")
            }

            if let summary: String = self.summaryText {
                Text(summary)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Text("Read")
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .font(.callout.weight(.semibold))
            .foregroundColor(.blue)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    private var summaryText: String? {
        return FeedContentTextFormatter.sanitized(self.item.latestText)
    }
}

private struct FeedContentDetailView: View {
    @StateObject private var viewModel: FeedContentDetailViewModel

    init(viewModel: FeedContentDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(self.viewModel.item.title)
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Label(
                        title: {
                            Text(self.viewModel.sourceName)
                        },
                        icon: {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                    )

                    Text("Feed")

                    if let updatedAt: Date = self.viewModel.item.updatedAt {
                        Text(FeedContentDateFormatter.string(from: updatedAt))
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                if let summary: String = FeedContentTextFormatter.sanitized(self.viewModel.item.latestText) {
                    Text(summary)
                        .font(.body)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let url: URL = URL(string: self.viewModel.item.detailURL) {
                    Link(destination: url) {
                        Label("Open Original", systemImage: "safari")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .navigationTitle("Feed")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            self.viewModel.saveReadingHistoryIfNeeded()
        }
    }
}

enum FeedContentTextFormatter {
    static func sanitized(_ text: String?) -> String? {
        guard let text: String = text else {
            return nil
        }

        let withoutTags: String = text.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let decoded: String = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        let collapsed: String = decoded
            .split(whereSeparator: { character in
                return character.isWhitespace
            })
            .joined(separator: " ")

        return collapsed.isEmpty ? nil : collapsed
    }
}

private enum FeedContentDateFormatter {
    static func string(from date: Date) -> String {
        return Self.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
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
