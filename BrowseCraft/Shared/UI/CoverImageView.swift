import NukeUI
import SwiftUI

// 中文注释：CoverImageView.swift 属于共享界面组件层，用于说明本文件承载的核心职责。

/// 中文注释：共享封面图片视图，负责展示列表和详情中的封面图。
/// 中文注释：NukeUI 只出现在 UI 边界层，领域层和应用层不依赖图片库。
struct CoverImageView: View {
    let urlString: String?
    let refererURLString: String?
    let requestConfig: RequestConfig?

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
        if let urlString: String = self.urlString,
           let request: ImageRequest = ImageRequestFactory.makeRequest(
            urlString: urlString,
            refererURLString: self.refererURLString,
            requestConfig: self.requestConfig
           ) {
            LazyImage(source: request) { state in
                if let image = state.image {
                    image
                        .resizingMode(.aspectFill)
                } else {
                    self.placeholder
                }
            }
        } else {
            self.placeholder
        }
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
