import Foundation
import SwiftUI

// 中文注释：RSSMediaPlayerView 是 RSS 专属播放 host，只复用播放物理层，不进入 Video Runtime。
struct RSSMediaPlayerView: View {
    @Environment(\.openURL) private var openURL

    let media: RSSContentPayload.Media
    let title: String
    let onClose: () -> Void

    var body: some View {
        Group {
            if let mediaURL: URL = URL(string: self.media.url) {
                switch self.media.playbackMode {
                case .directMedia:
                    self.directMediaPlayer(mediaURL)
                case .webPage:
                    self.webPagePlayer(mediaURL)
                }
            } else {
                self.unavailablePlayer
            }
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func directMediaPlayer(_ mediaURL: URL) -> some View {
        switch self.media.kind {
        case .audio:
            if let request: VideoWebPlayerRequest = self.audioPlayerRequest(mediaURL: mediaURL) {
                VideoWebPlayerView(
                    request: request,
                    title: self.title,
                    controls: {
                        EmptyView()
                    },
                    onClose: self.onClose
                )
            } else {
                self.unavailablePlayer
            }
        case .video:
            VideoNativePlayerView(
                mediaURL: mediaURL,
                requestConfig: self.playbackRequestConfig(),
                title: self.title,
                controls: {
                    EmptyView()
                },
                onProgress: { _, _ in },
                onReadyToPlay: { _ in },
                onClose: self.onClose
            )
            .background(Color.black)
        case .article:
            self.unavailablePlayer
        }
    }

    @ViewBuilder
    private func webPagePlayer(_ mediaURL: URL) -> some View {
        if Self.isKnownRestrictedPlaybackPage(mediaURL) {
            self.restrictedWebPagePlayer(mediaURL)
        } else {
            VideoWebPlayerView(
                request: VideoWebPlayerRequest(url: mediaURL),
                title: self.title,
                controls: {
                    EmptyView()
                },
                onClose: self.onClose
            )
        }
    }

    private func restrictedWebPagePlayer(_ mediaURL: URL) -> some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()

                Button(
                    action: self.onClose,
                    label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                )
                .accessibilityLabel("Close Player")
            }

            Spacer(minLength: 0)

            Image(systemName: self.media.kind == .audio ? "waveform.circle" : "play.rectangle")
                .font(.system(size: 46, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("Cannot Play In App")
                    .font(.title3.weight(.semibold))

                Text("This site requires its own app or web player for playback.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                self.openURL(mediaURL)
            } label: {
                Label("Open Original Page", systemImage: "safari")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unavailablePlayer: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()

                Button(
                    action: self.onClose,
                    label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                )
                .accessibilityLabel("Close Player")
            }

            Spacer(minLength: 0)

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 42, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 6) {
                Text("Media Unavailable")
                    .font(.title3.weight(.semibold))

                Text("Open the original page to continue.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func audioPlayerRequest(mediaURL: URL) -> VideoWebPlayerRequest? {
        guard let playerURL: URL = RSSAudioPlayerPageBuilder.dataURL(
            title: self.title,
            mediaURL: mediaURL,
            posterURL: self.url(from: self.media.posterURL),
            sourcePageURL: self.url(from: self.media.sourcePageURL)
        ) else {
            return nil
        }

        return VideoWebPlayerRequest(url: playerURL, referer: self.url(from: self.media.sourcePageURL))
    }

    private func playbackRequestConfig() -> SourcePlaybackRequestConfig? {
        guard let sourcePageURL: URL = self.url(from: self.media.sourcePageURL) else {
            return nil
        }

        return SourcePlaybackRequestConfig(
            headers: [:],
            referer: sourcePageURL,
            userAgent: nil
        )
    }

    private func url(from string: String?) -> URL? {
        guard let string: String = string else {
            return nil
        }

        return URL(string: string)
    }

    private static func isKnownRestrictedPlaybackPage(_ url: URL) -> Bool {
        guard let host: String = url.host?.lowercased() else {
            return false
        }

        let isGcoresHost: Bool = host == "gcores.com" || host == "www.gcores.com"
        let path: String = url.path.lowercased()
        return isGcoresHost && (path.hasPrefix("/radios/") || path.hasPrefix("/videos/"))
    }
}
