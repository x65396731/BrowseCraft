import Nuke
import NukeUI
import SwiftUI

// 中文注释：ItemThumbnailImageView 只用于 Library/History item 缩略图，缓存池独立于漫画阅读页图片。
struct ItemThumbnailImageView: View {
    let urlString: String?
    let refererURLString: String?
    let requestConfig: RequestConfig?
    @State private var candidateIndex: Int = 0

    init(
        urlString: String?,
        refererURLString: String? = nil,
        requestConfig: RequestConfig? = nil
    ) {
        self.urlString = urlString
        self.refererURLString = refererURLString
        self.requestConfig = requestConfig
    }

    var body: some View {
        let urlCandidates: [String] = Self.urlCandidates(from: self.urlString)
        Group {
            if let urlString: String = Self.urlCandidate(at: self.candidateIndex, in: urlCandidates),
               let request: ImageRequest = self.thumbnailRequest(urlString: urlString) {
                LazyImage(source: request) { state in
                    if let image = state.image {
                        image
                            .resizingMode(.aspectFill)
                    } else if state.error != nil {
                        self.placeholder
                            .onAppear {
                                self.advanceToNextCandidateIfAvailable(candidateCount: urlCandidates.count)
                            }
                    } else {
                        self.placeholder
                    }
                }
                .pipeline(ItemThumbnailImageCachePlugin.shared.pipeline)
                .id(urlString)
            } else {
                self.placeholder
            }
        }
        .onChange(of: self.urlString) {
            self.candidateIndex = 0
        }
    }

    private func advanceToNextCandidateIfAvailable(candidateCount: Int) {
        if self.candidateIndex + 1 < candidateCount {
            self.candidateIndex += 1
        }
    }

    private static func urlCandidate(at index: Int, in candidates: [String]) -> String? {
        guard index >= 0, index < candidates.count else {
            return nil
        }

        return candidates[index]
    }

    private static func urlCandidates(from urlString: String?) -> [String] {
        guard let urlString: String = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              urlString.isEmpty == false else {
            return []
        }

        if urlString.hasPrefix("//") {
            return ["https:\(urlString)"]
        }

        guard let url: URL = URL(string: urlString) else {
            return []
        }

        guard url.scheme?.lowercased() == "http",
              var components: URLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [urlString]
        }

        components.scheme = "https"
        guard let httpsURLString: String = components.url?.absoluteString,
              httpsURLString != urlString else {
            return [urlString]
        }

        return [httpsURLString, urlString]
    }

    private func thumbnailRequest(urlString: String) -> ImageRequest? {
        guard let request: ImageRequest = ImageRequestFactory.makeRequest(
                urlString: urlString,
                refererURLString: self.refererURLString,
                requestConfig: self.requestConfig
              ) else {
            return nil
        }

        return ItemThumbnailImageCachePlugin.thumbnailRequest(from: request)
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(Color(.secondarySystemFill))

            SwiftUI.Image(systemName: "photo")
                .font(.title2)
                .foregroundColor(.secondary)
        }
    }
}
