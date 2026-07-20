import NukeUI
import SwiftUI

// 中文注释：CoverImageView.swift 属于共享界面组件层，用于说明本文件承载的核心职责。

/// 中文注释：共享封面图片视图，负责展示列表和详情中的封面图。
/// 中文注释：NukeUI 只出现在 UI 边界层，领域层和应用层不依赖图片库。
struct CoverImageView: View {
    @Environment(\.browserRequestHeaderProvider) private var browserRequestHeaderProvider
    @Environment(\.systemCookieHeaderProvider) private var systemCookieHeaderProvider

    let urlString: String?
    let refererURLString: String?
    let requestConfig: RequestConfig?
    let placeholderImageName: String?
    @State private var candidateIndex: Int = 0

    init(
        urlString: String?,
        refererURLString: String? = nil,
        requestConfig: RequestConfig? = nil,
        placeholderImageName: String? = nil
    ) {
        self.urlString = urlString
        self.refererURLString = refererURLString
        self.requestConfig = requestConfig
        self.placeholderImageName = placeholderImageName
    }

    var body: some View {
        let urlCandidates: [String] = Self.urlCandidates(from: self.urlString)
        Group {
            if let urlString: String = Self.urlCandidate(at: self.candidateIndex, in: urlCandidates),
               let request: ImageRequest = ImageRequestFactory.makeRequest(
                urlString: urlString,
                refererURLString: self.refererURLString,
                requestConfig: self.requestConfig,
                browserRequestHeaderProvider: self.browserRequestHeaderProvider,
                systemCookieHeaderProvider: self.systemCookieHeaderProvider
               ) {
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

    @ViewBuilder
    private var placeholder: some View {
        if let placeholderImageName: String = self.placeholderImageName {
            SwiftUI.Image(placeholderImageName)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Rectangle()
                    .fill(Color(.secondarySystemFill))

                SwiftUI.Image(systemName: "photo")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
