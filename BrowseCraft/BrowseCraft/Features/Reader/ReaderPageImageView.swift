import NukeUI
import SwiftUI

// 中文注释：ReaderPageImageView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：ReaderPageImageView 是 struct，负责本模块中的对应职责。
struct ReaderPageImageView: View {
    let pageURLString: String
    let pageNumber: Int
    let refererURLString: String?
    let requestConfig: RequestConfig?

    var body: some View {
        if let request: ImageRequest = ImageRequestFactory.makeRequest(
            urlString: self.pageURLString,
            refererURLString: self.refererURLString,
            requestConfig: self.requestConfig
        ) {
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
