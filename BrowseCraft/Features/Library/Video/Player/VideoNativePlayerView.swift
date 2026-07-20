import BrowseCraftCore
import KSPlayer
import SwiftUI
import UIKit

// 中文注释：VideoNativePlayerView 使用 KSPlayer 的 UIKit 播放器承载原生直链，避免上游 SwiftUI
// Coordinator 在视图更新事务中同步发布状态。
struct VideoNativePlayerView<Controls: View>: View {
    @Environment(\.browserRequestHeaderProvider) private var browserRequestHeaderProvider

    let mediaURL: URL
    let requestConfig: SourcePlaybackRequestConfig?
    let title: String
    let controls: () -> Controls
    let onProgress: (TimeInterval, TimeInterval) -> Void
    let onReadyToPlay: (@escaping (TimeInterval) -> Void) -> Void
    let onClose: () -> Void

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
    }

    var body: some View {
        NativePlayerRepresentable(
            mediaURL: self.mediaURL,
            requestConfig: self.requestConfig,
            browserRequestHeaderProvider: self.browserRequestHeaderProvider,
            title: self.title,
            onProgress: self.onProgress,
            onReadyToPlay: self.onReadyToPlay,
            onClose: self.onClose
        )
        .overlay(alignment: .bottom) {
            self.controls()
                .padding(.horizontal, 28)
                .padding(.bottom, 76)
        }
        .ignoresSafeArea()
    }
}

private struct NativePlayerRepresentable: UIViewRepresentable {
    struct Configuration: Hashable {
        let mediaURL: URL
        let requestConfig: SourcePlaybackRequestConfig?
    }

