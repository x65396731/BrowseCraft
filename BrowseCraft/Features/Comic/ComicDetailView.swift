import SwiftUI

/// 中文注释：漫画详情页展示作品信息和章节目录；只有章节选择后才创建 Reader。
struct ComicDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ComicDetailViewModel
    @State private var selectedReaderChapter: ChapterLink?

    let readerViewModelFactory: (ContentItem, Source, ChapterLink?) -> ReaderViewModel

    init(
        viewModel: ComicDetailViewModel,
        readerViewModelFactory: @escaping (ContentItem, Source, ChapterLink?) -> ReaderViewModel
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.readerViewModelFactory = readerViewModelFactory
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
                    isEnabled: self.viewModel.startingChapter != nil,
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
            if let chapter: ChapterLink = self.selectedReaderChapter {
                self.readerDestination(for: chapter)
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
                return self.selectedReaderChapter != nil
            },
            set: { newValue in
                if newValue == false {
                    self.selectedReaderChapter = nil
                }
            }
        )
    }

    private func startReading() {
        guard let chapter: ChapterLink = self.viewModel.startingChapter else {
            return
        }
        self.openReaderDestination(chapter)
    }

    private func dismissDetail() {
        self.dismiss()
    }

    private func openReaderDestination(_ chapter: ChapterLink) {
        var selectedChapter: ChapterLink = chapter
        selectedChapter.navigationChapterURLs = self.viewModel.chapters.map(\.url)
        selectedChapter.navigationChapterTitles = self.viewModel.chapters.map(\.title)
        selectedChapter.navigationOrder = self.viewModel.chapterNavigationOrder
        self.selectedReaderChapter = selectedChapter

        #if DEBUG
        print(
            "[BrowseCraftNavigation] Select comic detail chapter " +
            "itemId=\(self.viewModel.item.id) chapterTitle=\(chapter.title) chapterURL=\(chapter.url)"
        )
        #endif
    }

    private func readerDestination(for chapter: ChapterLink) -> some View {
        ReaderView(
            viewModel: self.readerViewModelFactory(
                self.viewModel.item,
                self.viewModel.source,
                chapter
            )
        )
        .id(self.readerDestinationID(for: chapter))
    }

    private func readerDestinationID(for chapter: ChapterLink) -> String {
        return [
            self.viewModel.source.id,
            self.viewModel.item.id,
            self.viewModel.item.detailURL,
            chapter.url
        ].joined(separator: "|")
    }

    private func retry() {
        Task {
            await self.viewModel.reload()
        }
    }

    private func recordAppearance() {
        CrashDiagnostics.shared.setScreen(.sourceDetail)
        AppAnalytics.shared.logScreenView(.sourceDetail)
        CrashDiagnostics.shared.setSource(self.viewModel.source)
        CrashDiagnostics.shared.setRuleStage(.detail)
    }
}
