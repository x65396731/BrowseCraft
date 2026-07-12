import NukeUI
import SwiftUI
import UIKit

// 中文注释：ReaderView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：ChapterListView 是 struct，负责本模块中的对应职责。
struct ChapterListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ChapterListViewModel
    let readerViewModelFactory: (ContentItem, Source, ChapterLink?) -> ReaderViewModel

    init(
        viewModel: ChapterListViewModel,
        readerViewModelFactory: @escaping (ContentItem, Source, ChapterLink?) -> ReaderViewModel
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.readerViewModelFactory = readerViewModelFactory
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ChapterDetailHeaderView(viewModel: self.viewModel)

                ChapterSummaryView(viewModel: self.viewModel)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                self.chapterList
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(.systemBackground))
        .navigationTitle(self.viewModel.item.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ChapterLink.self) { chapter in
            ReaderView(
                viewModel: self.readerViewModelFactory(
                    self.viewModel.item,
                    self.viewModel.source,
                    chapter
                )
            )
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    self.dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
        }
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

    @ViewBuilder
    private var chapterList: some View {
        if self.viewModel.isLoading {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 180)
        } else if self.viewModel.chapters.isEmpty {
            ContentUnavailableView(
                "No Chapters",
                systemImage: "list.bullet.rectangle",
                description: Text("This source did not return any chapter entries.")
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 220)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(self.viewModel.chapters, id: \.url) { chapter in
                    NavigationLink(value: chapter) {
                        HStack(spacing: 12) {
                            Text(chapter.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(2)

                            Spacer(minLength: 12)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if chapter.url != self.viewModel.chapters.last?.url {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .padding(.bottom, 24)
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

private struct ChapterDetailHeaderView: View {
    @ObservedObject var viewModel: ChapterListViewModel

    var body: some View {
        ChapterDetailHeroImageView(viewModel: self.viewModel)
    }
}

private struct ChapterDetailHeroImageView: View {
    @ObservedObject var viewModel: ChapterListViewModel

    var body: some View {
        self.image
            .frame(maxWidth: .infinity)
            .frame(height: UIScreen.main.bounds.width * 1.05)
            .background(Color(.secondarySystemBackground))
            .clipped()
            .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private var image: some View {
        if let request: ImageRequest = self.imageRequest {
            LazyImage(source: request) { state in
                if let uiImage: UIImage = state.imageContainer?.image {
                    Image(uiImage: uiImage)
                        .resizable()
                } else {
                    self.placeholder
                }
            }
        } else {
            self.placeholder
        }
    }

    private var imageRequest: ImageRequest? {
        guard let coverURL: String = self.viewModel.item.coverURL else {
            return nil
        }

        return ImageRequestFactory.makeRequest(
            urlString: coverURL,
            refererURLString: self.viewModel.item.detailURL,
            requestConfig: self.viewModel.detailCoverRequestConfig
        )
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(Color(.secondarySystemFill))

            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ChapterSummaryView: View {
    @ObservedObject var viewModel: ChapterListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                self.summaryItem(
                    title: "Description",
                    value: self.descriptionText,
                    lineLimit: nil
                )

                Divider()

                self.summaryItem(
                    title: "Last",
                    value: self.viewModel.item.latestText ?? "Unknown",
                    lineLimit: 2
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var descriptionText: String {
        guard let description: String = self.viewModel.detailDescription,
              description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return self.viewModel.source.name.uppercased()
        }

        return description
    }

    private func summaryItem(title: String, value: String, lineLimit: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// 中文注释：ReaderView 是 struct，负责本模块中的对应职责。
struct ReaderView: View {
    @StateObject private var viewModel: ReaderViewModel
    @State private var didApplyRestorePage: Bool = false

    init(viewModel: ReaderViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    self.readerContent
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

    @ViewBuilder
    private var readerContent: some View {
        if self.viewModel.isLoading && self.viewModel.chapter == nil {
            ProgressView()
                .padding(.top, 80)
        } else if let chapter: ReaderChapter = self.viewModel.chapter,
                  chapter.pageImageURLs.isEmpty == false {
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

    @ViewBuilder
    private func readerPages(for chapter: ReaderChapter) -> some View {
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
