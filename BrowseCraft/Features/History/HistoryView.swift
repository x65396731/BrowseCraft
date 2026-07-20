import SwiftUI

// 中文注释：HistoryView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：HistoryView 是 struct，负责本模块中的对应职责。
struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    let contentViewModelFactory: LibraryContentViewModelFactory

    var body: some View {
        NavigationStack {
            List {
                Section("Reading") {
                    ForEach(self.viewModel.readingHistoryEntries, id: \.id) { entry in
                        if entry.kind == .video {
                            Button {
                                if let history: VideoWatchHistory = entry.videoHistory {
                                    self.viewModel.openVideoHistory(history)
                                }
                            } label: {
                                HistoryEntryRowView(
                                    entry: entry,
                                    dateText: Self.historyDateFormatter.string(from: entry.visitedAt)
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(destination: self.destination(for: entry)) {
                                HistoryEntryRowView(
                                    entry: entry,
                                    dateText: Self.historyDateFormatter.string(from: entry.visitedAt)
                                )
                            }
                        }
                    }
                    .onDelete { offsets in
                        self.viewModel.deleteHistoryEntries(at: offsets)
                    }
                }
            }
            .overlay(
                Group {
                    if self.viewModel.readingHistoryEntries.isEmpty {
                        EmptyStateView(
                            systemImage: "clock",
                            title: "No History",
                            message: "Opened feed items and read chapters will appear here."
                        )
                    }
                }
            )
            .navigationTitle("History")
            .onAppear {
                CrashDiagnostics.shared.setScreen(.history)
                AppAnalytics.shared.logScreenView(.history)
                self.viewModel.load()
            }
            .fullScreenCover(item: self.$viewModel.videoPlaybackRoute) { route in
                VideoPlayerHostView(viewModel: route.viewModel)
            }
            .alert(isPresented: self.errorAlertBinding) {
                Alert(
                    title: Text("History"),
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

    @ViewBuilder
    private func destination(for entry: ReadingHistoryEntry) -> some View {
        switch entry.kind {
        case .rss:
            if let history: RSSReadingHistory = entry.rssHistory {
                RSSHistoryDetailView(history: history)
            } else {
                HistoryUnavailableView(message: "Missing feed history.")
            }
        case .comic:
            if let history: ComicChapterHistory = entry.comicHistory,
               let source: Source = self.viewModel.source(for: history),
               history.lastReaderPageURL != nil || history.chapterURL != nil {
                ReaderView(
                    history: history,
                    source: source,
                    factory: self.contentViewModelFactory
                )
            } else {
                HistoryUnavailableView(message: "Missing comic source or chapter URL.")
            }
        case .video:
            HistoryUnavailableView(message: "Video history opens with the full-screen player.")
        case .temporary:
            if let history: TemporaryResourceHistory = entry.temporaryHistory {
                TemporaryHistoryDetailView(history: history)
            } else {
                HistoryUnavailableView(message: "Missing temporary history.")
            }
        }
    }

    private static let historyDateFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

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
