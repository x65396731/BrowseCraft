import SwiftUI

// 中文注释：RSSContentDetailView 是 RSS 新闻详情画面。

struct RSSContentDetailView: View {
    @StateObject private var viewModel: RSSContentDetailViewModel

    init(viewModel: RSSContentDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if self.viewModel.item.coverURL != nil {
                    CoverImageView(urlString: self.viewModel.item.coverURL)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Text(self.viewModel.item.title)
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Label(
                        title: {
                            Text(self.viewModel.sourceName)
                        },
                        icon: {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                    )

                    Text("RSS")

                    if let updatedAt: Date = self.viewModel.item.updatedAt {
                        Text(RSSContentDateFormatter.string(from: updatedAt))
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                if let summary: String = RSSContentTextFormatter.sanitized(self.viewModel.item.latestText) {
                    Text(summary)
                        .font(.body)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let url: URL = URL(string: self.viewModel.item.detailURL) {
                    Link(destination: url) {
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
        .navigationTitle(self.viewModel.sourceName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            CrashDiagnostics.shared.setScreen(.rssDetail)
            CrashDiagnostics.shared.setSource(self.viewModel.source)
            CrashDiagnostics.shared.setRuleStage(.rssFeed)
            self.viewModel.saveReadingHistoryIfNeeded()
        }
        .handlesRewardedAdPlayback(
            shouldPlayAd: self.viewModel.shouldPlayAd,
            markHandled: {
                self.viewModel.markAdPlaybackHandled()
            }
        )
    }
}
