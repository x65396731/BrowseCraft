import SwiftUI

// 中文注释：VideoPlayerHostView 是视频播放页，不复用漫画 Reader UI。
struct VideoPlayerHostView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: VideoPlayerViewModel
    @State private var didOpenContentSuccessfully: Bool = false

    init(viewModel: VideoPlayerViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        self.playerContent
        .task {
            CrashDiagnostics.shared.setScreen(.videoPlayer)
            AppAnalytics.shared.logScreenView(.videoPlayer)
            CrashDiagnostics.shared.setSource(self.viewModel.source)
            CrashDiagnostics.shared.setRuleStage(.videoPlayback)
            await self.viewModel.prepareForPlayback()
            guard Task.isCancelled == false else {
                return
            }
            self.didOpenContentSuccessfully = self.hasPlayableContent
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
        .fullScreenCover(item: self.requestedSourceLoginBinding) { loginState in
            SourceLoginView(
                state: loginState,
                cancelAction: {
                    self.viewModel.dismissRequestedSourceLogin()
                },
                completeAction: { credential in
                    Task {
                        await self.viewModel.completeRequestedSourceLogin(credential: credential)
                    }
                }
            )
        }
        .handlesRewardedAdPlayback(
            shouldPlayAd: self.viewModel.shouldPlayAd,
            markHandled: {
                self.viewModel.markAdPlaybackHandled()
            }
        )
        .requestsAppReviewAfterSuccessfulContentOpen(
            when: self.didOpenContentSuccessfully && self.viewModel.shouldPlayAd == false
        )
    }

    private var hasPlayableContent: Bool {
        switch self.viewModel.playbackDestination {
        case .native, .web:
            return true
        case .unavailable:
            return false
        }
    }

    @ViewBuilder
    private var playerContent: some View {
        switch self.viewModel.playbackDestination {
        case .native(let mediaURL):
            VideoNativePlayerView(
                mediaURL: mediaURL,
                requestConfig: self.viewModel.resolvedPlaybackRequestConfig,
                title: self.viewModel.displayTitle,
                onProgress: { currentTime, totalTime in
                    self.viewModel.recordPlaybackProgress(
                        currentTime: currentTime,
                        totalTime: totalTime
                    )
                },
                onReadyToPlay: { seek in
                    self.viewModel.markReadyToPlay(seek: seek)
                },
                onPlaybackFailure: { error in
                    Task {
                        await self.viewModel.handleNativePlaybackFailure(error)
                    }
                },
                onClose: {
                    self.closePlayer()
                }
            )
        case .web(let request):
            VideoWebPlayerView(
                request: request,
                title: self.viewModel.displayTitle,
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

            if let loginState: LibrarySourceLoginState = self.viewModel.restrictedLoginState {
                Button(loginState.status == .authenticated ? "Open Login Page" : "Sign In to This Source") {
                    self.viewModel.requestSourceLogin()
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var requestedSourceLoginBinding: Binding<LibrarySourceLoginState?> {
        return Binding<LibrarySourceLoginState?>(
            get: {
                return self.viewModel.requestedSourceLogin
            },
            set: { loginState in
                if loginState == nil {
                    self.viewModel.dismissRequestedSourceLogin()
                }
            }
        )
    }
}
