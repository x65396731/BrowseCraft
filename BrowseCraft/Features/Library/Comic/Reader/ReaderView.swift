import SwiftUI

// 中文注释：ReaderView 只负责具体章节阅读；漫画作品信息和章节目录位于 Library/Comic/Detail。
/// 中文注释：ReaderView 是 struct，负责本模块中的对应职责。
struct ReaderView: View {
    @StateObject private var viewModel: ReaderViewModel
    @State private var didApplyRestorePage: Bool = false

    init(
        item: ContentItem,
        source: Source,
        selectedChapter: ChapterLink? = nil,
        factory: LibraryContentViewModelFactory
    ) {
        self._viewModel = StateObject(
            wrappedValue: factory.makeReader(item, source, selectedChapter)
        )
    }

    init(
        history: ComicChapterHistory,
        source: Source,
        factory: LibraryContentViewModelFactory
    ) {
        self._viewModel = StateObject(
            wrappedValue: factory.makeHistoryReader(history, source)
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    self.readerContent
                }
            }
            .onPreferenceChange(ReaderPageVisibilityPreferenceKey.self) { visiblePage in
                guard let visiblePage: ReaderPageVisibility else {
                    return
                }
                self.viewModel.updateVisiblePage(
                    index: visiblePage.pageIndex,
                    imageURLString: visiblePage.pageURLString
                )
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
        .alert(item: self.sourceLoginPromptBinding) { prompt in
            Alert(
                title: Text("Login Required"),
                message: Text("This chapter requires a source account. Signing in may not grant access if purchase or VIP membership is also required."),
                primaryButton: .default(
                    Text("Log In"),
                    action: {
                        self.viewModel.requestSourceLogin(state: prompt.state)
                    }
                ),
                secondaryButton: .cancel(
                    Text("Not Now"),
                    action: {
                        self.viewModel.dismissSourceLoginPrompt()
                    }
                )
            )
        }
        .fullScreenCover(item: self.requestedSourceLoginBinding) { loginState in
            SourceLoginView(
                state: loginState,
                cancelAction: {
                    self.viewModel.dismissRequestedSourceLogin()
                },
                completeAction: { credential in
                    Task {
                        await self.viewModel.completeRequestedSourceLogin(credential: credential)
                    }
                }
            )
        }
        .handlesRewardedAdPlayback(
            shouldPlayAd: self.viewModel.shouldPlayAd,
            markHandled: {
                self.viewModel.markAdPlaybackHandled()
            }
        )
    }

    @ViewBuilder
    private var readerContent: some View {
        if self.viewModel.isLoading && self.viewModel.chapter == nil {
            ProgressView()
                .padding(.top, 80)
        } else if let chapter: ReaderChapter = self.viewModel.chapter,
                  chapter.pageResources.isEmpty == false {
            self.readerPages(for: chapter)
        } else if self.viewModel.isLoading {
            ProgressView()
                .padding(.top, 80)
        } else {
            ContentUnavailableView(
                "No Pages",
                systemImage: "photo.on.rectangle.angled",
                description: Text("This chapter did not return any readable pages.")
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 260)
        }
    }

    private var sourceLoginPromptBinding: Binding<ReaderSourceLoginPrompt?> {
        return Binding<ReaderSourceLoginPrompt?>(
            get: {
                return self.viewModel.sourceLoginPrompt
            },
            set: { newValue in
                if newValue == nil {
                    self.viewModel.hideSourceLoginPrompt()
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

    @ViewBuilder
    private func readerPages(for chapter: ReaderChapter) -> some View {
        ForEach(
            chapter.pageResources.indices,
            id: \.self
        ) { pageIndex in
            let resource: ReaderPageResource = chapter.pageResources[pageIndex]
            let pageURLString: String = resource.displayURLString
            ReaderPageImageView(
                resource: resource,
                pageNumber: pageIndex + 1,
                refererURLString: chapter.chapterURL,
                requestConfig: self.viewModel.readerImageRequestConfig,
                additionalHeaders: chapter.pageImageHeaders[pageURLString] ?? [:],
                loadProtectedImage: { reference, targetPixelWidth in
                    try await self.viewModel.loadProtectedImage(
                        reference: reference,
                        targetPixelWidth: targetPixelWidth
                    )
                }
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

    @MainActor
    private func scrollToTopForLoadedChapter(proxy: ScrollViewProxy) async {
        // 中文注释：只有“下一章”需要回到新章节顶部；历史恢复页码和上一章都不走这里。
        guard self.hasReaderPages(self.viewModel.chapter),
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
              let pageCount: Int = self.readerPageCount(self.viewModel.chapter),
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

    private func hasReaderPages(_ chapter: ReaderChapter?) -> Bool {
        guard let chapter: ReaderChapter else {
            return false
        }

        return chapter.pageResources.isEmpty == false
    }

    private func readerPageCount(_ chapter: ReaderChapter?) -> Int? {
        guard let chapter: ReaderChapter else {
            return nil
        }

        return chapter.pageResources.count
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
