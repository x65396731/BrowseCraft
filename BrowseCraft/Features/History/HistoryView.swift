import SwiftUI

// 中文注释：HistoryView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：HistoryView 是 struct，负责本模块中的对应职责。
struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        NavigationView {
            List {
                Section("Reading") {
                    ForEach(self.viewModel.readingHistoryEntries, id: \.id) { entry in
                        HistoryEntryRowView(
                            entry: entry,
                            dateText: Self.historyDateFormatter.string(from: entry.visitedAt)
                        )
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
        }
    }

    private var detailText: String? {
        switch self.entry.kind {
        case .rss:
            return self.entry.rssHistory?.dataContent
        case .comic:
            return self.entry.comicHistory?.chapterURL?.absoluteString
        }
    }
}
