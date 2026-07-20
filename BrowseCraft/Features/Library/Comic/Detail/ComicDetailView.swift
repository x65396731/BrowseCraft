import SwiftUI

/// 中文注释：漫画详情页展示作品信息和章节目录；只有章节选择后才创建 Reader。
struct ComicDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ComicDetailViewModel
    @State private var selectedReaderDestination: ComicReaderDestination?

    let contentViewModelFactory: LibraryContentViewModelFactory

    init(
        item: ContentItem,
        source: Source,
        factory: LibraryContentViewModelFactory
    ) {
        self._viewModel = StateObject(
            wrappedValue: factory.makeComicDetail(item, source)
        )
        self.contentViewModelFactory = factory
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ComicDetailHeroSection(
                    title: self.viewModel.displayTitle,
                    author: self.viewModel.authorText,
                    status: self.viewModel.statusText,
                    category: self.viewModel.categoryText,
                    sourceName: self.viewModel.source.name,
                    coverURLString: self.viewModel.coverURLString,
                    detailURLString: self.viewModel.item.detailURL,
                    requestConfig: self.viewModel.detailCoverRequestConfig
                )

                ComicDetailActionSection(
                    chapterCount: self.viewModel.chapters.count,
                    latestText: self.viewModel.item.latestText,
                    readingTitle: self.primaryReadingButtonTitle,
                    isEnabled: self.viewModel.primaryReadingTarget != nil,
                    startReading: self.startReading
                )

                if self.viewModel.tags.isEmpty == false {
                    ComicDetailTagsSection(tags: self.viewModel.tags)
                }

                if let description: String = self.viewModel.descriptionText {
                    ComicDetailDescriptionSection(description: description)
                }

                if self.viewModel.metadataRows.isEmpty == false || self.viewModel.relatedLinks.isEmpty == false {
                    ComicDetailInformationSection(
                        rows: self.viewModel.metadataRows,
                        links: self.viewModel.relatedLinks
                    )
                }

                ComicDetailChapterSection(
                    chapters: self.viewModel.chapters,
                    isLoading: self.viewModel.isLoading,
                    didLoad: self.viewModel.didLoad,
                    errorMessage: self.viewModel.errorMessage,
                    selectChapter: self.openReaderDestination,
                    retry: self.retry
                )
            }
        }
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea(edges: .top)
        .navigationTitle(self.viewModel.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: self.dismissDetail) {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
        }
        .navigationDestination(isPresented: self.readerDestinationPresentedBinding) {
            if let destination: ComicReaderDestination = self.selectedReaderDestination {
                self.readerDestination(for: destination)
            }
        }
        .alert(isPresented: self.accessAlertBinding) {
            Alert(
                title: Text("Access Required"),
                message: Text(self.viewModel.accessMessage ?? ""),
                dismissButton: .default(Text("OK")) {
                    self.viewModel.accessMessage = nil
                }
            )
        }
        .alert(item: self.sourceLoginPromptBinding) { prompt in
            Alert(
                title: Text("Access Required"),
                message: Text(self.loginPromptMessage(isPaid: prompt.isPaid)),
                primaryButton: .default(Text("Log In")) {
                    self.viewModel.requestSourceLogin(state: prompt.state)
                },
                secondaryButton: .cancel(Text("Not Now")) {
                    self.viewModel.dismissSourceLoginPrompt()
                }
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
                        if let chapter = await self.viewModel.completeRequestedSourceLogin(credential: credential) {
                            self.openReaderDestination(chapter)
                        }
                    }
                }
            )
        }
        .task {
            await self.viewModel.loadIfNeeded()
        }
        .refreshable {
            await self.viewModel.reload()
        }
        .onAppear(perform: self.recordAppearance)
    }

    private var readerDestinationPresentedBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.selectedReaderDestination != nil
            },
            set: { newValue in
                if newValue == false {
                    self.selectedReaderDestination = nil
                }
            }
        )
    }

    private var accessAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: { self.viewModel.accessMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    self.viewModel.accessMessage = nil
                }
            }
        )
    }

    private var sourceLoginPromptBinding: Binding<ComicDetailSourceLoginPrompt?> {
        return Binding<ComicDetailSourceLoginPrompt?>(
            get: { self.viewModel.sourceLoginPrompt },
            set: { prompt in
                if prompt == nil {
                    self.viewModel.hideSourceLoginPrompt()
                }
            }
        )
    }

    private var requestedSourceLoginBinding: Binding<LibrarySourceLoginState?> {
        return Binding<LibrarySourceLoginState?>(
            get: { self.viewModel.requestedSourceLogin },
            set: { loginState in
                if loginState == nil {
                    self.viewModel.dismissRequestedSourceLogin()
                }
            }
        )
    }

    private var primaryReadingButtonTitle: String {
        guard let target: ComicReaderDestination = self.viewModel.primaryReadingTarget else {
            return "Read Latest"
        }
        switch target {
        case .chapter(let chapter):
            return "Read Latest · \(chapter.title)"
        case .history(let history):
            return "Continue Reading · \(history.chapterTitle)"
        }
    }

    private func startReading() {
        guard let target: ComicReaderDestination = self.viewModel.primaryReadingTarget else {
            return
        }
        switch target {
        case .chapter(let chapter):
            self.openReaderDestination(chapter)
        case .history(let history):
            self.selectedReaderDestination = .history(history)
        }
    }

    private func dismissDetail() {
        self.dismiss()
    }

    private func openReaderDestination(_ chapter: ChapterLink) {
        guard self.viewModel.prepareToOpen(chapter) else {
            return
        }
        var selectedChapter: ChapterLink = chapter
        selectedChapter.navigationChapterURLs = self.viewModel.chapters.map(\.url)
        selectedChapter.navigationChapterTitles = self.viewModel.chapters.map(\.title)
        selectedChapter.navigationOrder = self.viewModel.chapterNavigationOrder
        self.selectedReaderDestination = .chapter(selectedChapter)

        #if DEBUG
        print(
            "[BrowseCraftNavigation] Select comic detail chapter " +
            "itemId=\(self.viewModel.item.id) chapterTitle=\(chapter.title) chapterURL=\(chapter.url)"
        )
        #endif
    }

    private func loginPromptMessage(isPaid: Bool?) -> String {
        if isPaid == true {
            return "This paid chapter is currently restricted. Log in to check whether your account has access. Purchase or VIP membership may still be required."
        }
        return "This chapter is currently restricted. Log in to check whether your account has access."
    }

    @ViewBuilder
    private func readerDestination(for destination: ComicReaderDestination) -> some View {
        switch destination {
        case .chapter(let chapter):
            ReaderView(
                item: self.viewModel.item,
                source: self.viewModel.source,
                selectedChapter: chapter,
                factory: self.contentViewModelFactory
            )
            .id(self.readerDestinationID(for: destination))
        case .history(let history):
            ReaderView(
                history: history,
                source: self.viewModel.source,
                factory: self.contentViewModelFactory
            )
            .id(self.readerDestinationID(for: destination))
        }
    }

    private func readerDestinationID(for destination: ComicReaderDestination) -> String {
        switch destination {
        case .chapter(let chapter):
            return [
                "chapter",
                self.viewModel.source.id,
                self.viewModel.item.id,
                self.viewModel.item.detailURL,
                chapter.url
            ].joined(separator: "|")
        case .history(let history):
            return [
                "history",
                history.id,
                String(history.visitedAt.timeIntervalSinceReferenceDate)
            ].joined(separator: "|")
        }
    }

    private func retry() {
        Task {
            await self.viewModel.reload()
        }
    }

    private func recordAppearance() {
        if self.viewModel.didLoad {
            self.viewModel.refreshLatestReadingHistory()
        }
        CrashDiagnostics.shared.setScreen(.sourceDetail)
        AppAnalytics.shared.logScreenView(.sourceDetail)
        CrashDiagnostics.shared.setSource(self.viewModel.source)
        CrashDiagnostics.shared.setRuleStage(.detail)
    }
}
