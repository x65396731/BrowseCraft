import AVFoundation
import SwiftUI
import UIKit

// 中文注释：启动视频使用系统 AVFoundation 播放本地资源，避免把完整业务播放器带入启动链路。

struct StartupVideoPlayerView: UIViewRepresentable {
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

    func makeUIView(context: Context) -> StartupPlayerUIView {
        let playerView: StartupPlayerUIView = StartupPlayerUIView()
        playerView.backgroundColor = .clear
        playerView.isUserInteractionEnabled = false
        context.coordinator.configure(videoURL: self.videoURL, playerView: playerView)
        return playerView
    }

    func updateUIView(_ playerView: StartupPlayerUIView, context: Context) {
        context.coordinator.update(
            isPlaybackActive: self.isPlaybackActive,
            onReady: self.onReady,
            onFailure: self.onFailure
        )
        context.coordinator.configure(videoURL: self.videoURL, playerView: playerView)
    }

    static func dismantleUIView(_ playerView: StartupPlayerUIView, coordinator: Coordinator) {
        coordinator.tearDown()
        playerView.player = nil
    }

    @MainActor
    final class Coordinator {
        private var player: AVQueuePlayer?
        private var playerLooper: AVPlayerLooper?
        private var statusObservation: NSKeyValueObservation?
        private var currentItemObservation: NSKeyValueObservation?
        private var itemStatusObservation: NSKeyValueObservation?
        private var videoURL: URL?
        private var isPlaybackActive: Bool
        private var didReportReady: Bool = false
        private var didReportFailure: Bool = false
        private var didActivateAudioSession: Bool = false
        private var onReady: () -> Void
        private var onFailure: () -> Void

        init(
            isPlaybackActive: Bool,
            onReady: @escaping () -> Void,
            onFailure: @escaping () -> Void
        ) {
            self.isPlaybackActive = isPlaybackActive
            self.onReady = onReady
            self.onFailure = onFailure
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

        func configure(videoURL: URL, playerView: StartupPlayerUIView) {
            guard self.videoURL != videoURL else {
                self.applyPlaybackState()
                return
            }

            self.tearDownPlayer()
            self.videoURL = videoURL
            self.didReportReady = false
            self.didReportFailure = false

            let templateItem: AVPlayerItem = AVPlayerItem(url: videoURL)
            let player: AVQueuePlayer = AVQueuePlayer()
            player.actionAtItemEnd = .advance
            player.allowsExternalPlayback = false
            player.automaticallyWaitsToMinimizeStalling = true
            player.isMuted = false
            player.volume = 1

            self.player = player
            self.playerLooper = AVPlayerLooper(player: player, templateItem: templateItem)
            playerView.player = player
            self.observeStatus(of: player)
            self.observeCurrentItem(of: player)
            self.activateAmbientAudioSession()
            self.applyPlaybackState()
        }

        func tearDown() {
            self.tearDownPlayer()
            self.deactivateAudioSession()
            self.onReady = {}
            self.onFailure = {}
        }

        private func observeStatus(of player: AVQueuePlayer) {
            self.statusObservation = player.observe(\.status, options: [.initial, .new]) { [weak self] player, _ in
                let status: AVPlayer.Status = player.status
                let errorDescription: String? = player.error?.localizedDescription
                DispatchQueue.main.async {
                    self?.handlePlayerStatus(status, errorDescription: errorDescription)
                }
            }
        }

        private func observeCurrentItem(of player: AVQueuePlayer) {
            self.currentItemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
                let currentItem: AVPlayerItem? = player.currentItem
                DispatchQueue.main.async {
                    self?.observeStatus(of: currentItem)
                }
            }
        }

        private func observeStatus(of item: AVPlayerItem?) {
            self.itemStatusObservation = nil
            guard let item,
                  item === self.player?.currentItem else {
                return
            }

            self.itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard item.status == .failed else {
                    return
                }

                let detail: String = item.error?.localizedDescription ?? "AVPlayerItem entered the failed state"
                DispatchQueue.main.async {
                    self?.reportFailure(detail: detail)
                }
            }
        }

        private func handlePlayerStatus(_ status: AVPlayer.Status, errorDescription: String?) {
            switch status {
            case .unknown:
                return
            case .readyToPlay:
                guard self.didReportReady == false else {
                    return
                }

                self.didReportReady = true
                self.didReportFailure = false
                self.applyPlaybackState()
                self.onReady()
            case .failed:
                self.reportFailure(detail: errorDescription ?? "AVQueuePlayer entered the failed state")
            @unknown default:
                self.reportFailure(detail: "AVQueuePlayer entered an unknown state")
            }
        }

        private func reportFailure(detail: String) {
            guard self.didReportFailure == false else {
                return
            }

            #if DEBUG
            print("[BrowseCraftStartup] video playback failed: \(detail)")
            #endif

            self.didReportFailure = true
            self.didReportReady = false
            self.player?.pause()
            self.onFailure()
        }

        private func applyPlaybackState() {
            guard let player: AVQueuePlayer = self.player else {
                return
            }

            if self.isPlaybackActive {
                player.play()
            } else {
                player.pause()
            }
        }

        private func activateAmbientAudioSession() {
            let audioSession: AVAudioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(.ambient, mode: .default)
                try audioSession.setActive(true)
                self.didActivateAudioSession = true
            } catch {
                #if DEBUG
                print("[BrowseCraftStartup] ambient audio session activation failed: \(error.localizedDescription)")
                #endif
            }
        }

        private func deactivateAudioSession() {
            guard self.didActivateAudioSession else {
                return
            }

            self.didActivateAudioSession = false
            do {
                try AVAudioSession.sharedInstance().setActive(
                    false,
                    options: .notifyOthersOnDeactivation
                )
            } catch {
                #if DEBUG
                print("[BrowseCraftStartup] audio session deactivation failed: \(error.localizedDescription)")
                #endif
            }
        }

        private func tearDownPlayer() {
            self.statusObservation = nil
            self.currentItemObservation = nil
            self.itemStatusObservation = nil
            self.playerLooper?.disableLooping()
            self.playerLooper = nil
            self.player?.pause()
            self.player?.removeAllItems()
            self.player = nil
            self.videoURL = nil
        }
    }
}

final class StartupPlayerUIView: UIView {
    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    var player: AVPlayer? {
        get {
            return self.playerLayer.player
        }
        set {
            self.playerLayer.player = newValue
        }
    }

    private var playerLayer: AVPlayerLayer {
        let playerLayer: AVPlayerLayer = self.layer as! AVPlayerLayer
        playerLayer.videoGravity = .resizeAspectFill
        return playerLayer
    }
}
