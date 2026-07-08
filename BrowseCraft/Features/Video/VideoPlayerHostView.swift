import SwiftUI

// 中文注释：VideoPlayerHostView 是视频播放页，不复用漫画 Reader UI。
struct VideoPlayerHostView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: VideoPlayerViewModel

    init(viewModel: VideoPlayerViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        self.playerContent
        .task {
            self.viewModel.prepareForPlayback()
        }
        .onDisappear {
            self.viewModel.saveOnDisappear()
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
    private var playerContent: some View {
        switch self.viewModel.playbackDestination {
        case .native(let mediaURL):
            VideoNativePlayerView(
                mediaURL: mediaURL,
                requestConfig: self.viewModel.reference.playbackRequestConfig,
                title: self.viewModel.displayTitle,
                controls: {
                    self.episodeNavigationControls
                },
                onProgress: { currentTime, totalTime in
                    self.viewModel.recordPlaybackProgress(
                        currentTime: currentTime,
                        totalTime: totalTime
                    )
                },
                onReadyToPlay: { seek in
                    self.viewModel.markReadyToPlay(seek: seek)
                },
                onClose: {
                    self.closePlayer()
                }
            )
        case .web(let request):
            VideoWebPlayerView(
                request: request,
                title: self.viewModel.displayTitle,
                controls: {
                    self.episodeNavigationControls
                },
                onClose: {
                    self.closePlayer()
                }
            )
        case .unavailable(let title, let message, let systemImage):
            self.unavailablePlayer(
                title: title,
                message: message,
                systemImage: systemImage
            )
        }
    }

    private func closePlayer() {
        self.viewModel.saveOnDisappear()
        self.dismiss()
    }

    private func unavailablePlayer(
        title: String,
        message: String,
        systemImage: String
    ) -> some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()

                Button(
                    action: {
                        self.closePlayer()
                    },
                    label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                )
                .accessibilityLabel("Close Player")
            }

            Spacer(minLength: 0)

            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            self.episodeNavigationControls

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var episodeNavigationControls: some View {
        HStack(spacing: 20) {
            Button {
                Task {
                    await self.viewModel.openPreviousEpisode()
                }
            } label: {
                Label("Previous Episode", systemImage: "backward.end.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(.borderedProminent)
            .disabled(self.viewModel.canOpenPreviousEpisode == false)
            .opacity(self.viewModel.canOpenPreviousEpisode ? 1 : 0.42)

            if self.viewModel.isLoadingEpisodeSwitch {
                ProgressView()
                    .tint(.white)
                    .frame(width: 46, height: 46)
            }

            Button {
                Task {
                    await self.viewModel.openNextEpisode()
                }
            } label: {
                Label("Next Episode", systemImage: "forward.end.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(.borderedProminent)
            .disabled(self.viewModel.canOpenNextEpisode == false)
            .opacity(self.viewModel.canOpenNextEpisode ? 1 : 0.42)
        }
        .tint(.white.opacity(0.9))
        .accessibilityElement(children: .contain)
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
