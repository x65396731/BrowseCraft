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

    var body: some View {
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
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .navigationTitle(self.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await self.viewModel.load()
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
