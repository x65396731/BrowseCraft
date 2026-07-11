import SwiftUI

// 中文注释：VideoDetailView 是视频详情和选集页，和漫画章节/Reader 流程分离。
struct VideoDetailView: View {
    @StateObject private var viewModel: VideoDetailViewModel

    init(viewModel: VideoDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                self.header

                self.detailSummary

                if self.viewModel.isLoadingEpisodes {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else if self.viewModel.episodes.isEmpty {
                    EmptyStateView(
                        systemImage: "play.rectangle",
                        title: "No Episodes",
                        message: "Refresh this video detail after the source exposes episodes."
                    )
                    .padding(.vertical, 32)
                } else {
                    self.episodeList
                }
            }
            .padding(16)
        }
        .navigationTitle("Video")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            CrashDiagnostics.shared.setScreen(.videoDetail)
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

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverImageView(
                urlString: self.viewModel.item.coverURL,
                refererURLString: self.viewModel.item.detailURL,
                requestConfig: nil
            )
            .frame(width: 112)
            .aspectRatio(0.72, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(self.viewModel.item.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Label(
                    title: {
                        Text(self.viewModel.sourceName)
                    },
                    icon: {
                        Image(systemName: "play.rectangle")
                    }
                )
                .font(.caption)
                .foregroundColor(.secondary)

                if let latestText: String = self.viewModel.item.latestText {
                    Text(latestText)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var detailSummary: some View {
        if let synopsis: String = self.viewModel.synopsis {
            VStack(alignment: .leading, spacing: 8) {
                Text("简介")
                    .font(.headline)

                Text(synopsis)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if self.viewModel.metadataRows.isEmpty == false {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(self.viewModel.metadataRows, id: \.self) { row in
                    Text(row)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var episodeList: some View {
        LazyVStack(spacing: 10) {
            ForEach(self.viewModel.episodes) { episode in
                Button(
                    action: {
                        Task {
                            await self.viewModel.openEpisode(episode)
                        }
                    },
                    label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.circle")
                                .font(.title3)
                                .foregroundColor(.blue)

                            Text(episode.title)
                                .font(.body.weight(.medium))
                                .foregroundColor(.primary)
                                .lineLimit(2)

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                )
                .buttonStyle(.plain)
            }
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
