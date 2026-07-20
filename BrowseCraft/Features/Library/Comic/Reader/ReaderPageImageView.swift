import Nuke
import NukeUI
import SwiftUI
import UIKit

// 中文注释：ReaderPageImageView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：ReaderPageImageView 是 struct，负责本模块中的对应职责。
struct ReaderPageImageView: View {
    @Environment(\.browserRequestHeaderProvider) private var browserRequestHeaderProvider
    @Environment(\.systemCookieHeaderProvider) private var systemCookieHeaderProvider

    let resource: ReaderPageResource
    let pageNumber: Int
    let refererURLString: String?
    let requestConfig: RequestConfig?
    let additionalHeaders: [String: String]
    let loadProtectedImage: (ProtectedReaderImageReference, CGFloat) async throws -> UIImage

    init(
        resource: ReaderPageResource,
        pageNumber: Int,
        refererURLString: String?,
        requestConfig: RequestConfig?,
        additionalHeaders: [String: String],
        loadProtectedImage: @escaping (ProtectedReaderImageReference, CGFloat) async throws -> UIImage
    ) {
        self.resource = resource
        self.pageNumber = pageNumber
        self.refererURLString = refererURLString
        self.requestConfig = requestConfig
        self.additionalHeaders = additionalHeaders
        self.loadProtectedImage = loadProtectedImage
    }

    init(
        pageURLString: String,
        pageNumber: Int,
        refererURLString: String?,
        requestConfig: RequestConfig?,
        additionalHeaders: [String: String]
    ) {
        self.init(
            resource: .remoteImageURL(pageURLString),
            pageNumber: pageNumber,
            refererURLString: refererURLString,
            requestConfig: requestConfig,
            additionalHeaders: additionalHeaders,
            loadProtectedImage: { _, _ in
                throw RuleExecutionError.protectedResource(
                    stage: .image,
                    sourceID: "unknown",
                    reason: "Protected resource loader is not configured"
                )
            }
        )
    }

    var body: some View {
        switch self.resource {
        case .remoteImageURL(let pageURLString):
            self.remoteImage(pageURLString: pageURLString)
        case .protectedResource(let reference):
            ProtectedReaderPageImageView(
                reference: reference,
                pageNumber: self.pageNumber,
                loadProtectedImage: self.loadProtectedImage
            )
            .id(reference)
        }
    }

    @MainActor
    @ViewBuilder
    private func remoteImage(pageURLString: String) -> some View {
        if let request: ImageRequest = self.makeImageRequest(pageURLString: pageURLString) {
            LazyImage(source: request) { state in
                if let image = state.image {
                    // 中文注释：阅读页按图片真实宽高比排版，避免固定比例把特殊长条页压成窄条。
                    ZStack {
                        image
                            .resizingMode(.aspectFit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(
                        self.aspectRatio(for: state.imageContainer?.image.size),
                        contentMode: .fit
                    )
                } else if state.error != nil {
                    self.errorView
                } else {
                    self.loadingView
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .accessibilityLabel("Page \(self.pageNumber)")
        } else {
            self.errorView
        }
    }

    @MainActor
    private func makeImageRequest(pageURLString: String) -> ImageRequest? {
        guard var request: ImageRequest = ImageRequestFactory.makeRequest(
            urlString: pageURLString,
            refererURLString: self.refererURLString,
            requestConfig: self.requestConfig,
            additionalHeaders: self.additionalHeaders,
            browserRequestHeaderProvider: self.browserRequestHeaderProvider,
            systemCookieHeaderProvider: self.systemCookieHeaderProvider
        ) else {
            return nil
        }

        request.processors = [
            ReaderImageProcessor(targetPixelWidth: ReaderImageSizing.targetPixelWidth)
        ]
        return request
    }

    private func aspectRatio(for imageSize: CGSize?) -> CGFloat {
        guard let imageSize: CGSize = imageSize,
              imageSize.width > 0,
              imageSize.height > 0 else {
            // 中文注释：加载完成前先使用常见漫画页比例占位，减少列表跳动。
            return 0.72
        }

        return imageSize.width / imageSize.height
    }

    private var loadingView: some View {
        ZStack {
            Rectangle()
                .fill(Color(.secondarySystemFill))
                .aspectRatio(0.72, contentMode: .fit)

            ProgressView()
        }
    }

    private var errorView: some View {
        ZStack {
            Rectangle()
                .fill(Color(.secondarySystemFill))
                .aspectRatio(0.72, contentMode: .fit)

            VStack(spacing: 8) {
                SwiftUI.Image(systemName: "exclamationmark.triangle")
                    .font(.title2)

                Text("Page \(self.pageNumber)")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
    }
}

private struct ProtectedReaderPageImageView: View {
    let reference: ProtectedReaderImageReference
    let pageNumber: Int
    let loadProtectedImage: (ProtectedReaderImageReference, CGFloat) async throws -> UIImage

    @State private var image: UIImage?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let image: UIImage = self.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(self.aspectRatio(for: image.size), contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                    .accessibilityLabel("Page \(self.pageNumber)")
            } else if self.errorMessage != nil {
                self.errorView
            } else {
                self.loadingView
            }
        }
        .task(id: self.reference.displayURLString) {
            await self.load()
        }
    }

    @MainActor
    private func load() async {
        guard self.image == nil,
              self.isLoading == false else {
            return
        }

        self.isLoading = true
        self.errorMessage = nil

        do {
            self.image = try await self.loadProtectedImage(
                self.reference,
                ReaderImageSizing.targetPixelWidth
            )
        } catch {
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            RuleExecutionErrorClassifier.log(error: error, stage: .image, event: "protected-reader-image-error")
        }

        self.isLoading = false
    }

    private func aspectRatio(for imageSize: CGSize) -> CGFloat {
        guard imageSize.width > 0,
              imageSize.height > 0 else {
            return 0.72
        }

        return imageSize.width / imageSize.height
    }

    private var loadingView: some View {
        ZStack {
            Rectangle()
                .fill(Color(.secondarySystemFill))
                .aspectRatio(0.72, contentMode: .fit)

            ProgressView()
        }
    }

    private var errorView: some View {
        ZStack {
            Rectangle()
                .fill(Color(.secondarySystemFill))
                .aspectRatio(0.72, contentMode: .fit)

            VStack(spacing: 8) {
                SwiftUI.Image(systemName: "exclamationmark.triangle")
                    .font(.title2)

                Text("Page \(self.pageNumber)")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
    }
}
