import SwiftUI
import UIKit

// 中文注释：VideoDetailView 是视频详情和选集页，和漫画章节/Reader 流程分离。
struct VideoDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: VideoDetailViewModel

    init(viewModel: VideoDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                VideoDetailHeaderView(viewModel: self.viewModel)

                VideoDetailSummaryView(viewModel: self.viewModel)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                self.episodeList
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(.systemBackground))
        .navigationTitle(self.viewModel.item.title)
        .navigationBarTitleDisplayMode(.inline)
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
            CrashDiagnostics.shared.setScreen(.videoDetail)
            AppAnalytics.shared.logScreenView(.videoDetail)
            CrashDiagnostics.shared.setSource(self.viewModel.source)
            CrashDiagnostics.shared.setRuleStage(.detail)
            #if DEBUG
            print(
                "[BrowseCraftVideoDetail] view appear " +
                "source=\(self.viewModel.source.id) " +
                "item=\(self.viewModel.item.id) " +
                "episodes=\(self.viewModel.episodes.count)"
            )
            #endif
        }
        .task {
            #if DEBUG
            print(
                "[BrowseCraftVideoDetail] task start " +
                "source=\(self.viewModel.source.id) " +
                "item=\(self.viewModel.item.id)"
            )
            #endif
            await self.viewModel.loadEpisodesIfNeeded()
        }
        .refreshable {
            await self.viewModel.loadEpisodes()
        }
        .fullScreenCover(item: self.$viewModel.playbackRoute) { route in
            VideoPlayerHostView(viewModel: route.viewModel)
        }
        .overlay {
            if self.viewModel.isLoadingPlayback {
                ZStack {
                    Color(.systemBackground)
                        .opacity(0.72)
                        .ignoresSafeArea()

                    ProgressView("Loading Playback")
                        .padding(20)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .alert(isPresented: self.errorAlertBinding) {
            Alert(
                title: Text("Video"),
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
    private var episodeList: some View {
        if self.viewModel.isLoadingEpisodes {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 180)
        } else if self.viewModel.episodes.isEmpty {
            ContentUnavailableView(
                "No Episodes",
                systemImage: "play.rectangle",
                description: Text("This source did not return any episode entries.")
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 220)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(self.viewModel.episodes) { episode in
                    Button(
                        action: {
                            Task {
                                await self.viewModel.openEpisode(episode)
                            }
                        },
                        label: {
                            HStack(spacing: 12) {
                                Text(episode.title)
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
                    )
                    .buttonStyle(.plain)

                    if episode.id != self.viewModel.episodes.last?.id {
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

private struct VideoDetailHeaderView: View {
    @ObservedObject var viewModel: VideoDetailViewModel

    var body: some View {
        VideoDetailHeroImageView(viewModel: self.viewModel)
    }
}

private struct VideoDetailHeroImageView: View {
    @ObservedObject var viewModel: VideoDetailViewModel

    var body: some View {
        CoverImageView(
            urlString: self.viewModel.item.coverURL,
            refererURLString: self.viewModel.item.detailURL,
            requestConfig: nil
        )
        .frame(maxWidth: .infinity)
        .frame(height: UIScreen.main.bounds.width * 1.05)
        .background(Color(.secondarySystemBackground))
        .clipped()
        .ignoresSafeArea(edges: .top)
    }
}

private struct VideoDetailSummaryView: View {
    @ObservedObject var viewModel: VideoDetailViewModel

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

                if self.metadataText.isEmpty == false {
                    Divider()

                    self.summaryItem(
                        title: "Info",
                        value: self.metadataText,
                        lineLimit: nil
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var descriptionText: String {
        guard let synopsis: String = self.viewModel.synopsis,
              synopsis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return self.viewModel.sourceName.uppercased()
        }

        return synopsis
    }

    private var metadataText: String {
        return self.viewModel.metadataRows.joined(separator: "\n")
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
