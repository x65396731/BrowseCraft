import KSPlayer
import SwiftUI
import UIKit

struct PurchaseAnimationKSPlayerView: UIViewRepresentable {
    let videoURL: URL
    let isPlaybackActive: Bool
    let onReady: () -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        return Coordinator(
            isPlaybackActive: self.isPlaybackActive,
            onReady: self.onReady,
            onFailure: self.onFailure
        )
    }

    func makeUIView(context: Context) -> IOSVideoPlayerView {
        let playerView: IOSVideoPlayerView = PurchaseBackgroundKSPlayerView()
        playerView.backgroundColor = .clear
        playerView.isUserInteractionEnabled = false
        context.coordinator.attach(to: playerView)
        self.configure(playerView, coordinator: context.coordinator)
        return playerView
    }

    func updateUIView(_ playerView: IOSVideoPlayerView, context: Context) {
        context.coordinator.update(
            isPlaybackActive: self.isPlaybackActive,
            onReady: self.onReady,
            onFailure: self.onFailure
        )
        self.configure(playerView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ playerView: IOSVideoPlayerView, coordinator: Coordinator) {
        playerView.delegate = nil
        playerView.pause()
        playerView.playerLayer?.player.shutdown()
        playerView.playerLayer = nil
        playerView.resetPlayer()
        coordinator.detach()
    }

    private func configure(_ playerView: IOSVideoPlayerView, coordinator: Coordinator) {
        guard coordinator.videoURL != self.videoURL else {
            return
        }

        coordinator.prepare(for: self.videoURL)

        let options: KSOptions = KSOptions()
        options.isLoopPlay = true
        options.registerRemoteControll = false

        playerView.set(url: self.videoURL, options: options)
        playerView.playerLayer?.player.isMuted = true
        playerView.playerLayer?.player.contentMode = .scaleAspectFill
        coordinator.applyPlaybackState()
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency PlayerControllerDelegate {
        private weak var playerView: IOSVideoPlayerView?
        private var isPlaybackActive: Bool
        private var didReportReady: Bool = false
        private var didReportFailure: Bool = false
        private var onReady: () -> Void
        private var onFailure: () -> Void

        fileprivate var videoURL: URL?

        init(
            isPlaybackActive: Bool,
            onReady: @escaping () -> Void,
            onFailure: @escaping () -> Void
        ) {
            self.isPlaybackActive = isPlaybackActive
            self.onReady = onReady
            self.onFailure = onFailure
        }

        func attach(to playerView: IOSVideoPlayerView) {
            self.playerView = playerView
            playerView.delegate = self
        }

        func prepare(for videoURL: URL) {
            self.videoURL = videoURL
            self.didReportReady = false
            self.didReportFailure = false
        }

        func update(
            isPlaybackActive: Bool,
            onReady: @escaping () -> Void,
            onFailure: @escaping () -> Void
        ) {
            let playbackStateChanged: Bool = self.isPlaybackActive != isPlaybackActive
            self.isPlaybackActive = isPlaybackActive
            self.onReady = onReady
            self.onFailure = onFailure
            if playbackStateChanged {
                self.applyPlaybackState()
            }
        }

        func applyPlaybackState() {
            guard let playerView: IOSVideoPlayerView = self.playerView else {
                return
            }

            playerView.playerLayer?.player.isMuted = true
            playerView.playerLayer?.player.contentMode = .scaleAspectFill

            if self.isPlaybackActive {
                playerView.play()
            } else {
                playerView.pause()
            }
        }

        func detach() {
            self.playerView = nil
            self.videoURL = nil
            self.onReady = {}
            self.onFailure = {}
        }

        func playerController(state: KSPlayerState) {
            switch state {
            case .readyToPlay, .bufferFinished:
                guard self.didReportReady == false else {
                    return
                }

                self.didReportReady = true
                self.didReportFailure = false
                self.applyPlaybackState()
                self.onReady()
            case .error:
                self.reportFailureIfNeeded(detail: "KSPlayer entered the error state")
            default:
                break
            }
        }

        func playerController(finish error: Error?) {
            if let error {
                self.reportFailureIfNeeded(detail: error.localizedDescription)
            }
        }

        private func reportFailureIfNeeded(detail: String) {
            guard self.didReportFailure == false else {
                return
            }

            #if DEBUG
            print("[BrowseCraftPurchaseAnimation] playback failed: \(detail)")
            #endif

            self.didReportFailure = true
            self.didReportReady = false
            self.playerView?.pause()
            self.onFailure()
        }

        func playerController(currentTime _: TimeInterval, totalTime _: TimeInterval) {}

        func playerController(maskShow _: Bool) {}

        func playerController(action _: PlayerButtonType) {}

        func playerController(bufferedCount _: Int, consumeTime _: TimeInterval) {}

        func playerController(seek _: TimeInterval) {}
    }
}

private final class PurchaseBackgroundKSPlayerView: IOSVideoPlayerView {
    override func customizeUIComponents() {
        super.customizeUIComponents()

        self.controllerView.isHidden = true
        self.contentOverlayView.isHidden = true
        self.tapGesture.isEnabled = false
        self.doubleTapGesture.isEnabled = false
        self.panGesture.isEnabled = false
        self.longPressGesture.isEnabled = false
    }
}
