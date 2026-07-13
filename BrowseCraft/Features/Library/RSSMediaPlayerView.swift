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
        guard let playerURL: URL = Self.audioPlayerDataURL(
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

    private static func audioPlayerDataURL(
        title: String,
        mediaURL: URL,
        posterURL: URL?,
        sourcePageURL: URL?
    ) -> URL? {
        let posterHTML: String
        if let posterURL: URL = posterURL {
            posterHTML = """
            <img class="poster" src="\(Self.htmlEscaped(posterURL.absoluteString))" alt="" />
            """
        } else {
            posterHTML = """
            <div class="poster placeholder"></div>
            """
        }

        let sourceHTML: String
        if let sourcePageURL: URL = sourcePageURL {
            sourceHTML = """
            <a class="source" href="\(Self.htmlEscaped(sourcePageURL.absoluteString))">Open original page</a>
            """
        } else {
            sourceHTML = ""
        }

        let html: String = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <style>
            :root { color-scheme: light dark; }
            body {
              margin: 0;
              min-height: 100vh;
              display: flex;
              align-items: center;
              justify-content: center;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
              background: #101318;
              color: #f7f8fa;
            }
            main {
              width: min(720px, calc(100vw - 32px));
              display: grid;
              gap: 22px;
            }
            .poster {
              width: 100%;
              aspect-ratio: 16 / 9;
              object-fit: cover;
              border-radius: 8px;
              background: #252b34;
            }
            .placeholder {
              background: linear-gradient(135deg, #252b34, #38404c);
            }
            h1 {
              margin: 0;
              font-size: 22px;
              line-height: 1.3;
              font-weight: 700;
            }
            audio {
              width: 100%;
            }
            .source {
              color: #9db4ff;
              font-size: 15px;
              text-decoration: none;
            }
          </style>
        </head>
        <body>
          <main>
            \(posterHTML)
            <h1>\(Self.htmlEscaped(title))</h1>
            <audio id="rss-audio" controls autoplay preload="auto" src="\(Self.htmlEscaped(mediaURL.absoluteString))"></audio>
            \(sourceHTML)
          </main>
          <script>
            const audio = document.getElementById("rss-audio");
            if (audio) {
              const play = () => audio.play().catch(() => {});
              if (document.readyState === "loading") {
                document.addEventListener("DOMContentLoaded", play, { once: true });
              } else {
                play();
              }
            }
          </script>
        </body>
        </html>
        """

        let encodedHTML: String = Data(html.utf8).base64EncodedString()
        return URL(string: "data:text/html;charset=utf-8;base64,\(encodedHTML)")
    }

    private static func htmlEscaped(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
