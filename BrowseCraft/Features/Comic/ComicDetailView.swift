import SwiftUI

/// 中文注释：漫画详情页展示作品信息和章节目录；只有章节选择后才创建 Reader。
struct ComicDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ComicDetailViewModel
    @State private var selectedReaderDestination: ComicReaderDestination?

    let readerViewModelFactory: (ContentItem, Source, ChapterLink?) -> ReaderViewModel
    let historyReaderViewModelFactory: (ComicChapterHistory, Source) -> ReaderViewModel

    init(
        viewModel: ComicDetailViewModel,
        readerViewModelFactory: @escaping (ContentItem, Source, ChapterLink?) -> ReaderViewModel,
        historyReaderViewModelFactory: @escaping (ComicChapterHistory, Source) -> ReaderViewModel
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.readerViewModelFactory = readerViewModelFactory
        self.historyReaderViewModelFactory = historyReaderViewModelFactory
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

    @ViewBuilder
    private func readerDestination(for destination: ComicReaderDestination) -> some View {
        switch destination {
        case .chapter(let chapter):
            ReaderView(
                viewModel: self.readerViewModelFactory(
                    self.viewModel.item,
                    self.viewModel.source,
                    chapter
                )
            )
            .id(self.readerDestinationID(for: destination))
        case .history(let history):
            ReaderView(
                viewModel: self.historyReaderViewModelFactory(
                    history,
                    self.viewModel.source
                )
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
