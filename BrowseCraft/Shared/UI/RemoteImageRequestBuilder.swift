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
    /// 中文注释：视图实际布局尺寸（pt），恒为正——见下面的可失败构造。
    let displaySize: CGSize

    /// 中文注释：**尺寸没测到就不构造标识**（2026-09-18 真机日志逼出来的）。
    /// `displaySize` 由 `onGeometryChange` 回填，初值是 zero，所以 `.task(id:)` 会先带着零尺寸
    /// 触发一次、再在测量后触发第二次：真机日志里同一张封面的 `stage=image` 请求出现 2 到 3 行。
    /// 零尺寸那次**不声明缩略选项，等于按原图解码**，正好抵消掉按单元格尺寸降采样的第一屏收益，
    /// 而且构造本身要扫 Cookie 存储、合并三层请求头、写日志，全部白做一遍。
    /// 因此零尺寸直接返回 nil：调用方的 `.task(id:)` 拿到 nil 就不发请求，占位图继续显示，
    /// 等布局尺寸到位后只构造一次、并且一次就是正确的解码尺寸。
    init?(
        urlString: String,
        refererURLString: String?,
        requestConfig: RequestConfig?,
        additionalHeaders: [String: String]?,
        displaySize: CGSize
    ) {
        guard displaySize.width > 0, displaySize.height > 0 else {
            return nil
        }
        self.urlString = urlString
        self.refererURLString = refererURLString
        self.requestConfig = requestConfig
        self.additionalHeaders = additionalHeaders
        self.displaySize = displaySize
    }

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
    /// 中文注释：`diagnosticViewID` **只进日志，绝不进 `RemoteImageRequestIdentity`**——
    /// 它每个视图实例一个值，混进 identity 会让 `.task(id:)` 的 id 永不相等，
    /// 那样就不是在观测重复构造，而是在制造重复构造。
    static func makeRequest(
        _ identity: RemoteImageRequestIdentity,
        browserRequestHeaderProvider: any BrowserRequestHeaderProviding,
        systemCookieHeaderProvider: any SystemCookieHeaderProviding,
        diagnosticViewID: String
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
        // 中文注释：标识只有在尺寸为正时才构造得出来，所以这里必然声明缩略尺寸——
        // 「先按原图解码一次、再按单元格尺寸解码一次」的旧路径不再存在。
        // aspectFill 语义下按单元格尺寸解码；不足单元格的原图不放大（Nuke 默认）。
        request.userInfo[.thumbnailKey] = ImageRequest.ThumbnailOptions(
            size: identity.displaySize,
            unit: .points,
            contentMode: .aspectFill
        )
        // 中文注释：解码尺寸必须随请求一起可见。`.task(id:)` 的 id 含 `displaySize`，
        // 因此同一张图被构造几次、每次按什么尺寸解码，是这条链路上唯一会变的量——
        // 2026-09-20 真机日志里同一 urlPath 的 `event=request` 出现 2 到 3 行，
        // 而 `event=request` 本身不带尺寸，光看它分不出「尺寸变了」还是「视图重建了」。
        // 零尺寸那一格已由 `RemoteImageRequestIdentity` 的可失败构造挡掉（见其注释），
        // 所以这里记到的必然是两个以上**不同的正尺寸**，或者同一尺寸被重复构造。
        RuleExecutionLogger.log(
            stage: .image,
            event: "request-decode-size",
            fields: [
                "urlPath": request.url?.path ?? "nil",
                "width": Int(identity.displaySize.width.rounded()),
                "height": Int(identity.displaySize.height.rounded()),
                // 中文注释：`viewID` 随 `@State` 与视图身份同生死。同一 urlPath 的多行里
                // **ID 不同 = 视图被重建了**（`@State` 连同 displaySize 一起重置，task 随之重跑）；
                // **ID 相同 = 同一个视图实例跑了多次**，那是 `.task(id:)` 的 id 不稳定。
                // 两者的修法完全不同，所以必须先分开。
                "viewID": diagnosticViewID
            ]
        )
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
