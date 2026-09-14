import ReadiumShared
import SwiftUI

// 中文注释：BookReaderView 是 EPUB 阅读器页：正文由 Readium Navigator 渲染，工具栏给目录与书签。

struct BookReaderView: View {
    @State private var viewModel: BookReaderViewModel
    @State private var isContentsPresented: Bool = false
    @State private var isBookmarksPresented: Bool = false

    init(viewModel: BookReaderViewModel) {
        self._viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            switch self.viewModel.state {
            case .loading:
                ProgressView()
            case .failed(let message):
                EmptyStateView(systemImage: "exclamationmark.triangle", title: NSLocalizedString("Open failed", comment: "打开失败"), message: message)
            case .ready:
                if self.viewModel.isAudiobook {
                    AudiobookPlayerView(viewModel: self.viewModel)
                        .onAppear { self.viewModel.startAudioPlayback() }
                        .onDisappear { self.viewModel.stopAudioPlayback() }
                } else if let publication: Publication = self.viewModel.publication {
                    EPUBNavigatorRepresentable(
                        publication: publication,
                        initialLocation: self.viewModel.initialLocator,
                        proxy: self.viewModel.navigatorProxy,
                        onLocationChange: { locator in
                            self.viewModel.navigatorDidChangeLocation(locator)
                        },
                        onError: { _ in }
                    )
                    .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .navigationTitle(self.viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    self.isContentsPresented = true
                } label: {
                    Label("Contents", systemImage: "list.bullet")
                }
                .disabled(self.viewModel.tableOfContents.isEmpty)
                Button {
                    self.isBookmarksPresented = true
                } label: {
                    Label("Bookmarks", systemImage: "bookmark")
                }
            }
        }
        .sheet(isPresented: self.$isContentsPresented) {
            NavigationStack {
                List(Array(self.viewModel.tableOfContents.enumerated()), id: \.offset) { _, link in
                    Button {
                        self.isContentsPresented = false
                        Task {
                            await self.viewModel.jump(to: link)
                        }
                    } label: {
                        Text(link.title ?? link.href)
                            .lineLimit(2)
                    }
                }
                .navigationTitle("Contents")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            self.isContentsPresented = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: self.$isBookmarksPresented) {
            NavigationStack {
                List {
                    ForEach(self.viewModel.bookmarks) { bookmark in
                        Button {
                            self.isBookmarksPresented = false
                            Task {
                                await self.viewModel.jump(to: bookmark)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bookmark.title ?? Self.dateFormatter.string(from: bookmark.createdAt))
                                if let snippet: String = bookmark.snippet, snippet.isEmpty == false {
                                    Text(snippet)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index: Int in offsets {
                            self.viewModel.removeBookmark(self.viewModel.bookmarks[index])
                        }
                    }
                }
                .overlay {
                    if self.viewModel.bookmarks.isEmpty {
                        EmptyStateView(systemImage: "bookmark", title: NSLocalizedString("Bookmarks", comment: "书签"), message: NSLocalizedString("Add a bookmark at the current page.", comment: "书签空态"))
                    }
                }
                .navigationTitle("Bookmarks")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            self.isBookmarksPresented = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add Bookmark") {
                            self.viewModel.addBookmarkAtCurrentLocation()
                        }
                        .disabled(self.viewModel.currentLocator == nil)
                    }
                }
            }
        }
        .task {
            await self.viewModel.open()
        }
        .onDisappear {
            self.viewModel.flush()
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
