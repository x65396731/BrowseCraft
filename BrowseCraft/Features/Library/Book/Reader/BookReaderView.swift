import ReadiumShared
import SwiftUI

// 中文注释：BookReaderView 是 EPUB 阅读器页：正文由 Readium Navigator 渲染，工具栏给目录与书签。
// 有声作品走自绘的 `AudiobookPlayerView`（Audiobook-Player-Page-Redesign-Design.md）：隐藏系统导航栏，返回与目录在页面里，没有书签。

struct BookReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: BookReaderViewModel
    @State private var isContentsPresented: Bool = false
    @State private var isBookmarksPresented: Bool = false
    /// 中文注释：打开后才知道是文字书还是有声书；在此之前为 nil，不报页面曝光。
    @State private var resolvedScreen: DiagnosticScreen?
    private let entry: ReaderOpenEntry

    /// 中文注释：`entry` 是埋点入口（`reader_opened` / 有声书 `playback_started`）；默认按历史页打开算。
    init(viewModel: BookReaderViewModel, entry: ReaderOpenEntry = .history) {
        self._viewModel = State(wrappedValue: viewModel)
        self.entry = entry
    }

    var body: some View {
        Group {
            switch self.viewModel.state {
            case .loading:
                if self.viewModel.expectsAudiobook {
                    AudiobookLoadingView(backAction: { self.dismiss() })
                } else {
                    ProgressView()
                }
            case .failed(let message):
                // 中文注释：打开失败：库页同一张「载入失败」插画 + 原因 + 下拉重试（交互约定：重试用下拉），两种阅读页共用。
                ScrollView {
                    LibraryPlaceholderView(
                        systemImage: "exclamationmark.triangle",
                        title: NSLocalizedString("Open failed", comment: "打开失败"),
                        message: message,
                        pullHint: NSLocalizedString("library_body_retry_pull_hint", comment: "失败态下拉重试提示"),
                        illustration: "EmptyStateOffline"
                    )
                }
                .refreshable {
                    await self.viewModel.reopen()
                }
            case .ready:
                if self.viewModel.isAudiobook {
                    AudiobookPlayerView(viewModel: self.viewModel, backAction: { self.dismiss() })
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
        .toolbar(self.showsAudiobookChrome ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            if self.showsAudiobookChrome == false {
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
                        // 中文注释：先按当前列表取出要删的书签，再逐个异步删除；删除后 VM 会重载列表。
                        let bookmarks: [BookBookmark] = offsets.map { self.viewModel.bookmarks[$0] }
                        Task {
                            for bookmark: BookBookmark in bookmarks {
                                await self.viewModel.removeBookmark(bookmark)
                            }
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
                            Task { await self.viewModel.addBookmarkAtCurrentLocation() }
                        }
                        .disabled(self.viewModel.currentLocator == nil)
                    }
                }
            }
        }
        .task {
            // 中文注释：打开前不知道是文字书还是有声书：加载期间只给 Crashlytics 记阅读页，
            // 打开后才按结果报一次页面曝光（有声书只报 audiobook_player，不先报 book_reader）。
            CrashDiagnostics.shared.setScreen(.bookReader)
            self.viewModel.openEntry = self.entry
            await self.viewModel.open()
            guard Task.isCancelled == false else {
                return
            }
            self.resolvedScreen = self.viewModel.isAudiobook ? .audiobookPlayer : .bookReader
        }
        .analyticsScreen(resolving: self.resolvedScreen)
        .onDisappear {
            self.viewModel.flush()
            self.viewModel.reportClosedIfNeeded()
        }
        .handlesRewardedAdPlayback(
            shouldPlayAd: self.viewModel.shouldPlayAd,
            trigger: self.viewModel.isAudiobook ? .audiobook : .book,
            markHandled: { outcome in
                self.viewModel.markAdPlaybackHandled(outcome: outcome)
            }
        )
    }

    /// 中文注释：有声书（以及打开中的整站有声作品）用播放页自己的返回与目录，隐藏系统导航栏与工具栏按钮。
    private var showsAudiobookChrome: Bool {
        switch self.viewModel.state {
        case .ready:
            return self.viewModel.isAudiobook
        case .loading:
            return self.viewModel.expectsAudiobook
        case .failed:
            return false
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
