import BrowseCraftCore
import BrowseCraftDomain
import Nuke
import NukeUI
import SwiftUI

// 中文注释：ItemThumbnailImageView 只用于 Library/History item 缩略图，缓存池独立于漫画阅读页图片。
struct ItemThumbnailImageView: View {
    @Environment(\.browserRequestHeaderProvider) private var browserRequestHeaderProvider
    @Environment(\.systemCookieHeaderProvider) private var systemCookieHeaderProvider
    @Environment(\.itemThumbnailImagePipeline) private var thumbnailImagePipeline

    let urlString: String?
    let refererURLString: String?
    let requestConfig: RequestConfig?
    let placeholderImageName: String?
    // 中文注释：诊断用——`@State` 的初值只在视图身份首次建立时被采用，
    // 因此同一个视图实例恒为同一个 ID，视图一旦被重建就换一个。只进日志。
    @State private var diagnosticViewID: String = String(UUID().uuidString.prefix(8))
    @State private var candidateIndex: Int = 0
    @State private var displaySize: CGSize = .zero
    @State private var request: ImageRequest?

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
        let candidate: String? = Self.urlCandidate(at: self.candidateIndex, in: urlCandidates)
        Group {
            if let urlString: String = candidate,
               let request: ImageRequest = self.request {
                LazyImage(request: request) { state in
                    if let image = state.image {
                        // 中文注释：aspectFill 必须由中立容器承载并裁剪——直接放大图片会让它的
                        // 布局尺寸超出单元格，外层 clipShape 裁的是撑大后的边界，结果溢出到相邻 item。
                        // NukeUI 0.8 的 resizingMode(.aspectFill) 内部等价于 scaleAspectFill + clipsToBounds。
                        Color.clear
                            .overlay {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                            .clipped()
                    } else if let error: Error = state.error {
                        self.placeholder
                            .onAppear {
                                // 中文注释：`BC-CATALOG-022`——先留错误再换候选地址。
                                // 换候选会把上一个地址的失败盖掉，不先记就永远不知道它为什么失败。
                                ImageRequestFactory.logFailure(
                                    urlString: urlString,
                                    error: error,
                                    event: "thumbnail-failure"
                                )
                                self.advanceToNextCandidateIfAvailable(candidateCount: urlCandidates.count)
                            }
                    } else {
                        self.placeholder
                    }
                }
                .pipeline(self.thumbnailImagePipeline.pipeline)
                .id(urlString)
            } else {
                self.placeholder
            }
        }
        .measuringDisplaySize(into: self.$displaySize)
        .task(id: self.requestIdentity(for: candidate)) {
            // 中文注释：同 CoverImageView——请求只在标识变化时构造一次；缩略图池的缓存键与低优先级在 thumbnailRequest 里加。
            self.request = self.requestIdentity(for: candidate).flatMap { identity in
                RemoteImageRequestBuilder.makeRequest(
                    identity,
                    browserRequestHeaderProvider: self.browserRequestHeaderProvider,
                    systemCookieHeaderProvider: self.systemCookieHeaderProvider,
                    diagnosticViewID: self.diagnosticViewID
                )
            }
            .map(self.thumbnailImagePipeline.thumbnailRequest(from:))
        }
        .onChange(of: self.urlString) {
            self.candidateIndex = 0
        }
    }

    private func requestIdentity(for candidate: String?) -> RemoteImageRequestIdentity? {
        guard let candidate else {
            return nil
        }
        return RemoteImageRequestIdentity(
            urlString: candidate,
            refererURLString: self.refererURLString,
            requestConfig: self.requestConfig,
            additionalHeaders: nil,
            displaySize: self.displaySize
        )
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
