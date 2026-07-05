import SwiftUI

// 中文注释：HistoryView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：HistoryView 是 struct，负责本模块中的对应职责。
struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    let readerViewModelFactory: (ComicChapterHistory, Source) -> ReaderViewModel

    var body: some View {
        NavigationView {
            List {
                Section("Reading") {
                    ForEach(self.viewModel.readingHistoryEntries, id: \.id) { entry in
                        NavigationLink(destination: self.destination(for: entry)) {
                            HistoryEntryRowView(
                                entry: entry,
                                dateText: Self.historyDateFormatter.string(from: entry.visitedAt)
                            )
                        }
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
                self.viewModel.load()
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
               let source: Source = self.viewModel.source(for: history.sourceID),
               history.lastReaderPageURL != nil || history.chapterURL != nil {
                ReaderView(viewModel: self.readerViewModelFactory(history, source))
            } else {
                HistoryUnavailableView(message: "Missing comic source or chapter URL.")
            }
        case .video:
            if entry.videoHistory != nil {
                HistoryUnavailableView(message: "Video player is not connected yet.")
            } else {
                HistoryUnavailableView(message: "Missing video history.")
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

private struct RSSHistoryDetailView: View {
    let history: RSSReadingHistory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(self.history.title)
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    if let sourceName: String = self.history.sourceName {
                        Label(sourceName, systemImage: "dot.radiowaves.left.and.right")
                    }

                    Label(Self.dateFormatter.string(from: self.history.dataTime), systemImage: "calendar")
                    Label(Self.dateFormatter.string(from: self.history.visitedAt), systemImage: "clock")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                if let content: String = FeedContentTextFormatter.sanitized(self.history.dataContent) {
                    Text(content)
                        .font(.body)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let detailURL: URL = self.history.detailURL {
                    Link(destination: detailURL) {
                        Label("Open Original", systemImage: "safari")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .navigationTitle("RSS")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

private struct HistoryUnavailableView: View {
    let message: String

    var body: some View {
        EmptyStateView(
            systemImage: "exclamationmark.triangle",
            title: "Unavailable",
            message: self.message
        )
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HistoryEntryRowView: View {
    let entry: ReadingHistoryEntry
    let dateText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: self.iconName)
                    .foregroundColor(.secondary)
                    .frame(width: 18)

                Text(self.entry.title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }

            if let subtitle: String = self.entry.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            if let detail: String = self.detailText {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            Text(self.dateText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch self.entry.kind {
        case .rss:
            return "dot.radiowaves.left.and.right"
        case .comic:
            return "book.pages"
        case .video:
            return "play.rectangle"
        }
    }

    private var detailText: String? {
        switch self.entry.kind {
        case .rss:
            return self.entry.rssHistory?.dataContent
        case .comic:
            return self.entry.comicHistory?.chapterURL?.absoluteString
        case .video:
            return self.entry.videoHistory?.playPageURL.absoluteString
        }
    }
}
