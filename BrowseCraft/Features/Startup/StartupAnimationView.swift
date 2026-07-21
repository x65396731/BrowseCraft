import SwiftUI
import UIKit

// 中文注释：StartupAnimationView 只负责启动动画呈现和用户跳过交互，状态迁移由 StartupCoordinator 管理。

struct StartupAnimationView: View {
    struct Assets {
        let videoURL: URL?
        let posterImage: UIImage?

        init(resource: BundledStartupAnimationResource) {
            do {
                self.videoURL = try resource.videoURL()
            } catch {
                self.videoURL = nil
                #if DEBUG
                print("[BrowseCraftStartup] missing startup video: \(error.localizedDescription)")
                #endif
            }

            self.posterImage = UIImage(named: "LaunchSplash")
            if self.posterImage == nil {
                #if DEBUG
                print("[BrowseCraftStartup] missing LaunchSplash poster image")
                #endif
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var isVideoReady: Bool = false
    @State private var didReportVideoFailure: Bool = false

    let phase: StartupPhase
    let skipAction: () -> Void
    let videoFailureAction: () -> Void

    private let assets: Assets

    init(
        phase: StartupPhase,
        resource: BundledStartupAnimationResource = BundledStartupAnimationResource(),
        skipAction: @escaping () -> Void,
        videoFailureAction: @escaping () -> Void
    ) {
        self.phase = phase
        self.skipAction = skipAction
        self.videoFailureAction = videoFailureAction
        self.assets = Assets(resource: resource)
    }

    init(
        phase: StartupPhase,
        assets: Assets,
        skipAction: @escaping () -> Void,
        videoFailureAction: @escaping () -> Void
    ) {
        self.phase = phase
        self.skipAction = skipAction
        self.videoFailureAction = videoFailureAction
        self.assets = assets
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            self.animationBackground
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .allowsHitTesting(false)

            if self.phase.canSkip {
                Button(
                    action: self.skipAction,
                    label: {
                        Label("Skip", systemImage: "arrow.right")
                            .font(.headline)
                    }
                )
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.black.opacity(0.64))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .accessibilityLabel("Skip startup animation")
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: self.phase.canSkip)
        .onAppear {
            if self.assets.videoURL == nil {
                self.reportVideoFailureIfNeeded()
            }
        }
        .onChange(of: self.reduceMotion) { _, shouldReduceMotion in
            if shouldReduceMotion {
                self.isVideoReady = false
            }
        }
    }

    private var animationBackground: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let posterImage: UIImage = self.assets.posterImage {
                    Image(uiImage: posterImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }

                if self.reduceMotion == false,
                   let videoURL: URL = self.assets.videoURL {
                    StartupVideoPlayerView(
                        videoURL: videoURL,
                        isPlaybackActive: self.scenePhase == .active && self.phase.isDismissed == false,
                        onReady: {
                            self.isVideoReady = true
                        },
                        onFailure: {
                            self.isVideoReady = false
                            self.reportVideoFailureIfNeeded()
                        }
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(self.isVideoReady ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: self.isVideoReady)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }

    private func reportVideoFailureIfNeeded() {
        guard self.didReportVideoFailure == false else {
            return
        }

        self.didReportVideoFailure = true
        self.videoFailureAction()
    }
}
