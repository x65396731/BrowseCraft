import BrowseCraftCore
import BrowseCraftDomain
import Nuke
import SwiftUI

// 中文注释：封面与缩略图视图共用的「请求标识 → ImageRequest」构造。
// 请求构造要扫 Cookie 存储、合并三层请求头、写调试日志，放在 body 里会随每次渲染重复执行；
// 视图改为用 `.task(id: RemoteImageRequestIdentity)` 只在标识变化时构造一次。
// 显示尺寸也进入标识：Nuke 按 `thumbnail` 选项在解码时降采样，内存缓存键包含该选项，
// 同一地址在不同尺寸的单元格里各自解码、互不串用。

struct RemoteImageRequestIdentity: Hashable {
    let urlString: String
    let refererURLString: String?
    let requestConfig: RequestConfig?
    let additionalHeaders: [String: String]?
    /// 中文注释：视图实际布局尺寸（pt）；未测量到时为 zero，此时不声明缩略尺寸、按原图解码。
    let displaySize: CGSize

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.urlString)
        hasher.combine(self.refererURLString)
        hasher.combine(self.requestConfig)
        hasher.combine(self.additionalHeaders)
        hasher.combine(self.displaySize.width)
        hasher.combine(self.displaySize.height)
    }
}

enum RemoteImageRequestBuilder {
    static func makeRequest(
        _ identity: RemoteImageRequestIdentity,
        browserRequestHeaderProvider: any BrowserRequestHeaderProviding,
        systemCookieHeaderProvider: any SystemCookieHeaderProviding
    ) -> ImageRequest? {
        guard var request: ImageRequest = ImageRequestFactory.makeRequest(
            urlString: identity.urlString,
            refererURLString: identity.refererURLString,
            requestConfig: identity.requestConfig,
            additionalHeaders: identity.additionalHeaders,
            browserRequestHeaderProvider: browserRequestHeaderProvider,
            systemCookieHeaderProvider: systemCookieHeaderProvider
        ) else {
            return nil
        }
        if identity.displaySize.width > 0, identity.displaySize.height > 0 {
            // 中文注释：aspectFill 语义下按单元格尺寸解码；不足单元格的原图不放大（Nuke 默认）。
            request.userInfo[.thumbnailKey] = ImageRequest.ThumbnailOptions(
                size: identity.displaySize,
                unit: .points,
                contentMode: .aspectFill
            )
        }
        return request
    }
}

extension View {
    /// 中文注释：把视图的布局尺寸回写到 binding；封面/缩略图用它决定解码尺寸。
    func measuringDisplaySize(into size: Binding<CGSize>) -> some View {
        return self.onGeometryChange(for: CGSize.self) { proxy in
            return proxy.size
        } action: { newSize in
            if size.wrappedValue != newSize {
                size.wrappedValue = newSize
            }
        }
    }
}