    let mediaURL: URL
    let requestConfig: SourcePlaybackRequestConfig?
    let browserRequestHeaderProvider: any BrowserRequestHeaderProviding
    let title: String
    let onProgress: (TimeInterval, TimeInterval) -> Void
    let onReadyToPlay: (@escaping (TimeInterval) -> Void) -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        return Coordinator(
            onProgress: self.onProgress,
            onReadyToPlay: self.onReadyToPlay,
            onClose: self.onClose
        )
    }

    func makeUIView(context: Context) -> IOSVideoPlayerView {
        let playerView: IOSVideoPlayerView = BrowseCraftNativePlayerView()
        context.coordinator.attach(to: playerView)
        self.configure(playerView, coordinator: context.coordinator)
        return playerView
    }

    func updateUIView(_ playerView: IOSVideoPlayerView, context: Context) {
        context.coordinator.updateCallbacks(
            onProgress: self.onProgress,
            onReadyToPlay: self.onReadyToPlay,
            onClose: self.onClose
        )
        self.configure(playerView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ playerView: IOSVideoPlayerView, coordinator: Coordinator) {
        playerView.delegate = nil
        playerView.backBlock = nil
        playerView.resetPlayer()
        coordinator.detach()
    }

    private func configure(_ playerView: IOSVideoPlayerView, coordinator: Coordinator) {
        let configuration: Configuration = Configuration(
            mediaURL: self.mediaURL,
            requestConfig: self.requestConfig
        )

        playerView.titleLabel.text = self.title
        playerView.backBlock = { [weak coordinator] in
            coordinator?.close()
        }

        guard coordinator.configuration != configuration else {
            return
        }

        coordinator.configuration = configuration
        playerView.set(
            url: self.mediaURL,
            options: Self.playbackOptions(
                mediaURL: self.mediaURL,
                requestConfig: self.requestConfig,
                browserRequestHeaderProvider: self.browserRequestHeaderProvider
            )
        )
        playerView.titleLabel.text = self.title
    }

    private static func playbackOptions(
        mediaURL: URL,
        requestConfig: SourcePlaybackRequestConfig?,
        browserRequestHeaderProvider: any BrowserRequestHeaderProviding
    ) -> KSOptions {
        let options: KSOptions = KSOptions()
        guard let requestConfig: SourcePlaybackRequestConfig else {
            return options
        }

        var headers: [String: String] = browserRequestHeaderProvider.defaultHeaders(
            for: mediaURL,
            referer: requestConfig.referer,
            includeOrigin: true
        )
        headers = RequestHeaderFields.applyingOverrides(requestConfig.headers, to: headers)
        if let referer: URL = requestConfig.referer,
           RequestHeaderFields.containsHeader("Referer", in: headers) == false {
            headers["Referer"] = referer.absoluteString
        }
        if let userAgent: String = requestConfig.userAgent,
           RequestHeaderFields.containsHeader("User-Agent", in: headers) == false {
            headers["User-Agent"] = userAgent
        }
        if RequestHeaderFields.containsHeader("Origin", in: headers) == false,
           let origin: String = RequestHeaderFields.originHeader(from: requestConfig.referer) {
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
        let mediaLocation: String = (mediaURL.host ?? "unknown") + mediaURL.path
        print(
            "[BrowseCraftVideoPlayer] playback-options " +
            "media=\(mediaLocation) " +
            "hasReferer=\(options.referer != nil) " +
            "hasUserAgent=\(options.userAgent != nil) " +
            "headers=\(headers.keys.sorted().joined(separator: ","))"
        )
        #endif

        return options
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency PlayerControllerDelegate {
        var configuration: Configuration?

        private weak var playerView: IOSVideoPlayerView?
        private var onProgress: (TimeInterval, TimeInterval) -> Void
        private var onReadyToPlay: (@escaping (TimeInterval) -> Void) -> Void
        private var onClose: () -> Void

        init(
            onProgress: @escaping (TimeInterval, TimeInterval) -> Void,
            onReadyToPlay: @escaping (@escaping (TimeInterval) -> Void) -> Void,
            onClose: @escaping () -> Void
        ) {
            self.onProgress = onProgress
            self.onReadyToPlay = onReadyToPlay
            self.onClose = onClose
        }

        func attach(to playerView: IOSVideoPlayerView) {
            self.playerView = playerView
            playerView.delegate = self
        }

        func detach() {
            self.playerView = nil
            self.configuration = nil
        }

        func updateCallbacks(
            onProgress: @escaping (TimeInterval, TimeInterval) -> Void,
            onReadyToPlay: @escaping (@escaping (TimeInterval) -> Void) -> Void,
            onClose: @escaping () -> Void
        ) {
            self.onProgress = onProgress
            self.onReadyToPlay = onReadyToPlay
            self.onClose = onClose
        }

        func close() {
            self.onClose()
        }

        func playerController(state: KSPlayerState) {
            guard state == .readyToPlay else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let playerView: IOSVideoPlayerView = self.playerView else {
                    return
                }

                playerView.play()
                self.onReadyToPlay { [weak playerView] playbackTime in
                    playerView?.seek(time: playbackTime, completion: { _ in })
                }
            }
        }

        func playerController(currentTime: TimeInterval, totalTime: TimeInterval) {
            let onProgress: (TimeInterval, TimeInterval) -> Void = self.onProgress
            DispatchQueue.main.async {
                onProgress(currentTime, totalTime)
            }
        }

        func playerController(finish _: Error?) {}

        func playerController(maskShow _: Bool) {}

        func playerController(action _: PlayerButtonType) {}

        func playerController(bufferedCount _: Int, consumeTime _: TimeInterval) {}

        func playerController(seek _: TimeInterval) {}
    }
}

/// 中文注释：KSPlayer 默认把 25pt 宽的返回按钮放在播放器 y=0 的顶栏中。
/// 播放器忽略 SwiftUI 安全区后，该位置会落入状态栏或灵动岛区域，因此在适配层修正布局和点击传递。
private final class BrowseCraftNativePlayerView: IOSVideoPlayerView {
    override func customizeUIComponents() {
        super.customizeUIComponents()

        self.backButton.accessibilityLabel = "Close Player"
        self.backButton.accessibilityIdentifier = "video-native-player-close"
        self.tapGesture.cancelsTouchesInView = false
        self.updateBackButtonLayout()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        self.updateBackButtonLayout()
    }

    private func updateBackButtonLayout() {
        self.navigationBar.transform = CGAffineTransform(
            translationX: 0,
            y: self.safeAreaInsets.top
        )

        self.backButton.constraints
            .first(where: { constraint in
                constraint.firstAttribute == .width
                    && constraint.relation == .equal
            })?
            .constant = 44
    }
}
