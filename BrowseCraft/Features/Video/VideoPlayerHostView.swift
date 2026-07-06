import SafariServices
import SwiftUI
import KSPlayer

// 中文注释：VideoPlayerHostView 是视频播放页，不复用漫画 Reader UI。
struct VideoPlayerHostView: View {
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
        .navigationTitle(self.viewModel.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
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
        // 中文注释：KSPlayer 已显示 SDK 自带关闭按钮；当前 dismiss 事件暂记为待定，不在这里叠加自定义 x。
        KSVideoPlayerView(
            coordinator: self.playerCoordinator,
            url: mediaURL,
            options: KSOptions(),
            title: self.viewModel.displayTitle
        )
        .onAppear {
            self.playerCoordinator.onPlay = { currentTime, totalTime in
                self.viewModel.recordPlaybackProgress(
                    currentTime: currentTime,
                    totalTime: totalTime
                )
            }
            self.playerCoordinator.onStateChanged = { layer, state in
                if state == .readyToPlay {
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
    }

    private var fallbackPlayer: some View {
        VStack(spacing: 18) {
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
            .sheet(isPresented: self.$isShowingSafari) {
                SafariView(url: self.viewModel.fallbackPageURL)
                    .ignoresSafeArea()
            }
        }
        .padding(24)
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
