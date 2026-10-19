import Foundation

// 中文注释：有声书单集音频取不到时的分类（docs/design/Audiobook-Player-Page-Redesign-Design.md 第六节，fwq `APP-MEMO-043`）。
// 音频请求由 Infrastructure 的 `SiteBookAudioHTTPClient` 发出，播放页在 Features；两边都看得到 Application，失败值放在这里。
// 只描述「这一集取不到、属于哪一类」，不带错误原文；判定后由播放页决定怎么提示，引擎与 App 都不到别处取内容。

struct BookAudioResourceFailure: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// 站点上这一集的文件不在了（HTTP 404 / 403 / 410，或播放页里解不出音频地址）：重试没用，只能跳过。
        case gone
        /// 网络、超时、HTTP 5xx / 429 等暂时性失败：可以重试。
        case unavailable
    }

    /// 出版物里登记的这一集地址（音频直链或播放页地址），播放页按它对回集序号。
    let chapterURL: URL
    let kind: Kind
    /// 站点回的 HTTP 状态码；不是 HTTP 失败时为 nil。只进日志。
    let statusCode: Int?

    /// 中文注释：只有这三个状态码算「站点上已失效」。403 也算——音频直链的 403 多是防盗链过期或文件下架，换线路之外 App 取不回；
    /// 规则侧的 403（UA、Referer）在取页阶段就会失败，到不了音频请求。
    static let goneStatusCodes: Set<Int> = [403, 404, 410]

    static func kind(statusCode: Int) -> Kind {
        return Self.goneStatusCodes.contains(statusCode) ? .gone : .unavailable
    }
}

/// 中文注释：音频请求失败的回调；由 URLSession 的回调线程调用，接收方自己切回主线程。
typealias BookAudioResourceFailureHandler = @Sendable (BookAudioResourceFailure) -> Void
