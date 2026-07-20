import Foundation

enum RSSAudioPlayerPageBuilder {
    static func dataURL(
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
