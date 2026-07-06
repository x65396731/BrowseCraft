import SafariServices
import SwiftUI
import KSPlayer

// 中文注释：VideoPlayerHostView 是视频播放页，不复用漫画 Reader UI。
struct VideoPlayerHostView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: VideoPlayerViewModel
    @StateObject private var playerCoordinator: KSVideoPlayer.Coordinator
    @State private var isShowingSafari: Bool = false

    init(viewModel: VideoPlayerViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _playerCoordinator = StateObject(wrappedValue: KSVideoPlayer.Coordinator())
    }

    var body: some View {
        Group {
            if let mediaURL: URL = self.viewModel.nativeMediaURL {
                self.nativePlayer(mediaURL: mediaURL)
            } else {
                self.fallbackPlayer
            }
        }
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

    private func nativePlayer(mediaURL: URL) -> some View {
        KSVideoPlayerView(
            coordinator: self.playerCoordinator,
            url: mediaURL,
            options: KSOptions(),
            title: self.viewModel.displayTitle
        )
        .overlay(alignment: .bottom) {
            self.episodeNavigationControls
                .padding(.horizontal, 28)
                .padding(.bottom, 76)
        }
        .onChange(of: mediaURL) { _, newURL in
            self.switchNativePlayer(to: newURL)
        }
        .onAppear {
            self.installPlayerCallbacks()
        }
    }

    private func switchNativePlayer(to mediaURL: URL) {
        guard let playerLayer: KSPlayerLayer = self.playerCoordinator.playerLayer,
              playerLayer.url != mediaURL else {
            return
        }

        self.installPlayerCallbacks()
        playerLayer.set(url: mediaURL, options: KSOptions())
        self.configureBackBlock(for: playerLayer.player.view)
    }

    private func installPlayerCallbacks() {
        self.playerCoordinator.onPlay = { currentTime, totalTime in
            self.viewModel.recordPlaybackProgress(
                currentTime: currentTime,
                totalTime: totalTime
            )
        }
        self.playerCoordinator.onStateChanged = { layer, state in
            self.configureBackBlock(for: layer.player.view)
            if state == .readyToPlay {
                DispatchQueue.main.async {
                    layer.play()
                    self.viewModel.markReadyToPlay { playbackTime in
                        layer.seek(
                            time: playbackTime,
                            autoPlay: true,
                            completion: { _ in }
                        )
                    }
                }
            }
        }
        self.configureBackBlock(for: self.playerCoordinator.playerLayer?.player.view)
    }

    private func configureBackBlock(for view: UIView?) {
        guard let playerView: PlayerView = view as? PlayerView else {
            return
        }

        playerView.backBlock = {
            self.closePlayer()
        }
    }

    private func closePlayer() {
        self.viewModel.saveOnDisappear()
        self.dismiss()
    }

    private var fallbackPlayer: some View {
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

            Image(systemName: "safari")
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(.blue)

            VStack(spacing: 6) {
                Text("Web Player Required")
                    .font(.title3.weight(.semibold))

                Text("This episode does not expose a direct media URL yet.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(
                action: {
                    self.isShowingSafari = true
                },
                label: {
                    Label("Open Web Player", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
            )
            .buttonStyle(.borderedProminent)

            self.episodeNavigationControls
            .sheet(isPresented: self.$isShowingSafari) {
                SafariView(url: self.viewModel.fallbackPageURL)
                    .ignoresSafeArea()
            }
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

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> SFSafariViewController {
        return SFSafariViewController(url: self.url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context _: Context) {}
}
