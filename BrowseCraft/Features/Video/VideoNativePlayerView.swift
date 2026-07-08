import BrowseCraftCore
import KSPlayer
import SwiftUI

// 中文注释：VideoNativePlayerView 是 KSPlayer 的物理层封装；上层只传入直链和播放回调。
struct VideoNativePlayerView<Controls: View>: View {
    let mediaURL: URL
    let requestConfig: SourcePlaybackRequestConfig?
    let title: String
    let controls: () -> Controls
    let onProgress: (TimeInterval, TimeInterval) -> Void
    let onReadyToPlay: (@escaping (TimeInterval) -> Void) -> Void
    let onClose: () -> Void

    @StateObject private var playerCoordinator: KSVideoPlayer.Coordinator

    init(
        mediaURL: URL,
        requestConfig: SourcePlaybackRequestConfig?,
        title: String,
        @ViewBuilder controls: @escaping () -> Controls,
        onProgress: @escaping (TimeInterval, TimeInterval) -> Void,
        onReadyToPlay: @escaping (@escaping (TimeInterval) -> Void) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.mediaURL = mediaURL
        self.requestConfig = requestConfig
        self.title = title
        self.controls = controls
        self.onProgress = onProgress
        self.onReadyToPlay = onReadyToPlay
        self.onClose = onClose
        _playerCoordinator = StateObject(wrappedValue: KSVideoPlayer.Coordinator())
    }

    var body: some View {
        KSVideoPlayerView(
            coordinator: self.playerCoordinator,
            url: self.mediaURL,
            options: self.playbackOptions(),
            title: self.title
        )
        .overlay(alignment: .bottom) {
            self.controls()
                .padding(.horizontal, 28)
                .padding(.bottom, 76)
        }
        .onChange(of: self.mediaURL) { _, newURL in
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
        playerLayer.set(url: mediaURL, options: self.playbackOptions())
        self.configureBackBlock(for: playerLayer.player.view)
    }

    private func playbackOptions() -> KSOptions {
        let options: KSOptions = KSOptions()
        guard let requestConfig: SourcePlaybackRequestConfig = self.requestConfig else {
            return options
        }

        var headers: [String: String] = requestConfig.headers
        if let referer: URL = requestConfig.referer,
           headers.keys.contains(where: { $0.caseInsensitiveCompare("Referer") == .orderedSame }) == false {
            headers["Referer"] = referer.absoluteString
        }
        if let userAgent: String = requestConfig.userAgent,
           headers.keys.contains(where: { $0.caseInsensitiveCompare("User-Agent") == .orderedSame }) == false {
            headers["User-Agent"] = userAgent
        }
        if headers.keys.contains(where: { $0.caseInsensitiveCompare("Origin") == .orderedSame }) == false,
           let origin: String = self.originHeader(from: requestConfig.referer) {
            headers["Origin"] = origin
        }

        if headers.isEmpty == false {
            options.appendHeader(headers)
        }
        options.referer = requestConfig.referer?.absoluteString
        if let userAgent: String = requestConfig.userAgent ?? headers.first(where: { element in
            element.key.caseInsensitiveCompare("User-Agent") == .orderedSame
        })?.value {
            options.userAgent = userAgent
        }

        #if DEBUG
        print(
            "[BrowseCraftVideoPlayer] playback-options " +
            "media=\(self.mediaURL.absoluteString) " +
            "referer=\(options.referer ?? "nil") " +
            "userAgent=\(options.userAgent ?? "nil") " +
            "headers=\(headers.keys.sorted().joined(separator: ","))"
        )
        #endif

        return options
    }

    private func originHeader(from url: URL?) -> String? {
        guard let url: URL,
              let scheme: String = url.scheme,
              let host: String = url.host else {
            return nil
        }

        if let port: Int = url.port {
            return "\(scheme)://\(host):\(port)"
        }

        return "\(scheme)://\(host)"
    }

    private func installPlayerCallbacks() {
        self.playerCoordinator.onPlay = { currentTime, totalTime in
            self.onProgress(currentTime, totalTime)
        }
        self.playerCoordinator.onStateChanged = { layer, state in
            self.configureBackBlock(for: layer.player.view)
            if state == .readyToPlay {
                DispatchQueue.main.async {
                    layer.play()
                    self.onReadyToPlay { playbackTime in
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
            self.onClose()
        }
    }
}
