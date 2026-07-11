import SwiftUI

// 中文注释：ReaderView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：ChapterListView 是 struct，负责本模块中的对应职责。
struct ChapterListView: View {
    @ObservedObject var viewModel: ChapterListViewModel
    let readerViewModelFactory: (ContentItem, Source, ChapterLink?) -> ReaderViewModel

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    CoverImageView(
                        urlString: self.viewModel.item.coverURL,
                        refererURLString: self.viewModel.item.detailURL,
                        requestConfig: self.viewModel.detailCoverRequestConfig
                    )
                        .frame(width: 86, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(self.viewModel.item.title)
                            .font(.headline)
                            .lineLimit(3)

                        Text(self.viewModel.source.name)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let latestText: String = self.viewModel.item.latestText {
                            Text(latestText)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.blue)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                if self.viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if self.viewModel.chapters.isEmpty {
                    Text("No Chapters")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(self.viewModel.chapters, id: \.url) { chapter in
                        NavigationLink(
                            destination: ReaderView(
                                viewModel: self.readerViewModelFactory(
                                    self.viewModel.item,
                                    self.viewModel.source,
                                    chapter
                                )
                            ),
                            label: {
                                Text(chapter.title)
                                    .lineLimit(2)
                            }
                        )
                    }
                }
            } header: {
                Text("Chapters")
            }
        }
        .navigationTitle("Chapters")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            CrashDiagnostics.shared.setScreen(.sourceDetail)
            AppAnalytics.shared.logScreenView(.sourceDetail)
            CrashDiagnostics.shared.setSource(self.viewModel.source)
            CrashDiagnostics.shared.setRuleStage(.chapter)
        }
        .task {
            await self.viewModel.load()
        }
        .alert(isPresented: self.errorAlertBinding) {
            Alert(
                title: Text("Chapters"),
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

/// 中文注释：ReaderView 是 struct，负责本模块中的对应职责。
struct ReaderView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @State private var didApplyRestorePage: Bool = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if self.viewModel.isLoading {
                        ProgressView()
                            .padding(.top, 80)
                    }

                    if let chapter: ReaderChapter = self.viewModel.chapter {
                        ForEach(
                            Array(chapter.pageImageURLs.enumerated()),
                            id: \.offset
                        ) { pageIndex, pageURLString in
                            ReaderPageImageView(
                                pageURLString: pageURLString,
                                pageNumber: pageIndex + 1,
                                refererURLString: chapter.chapterURL,
                                requestConfig: self.viewModel.readerImageRequestConfig
                            )
                            .id(pageIndex)
                            .background(
                                ReaderPageVisibilityReporter(
                                    pageIndex: pageIndex,
                                    pageURLString: pageURLString
                                )
                            )
                        }

                        ReaderChapterNavigationBar(
                            previousChapterURL: chapter.previousChapterURL,
                            nextChapterURL: chapter.nextChapterURL,
                            loadPrevious: {
                                await self.viewModel.loadPreviousChapter()
                            },
                            loadNext: {
                                await self.viewModel.loadNextChapter()
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .disabled(self.viewModel.isLoading)
                    }
                }
                .padding(.vertical, 12)
            }
            .onPreferenceChange(ReaderPageVisibilityPreferenceKey.self) { pages in
                if let visiblePage: ReaderPageVisibility = pages.min(by: { lhs, rhs in
                    return lhs.distanceToScreenCenter < rhs.distanceToScreenCenter
                }) {
                    self.viewModel.updateVisiblePage(
                        index: visiblePage.pageIndex,
                        imageURLString: visiblePage.pageURLString
                    )
                }
            }
            .onDisappear {
                self.viewModel.saveCurrentChapterProgress(reason: "reader-disappear")
            }
            .background(Color(.systemBackground))
            .navigationTitle(self.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                CrashDiagnostics.shared.setScreen(.comicReader)
                AppAnalytics.shared.logScreenView(.comicReader)
                CrashDiagnostics.shared.setSource(self.viewModel.diagnosticSource)
                CrashDiagnostics.shared.setRuleStage(.reader)
            }
            .task {
                await self.viewModel.load()
                await self.restoreInitialPageIfNeeded(proxy: proxy)
            }
            .onChange(of: self.viewModel.chapter?.chapterURL) { _, _ in
                Task {
                    await self.scrollToTopForLoadedChapter(proxy: proxy)
                }
            }
        }
        .alert(isPresented: self.errorAlertBinding) {
            Alert(
                title: Text("Reader"),
                message: Text(self.viewModel.errorMessage ?? ""),
                dismissButton: .default(
                    Text("OK"),
                    action: {
                        self.viewModel.errorMessage = nil
                    }
                )
            )
        }
        .handlesRewardedAdPlayback(
            shouldPlayAd: self.viewModel.shouldPlayAd,
            markHandled: {
                self.viewModel.markAdPlaybackHandled()
            }
        )
    }

    @MainActor
    private func scrollToTopForLoadedChapter(proxy: ScrollViewProxy) async {
        // 中文注释：只有“下一章”需要回到新章节顶部；历史恢复页码和上一章都不走这里。
        guard self.viewModel.chapter?.pageImageURLs.isEmpty == false,
              self.viewModel.pendingRestorePageIndex == nil,
              self.viewModel.pendingChapterNavigationDirection == .next else {
            return
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        proxy.scrollTo(0, anchor: .top)
        self.viewModel.markChapterNavigationScrollHandled()
    }

    @MainActor
    private func restoreInitialPageIfNeeded(proxy: ScrollViewProxy) async {
        guard self.didApplyRestorePage == false,
              let pageIndex: Int = self.viewModel.pendingRestorePageIndex,
              let pageCount: Int = self.viewModel.chapter?.pageImageURLs.count,
              pageIndex >= 0,
              pageIndex < pageCount else {
            return
        }

        self.didApplyRestorePage = true
        try? await Task.sleep(nanoseconds: 120_000_000)
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(pageIndex, anchor: .top)
        }
        self.viewModel.markRestorePageApplied()
    }

    private var navigationTitle: String {
        if let chapterTitle: String = self.viewModel.chapter?.chapterTitle {
            return chapterTitle
        }

        return self.viewModel.item.latestText ?? self.viewModel.item.title
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

private struct ReaderPageVisibility: Equatable {
    let pageIndex: Int
    let pageURLString: String
    let distanceToScreenCenter: CGFloat
}

private struct ReaderPageVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: [ReaderPageVisibility] = []

    static func reduce(value: inout [ReaderPageVisibility], nextValue: () -> [ReaderPageVisibility]) {
        value.append(contentsOf: nextValue())
    }
}

private struct ReaderPageVisibilityReporter: View {
    let pageIndex: Int
    let pageURLString: String

    var body: some View {
        GeometryReader { proxy in
            let frame: CGRect = proxy.frame(in: .global)
            let screenCenterY: CGFloat = UIScreen.main.bounds.midY
            let pageCenterY: CGFloat = frame.midY
            Color.clear.preference(
                key: ReaderPageVisibilityPreferenceKey.self,
                value: [
                    ReaderPageVisibility(
                        pageIndex: self.pageIndex,
                        pageURLString: self.pageURLString,
                        distanceToScreenCenter: abs(pageCenterY - screenCenterY)
                    )
                ]
            )
        }
    }
}

private struct ReaderChapterNavigationBar: View {
    let previousChapterURL: String?
    let nextChapterURL: String?
    let loadPrevious: () async -> Void
    let loadNext: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await self.loadPrevious()
                }
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(self.isBlank(self.previousChapterURL))

            Button {
                Task {
                    await self.loadNext()
                }
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(self.isBlank(self.nextChapterURL))
        }
    }

    private func isBlank(_ value: String?) -> Bool {
        guard let value: String = value else {
            return true
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
