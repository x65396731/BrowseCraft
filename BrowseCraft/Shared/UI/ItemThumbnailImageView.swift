import Nuke
import NukeUI
import SwiftUI

// 中文注释：ItemThumbnailImageView 只用于 Library/History item 缩略图，缓存池独立于漫画阅读页图片。
struct ItemThumbnailImageView: View {
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
        if let request: ImageRequest = self.thumbnailRequest {
            LazyImage(source: request) { state in
                if let image = state.image {
                    image
                        .resizingMode(.aspectFill)
                } else {
                    self.placeholder
                }
            }
            .pipeline(ItemThumbnailImageCachePlugin.shared.pipeline)
        } else {
            self.placeholder
        }
    }

    private var thumbnailRequest: ImageRequest? {
        guard let urlString: String = self.urlString,
              let request: ImageRequest = ImageRequestFactory.makeRequest(
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
