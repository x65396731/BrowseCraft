import SwiftUI

struct RSSHeroCarouselView: View {
    let item: ContentItem
    let originalURL: URL?
    let media: RSSContentPayload.Media?
    @Binding var selectedImageIndex: Int
    let openMedia: (RSSContentPayload.Media) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            let imageURLs: [String] = self.heroImageURLs

            if imageURLs.isEmpty {
                self.heroPlaceholder
            } else {
                TabView(selection: self.$selectedImageIndex) {
                    ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, imageURL in
                        CoverImageView(urlString: imageURL)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if imageURLs.count > 1 {
                    self.heroPagination(count: imageURLs.count)
                        .padding(.bottom, 38)
                }
            }

        }
        .overlay {
            if let media: RSSContentPayload.Media = self.media {
                self.heroMediaButton(media)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private func heroMediaButton(_ media: RSSContentPayload.Media) -> some View {
        Button {
            self.openMedia(media)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.34))
                    .frame(width: 86, height: 86)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.22))
                            .blur(radius: 1)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.88), lineWidth: 2)
                    )

                Image(systemName: "play.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(Color.white)
                    .offset(x: media.kind == .audio ? 0 : 2)
            }
            .shadow(color: Color.black.opacity(0.24), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(self.mediaTitle(media))
    }

    private var heroPlaceholder: some View {
        LinearGradient(
            colors: [
                Color(red: 58 / 255, green: 205 / 255, blue: 225 / 255),
                Color(red: 244 / 255, green: 249 / 255, blue: 250 / 255)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            Image(systemName: "newspaper")
                .font(.system(size: 54, weight: .light))
                .foregroundColor(Color.white.opacity(0.85))
        )
    }

    private func heroPagination(count: Int) -> some View {
        HStack(spacing: 24) {
            ForEach(self.visiblePaginationIndexes(count: count), id: \.self) { index in
                if index == self.selectedImageIndex {
                    Image(systemName: "sparkle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.white)
                        .frame(width: 17, height: 18)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 9, height: 9)
                }
            }
        }
        .frame(minWidth: 69, minHeight: 24)
        .animation(.easeInOut(duration: 0.2), value: self.selectedImageIndex)
    }

    private func visiblePaginationIndexes(count: Int) -> [Int] {
        let maxVisibleCount: Int = 5
        guard count > maxVisibleCount else {
            return Array(0..<count)
        }

        let halfVisibleCount: Int = maxVisibleCount / 2
        let lowerBound: Int = max(0, min(self.selectedImageIndex - halfVisibleCount, count - maxVisibleCount))
        return Array(lowerBound..<(lowerBound + maxVisibleCount))
    }

    private var heroImageURLs: [String] {
        var urls: [String] = []
        var indexesByDedupeKey: [String: Int] = [:]

        func append(_ urlString: String?) {
            guard let urlString: String = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
                  urlString.isEmpty == false else {
                return
            }

            let displayURLString: String = Self.displayImageURLString(from: urlString, baseURL: self.originalURL)
            let dedupeKey: String = Self.heroImageDedupeKey(for: displayURLString)
            if let existingIndex: Int = indexesByDedupeKey[dedupeKey] {
                if Self.heroImageQualityScore(for: displayURLString) > Self.heroImageQualityScore(for: urls[existingIndex]) {
                    urls[existingIndex] = displayURLString
                }
                return
            }

            indexesByDedupeKey[dedupeKey] = urls.count
            urls.append(displayURLString)
        }

        append(self.item.coverURL)

        if let payload: RSSContentPayload = self.item.richContent
            ?? RSSContentPayload.decode(from: self.item.latestText) {
            for block in payload.blocks where block.kind == .image {
                append(block.imageURL)
            }
        }

        return urls
    }

    private static func displayImageURLString(from urlString: String, baseURL: URL?) -> String {
        guard let url: URL = URL(string: urlString, relativeTo: baseURL)?.absoluteURL else {
            return urlString
        }

        return url.absoluteString
    }

    private static func heroImageDedupeKey(for urlString: String) -> String {
        guard let url: URL = URL(string: urlString),
              let host: String = url.host?.lowercased() else {
            return urlString
        }

        if Self.hasImageTransformQuery(url) {
            var components: URLComponents? = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.query = nil
            return components?.url?.absoluteString ?? urlString
        }

        guard host == "img.jiemian.com" else {
            return urlString
        }

        let filename: String = url.deletingPathExtension().lastPathComponent
        guard let normalizedFilename: String = Self.normalizedJiemianImageFilename(filename),
              normalizedFilename != filename else {
            return urlString
        }

        var components: URLComponents? = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let normalizedLastPathComponent: String
        if url.pathExtension.isEmpty {
            normalizedLastPathComponent = normalizedFilename
        } else {
            normalizedLastPathComponent = "\(normalizedFilename).\(url.pathExtension)"
        }

        components?.path = url
            .deletingLastPathComponent()
            .appendingPathComponent(normalizedLastPathComponent)
            .path
        return components?.url?.absoluteString ?? urlString
    }

    private static func heroImageQualityScore(for urlString: String) -> Int {
        guard let url: URL = URL(string: urlString),
              url.host?.lowercased() == "img.jiemian.com" else {
            return 0
        }

        let filename: String = url.deletingPathExtension().lastPathComponent
        guard let normalizedFilename: String = Self.normalizedJiemianImageFilename(filename),
              normalizedFilename != filename else {
            return 1
        }

        return 0
    }

    private static func hasImageTransformQuery(_ url: URL) -> Bool {
        guard let query: String = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery?.lowercased() else {
            return false
        }

        return query.contains("imageview2") || query.contains("imagemogr2")
    }

    private static func normalizedJiemianImageFilename(_ filename: String) -> String? {
        let pattern: String = #"_[a-z]?\d{2,5}x\d{2,5}$"#
        guard let regex: NSRegularExpression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range: NSRange = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        return regex.stringByReplacingMatches(
            in: filename,
            range: range,
            withTemplate: ""
        )
    }

    private func mediaTitle(_ media: RSSContentPayload.Media) -> String {
        switch media.kind {
        case .audio:
            return "Audio"
        case .video:
            return "Video"
        case .article:
            return "Article"
        }
    }
}
